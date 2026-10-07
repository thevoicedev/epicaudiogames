package com.epicaudiogames.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.Button
import com.epicaudiogames.engine.Commands
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.Play
import com.epicaudiogames.engine.Saved
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.Step
import com.epicaudiogames.engine.Turn
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

/** One entry in the game's transcript. */
sealed interface FeedItem {
    /** A line of the game, shown as it is spoken. */
    data class Spoken(val who: String, val name: String, val text: String) : FeedItem

    /** What the player said, typed or tapped. */
    data class Reply(val text: String) : FeedItem

    data class Note(val text: String) : FeedItem
}

/**
 * One game being played: the engine's game (a map's session, or Nuclear War), the audio, the listening, and what the
 * screen shows. A turn plays its clips while their lines appear in the feed; then the game waits for an answer
 * (listening by itself, as Alexa does), shows its end, or leaves.
 *
 * An engine error doesn't crash the app: the feed gets a note and the game goes back to the list ([failure]).
 */
class GameController(
    context: Context,
    val info: GameInfo,
    private val game: Play,
    private val saves: Saves,
    /** The installed packs this game was opened with (their folders). */
    val packs: List<File>,
    private val onLeave: () -> Unit,
) {
    private val scope = MainScope()
    private val audio = AudioPlayer(context, info.id, packs, onFinished = { finishTurn() }, onInterrupted = { pause() })
    private val listener = Listener(
        context,
        onPartial = { partial = it },
        onHeard = ::heard,
        onSilence = ::silence,
        onLevel = { level = it },
        onUnavailable = { listening = false; micWorks = false },
        onTrouble = ::stopped,
    )

    val feed = mutableStateListOf<FeedItem>()
    var speaking by mutableStateOf(false)
        private set
    var listening by mutableStateOf(false)
        private set
    var level by mutableFloatStateOf(0f)
        private set
    var partial by mutableStateOf("")
        private set
    var ask by mutableStateOf<Ask?>(null)
        private set
    var end by mutableStateOf<End?>(null)
        private set
    var paused by mutableStateOf(false)
        private set
    /** The feed entry being spoken, and how many of its characters have been said (for the highlight). */
    var activeEntry by mutableIntStateOf(-1)
        private set
    var activeChars by mutableIntStateOf(0)
        private set
    var micWorks by mutableStateOf(Listener.available(context))
    var micAllowed by mutableStateOf(false)
    /** What went wrong, when an engine error ended the game; the list tells the player. */
    var failure by mutableStateOf<String?>(null)
        private set

    /**
     * The player is typing an answer (the text box has the focus): the mic doesn't open by itself, and stops if it's
     * listening, as typing is the answer coming.
     */
    var typing = false
        set(value) {
            field = value
            if (value) typed()
        }

    private var turn: Turn? = null
    private var clipLines: List<List<Line>> = emptyList()
    private var revealed: IntArray = IntArray(0)
    private var entryOfLine = mutableMapOf<Pair<Int, Int>, Int>()
    /** Where each line starts in its feed entry: a line can carry on the one before it (see [reveal]). */
    private var offsetOfLine = mutableMapOf<Pair<Int, Int>, Int>()
    private var turnStart = 0
    /** The last line shown carries on into the next one (a list said a name at a time). */
    private var carryOn = false
    private var ticker: Job? = null
    private var silences = 0
    /** When the latest turn began: a tap on an option this soon after is the last tap's double (see [tap]). */
    private var askedAt = 0L

    /** Where a save is kept aside while its place isn't in the map (its pack missing, or not updated yet). */
    private val parked = "${info.id}.parked"

    fun open() {
        val saved = savedPlace()
        val t = try {
            game.open(saved).also { t ->
                if (saved != null && (game.canResume(saved) || (saved.ended && t.end != null))) {
                    feed += FeedItem.Note("Welcome back!")
                }
            }
        } catch (e: Exception) {
            // A save the game can't open: it's cleared, and the game starts afresh.
            feed.clear()
            saves.clear(info.id)
            try {
                game.start()
            } catch (e2: Exception) {
                fail(e2)
                return
            }
        }
        play(t)
    }

    /**
     * The save to open. In a map game, a save at a place the map doesn't have is kept aside rather than overwritten
     * by the game starting again; once the map has its place again (the pack back), it's picked up.
     */
    private fun savedPlace(): Saved? {
        val saved = saves.load(info.id)
        val nodes = (game as? Session)?.map?.nodes ?: return saved
        if (saved != null && !saved.ended && saved.node !in nodes) {
            saves.store(parked, saved)
            return saved
        }
        val back = saves.load(parked) ?: return saved
        if (back.node !in nodes) return saved
        saves.store(info.id, back)
        saves.clear(parked)
        return back
    }

    fun close() {
        ticker?.cancel()
        listener.release()
        audio.release()
        scope.cancel()
    }

    // ----- Turns -----

    private fun play(t: Turn) {
        turn = t
        ask = t.ask         // its options show at once: an answer can cut the voice short
        askedAt = SystemClock.uptimeMillis()
        end = null
        partial = ""
        stopListening()
        val clips = t.steps.filterIsInstance<Step.Play>()
        clipLines = clips.map { it.lines }
        revealed = IntArray(clips.size)
        entryOfLine.clear()
        offsetOfLine.clear()
        turnStart = feed.size
        carryOn = false
        speaking = true
        audio.play(t.steps)          // calls finishTurn when the turn's audio has played (at once if it has none)
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                follow()
                delay(50)
            }
        }
    }

    /** Plays what the game says next; an engine error ends the game. */
    private fun perform(next: () -> Turn) {
        play(attempt(next) ?: return)
    }

    /** What the game says next, or null when an engine error has ended the game. */
    private fun attempt(next: () -> Turn): Turn? = try {
        next()
    } catch (e: Exception) {
        fail(e)
        null
    }

    /**
     * The engine couldn't go on: a note, and back to the list, which tells the player plainly (what went wrong goes to
     * the log). The save is the last turn's.
     */
    private fun fail(e: Exception) {
        ticker?.cancel()
        audio.stop()
        speaking = false
        activeEntry = -1
        Log.w("GameController", "${info.id} went wrong", e)
        feed += FeedItem.Note("Sorry, the game went wrong.")
        failure = "${info.title} went wrong and had to stop."
        leave()
    }

    /** Shows each line as its time comes, and how far into the line the voice is. */
    private fun follow() {
        val pos = audio.position()
        if (pos == null) {
            for (c in 0 until audio.clipsDone()) reveal(c, Double.MAX_VALUE)     // a pause: what came before it
            return
        }
        val (clip, t) = pos
        for (c in 0 until clip) reveal(c, Double.MAX_VALUE)
        reveal(clip, t)
        val lines = clipLines.getOrNull(clip) ?: return
        val i = lines.indexOfLast { it.at <= t }
        if (i < 0) return
        val line = lines[i]
        activeEntry = entryOfLine[clip to i] ?: -1
        val progress = if (line.len > 0) ((t - line.at) / line.len).coerceIn(0.0, 1.0) else 1.0
        activeChars = (offsetOfLine[clip to i] ?: 0) + (line.text.length * progress).toInt()
    }

    /**
     * Shows the clip's lines whose time has come. A line that carries on a sentence (the same speaker's previous line
     * in this turn ends with a comma, or is marked to carry on, as in a list of names made of one clip per name)
     * joins that entry.
     */
    private fun reveal(clip: Int, t: Double) {
        val lines = clipLines.getOrNull(clip) ?: return
        while (revealed[clip] < lines.size && lines[revealed[clip]].at <= t) {
            val line = lines[revealed[clip]]
            val key = clip to revealed[clip]
            val last = feed.lastOrNull()
            if (last is FeedItem.Spoken && feed.lastIndex >= turnStart && last.who == line.who &&
                (last.text.endsWith(",") || carryOn)) {
                entryOfLine[key] = feed.lastIndex
                offsetOfLine[key] = last.text.length + 1
                feed[feed.lastIndex] = last.copy(text = "${last.text} ${line.text}")
            } else {
                entryOfLine[key] = feed.size
                offsetOfLine[key] = 0
                feed += FeedItem.Spoken(line.who, game.who[line.who] ?: line.who, line.text)
            }
            carryOn = line.more
            revealed[clip]++
        }
    }

    private fun finishTurn() {
        ticker?.cancel()
        for (c in clipLines.indices) reveal(c, Double.MAX_VALUE)
        speaking = false
        activeEntry = -1
        val t = turn ?: return
        when {
            t.quit -> {
                // "Leave" keeps the player's place (the question they answered), as an ended Alexa session did. A
                // plain quit isn't picked up again, but its save keeps the map's "keep" variables for next time.
                val s = game.save()
                saves.store(info.id, if (t.keep) s else s.copy(ended = true))
                leave()
            }
            t.end != null -> {
                end = t.end
                saves.store(info.id, game.save())
            }
            t.ask != null -> {
                ask = t.ask
                saves.store(info.id, game.save())
                if (!paused && !typing) listen()
            }
        }
    }

    // ----- Answers -----

    /**
     * A typed answer or a tapped option (also while the voice is still talking: it stops). [shown] is what the reply
     * shows: an option's label. Answering while paused carries on.
     */
    fun answer(text: String, shown: String = text) {
        if (text.isBlank() || ask == null) return
        if (Commands.isPause(text)) {
            pause()
            return
        }
        paused = false
        stopListening()
        if (speaking) {
            audio.stop()
            ticker?.cancel()
            for (c in clipLines.indices) reveal(c, Double.MAX_VALUE)
            speaking = false
            activeEntry = -1
        }
        feed += FeedItem.Reply(shown.trim())
        silences = 0
        perform { game.answer(text) }
    }

    /**
     * A tapped option (a chip at the end of the chat): it sends its value, and the reply shows its label. A tap this
     * soon after a new question is the last tap's double (its options show at once, often where the last ones were),
     * so it's let go.
     */
    fun tap(button: Button) {
        if (SystemClock.uptimeMillis() - askedAt < DOUBLE_TAP_MS) return
        answer(button.value, button.label)
    }

    /** The recogniser's guesses, best first: the first that the question takes, else the best. */
    private fun heard(guesses: List<String>) {
        if (!listening) return          // a listen that's over
        listening = false
        partial = ""
        if (ask == null) return
        if (guesses.isEmpty()) {
            // Speech it couldn't make out: "sorry?" (the game's else); twice running, the game waits for a tap.
            feed += FeedItem.Reply("…")
            if (++silences >= 2) {
                pause()
                return
            }
            val at = turn?.node
            val t = attempt { game.answer("") } ?: return
            // Only at the same question do they run on: a new one gets its own "say it again".
            if (t.ask == null || t.node != at) silences = 0
            play(t)
            return
        }
        val best = guesses.firstOrNull { g -> Commands.isPause(g) || understands(g) } ?: guesses.first()
        answer(best)
    }

    private fun understands(said: String) = try {
        game.understands(said)
    } catch (e: Exception) {
        false
    }

    /** Nobody answered: the question again; after a second silence, the game waits for a tap. */
    private fun silence() {
        if (!listening) return          // a listen that's over
        listening = false
        partial = ""
        if (ask == null) return
        silences++
        if (silences >= 2) pause() else perform { game.silence() }
    }

    /** Passing trouble with the recogniser, nothing to do with the player: the listen just ends (the mic tries again). */
    private fun stopped() {
        listening = false
        partial = ""
        level = 0f
    }

    // ----- Listening -----

    /** Listens for an answer. Calling it while listening does nothing. */
    fun listen() {
        if (!micAllowed || !micWorks || ask == null || speaking || listening) return
        partial = ""
        listening = true
        listener.start()
    }

    private fun stopListening() {
        listener.stop()
        listening = false
        level = 0f
    }

    /** The mic allowed now (the player said yes, or turned it on in Settings): the game listens if it's waiting. */
    fun allowMic() {
        micAllowed = true
        if (!paused && !typing) listen()
    }

    /** A key typed in the text box: listening stops, and the silences count from nothing again. */
    fun typed() {
        if (listening) stopListening()
        silences = 0
    }

    /** The mic button: listen now (cutting the voice short), or stop listening. After a failure, it tries again. */
    fun mic() {
        micWorks = true
        when {
            listening -> stopListening()
            speaking -> {
                skip()              // which listens, unless the player is typing
                listen()
            }
            else -> listen()
        }
    }

    /** Stops the voice and shows the rest of the turn's lines. */
    fun skip() {
        if (!speaking) return
        audio.stop()
        paused = false
        finishTurn()
    }

    /** "Stop", the app going to the background, or a second silence: everything waits for a tap. */
    fun pause() {
        paused = true
        stopListening()
        if (speaking) {
            audio.stop()
            finishTurn()        // the rest of the lines, and the question (or the end) waiting
        }
    }

    /** Back from a pause: the question again. */
    fun carryOn() {
        paused = false
        silences = 0
        if (speaking) return
        if (ask != null) perform { game.silence() }
    }

    // ----- Ends -----

    fun playAgain() {
        feed.clear()
        feed += FeedItem.Note("Starting again!")
        paused = false
        silences = 0
        val e = end
        perform { if (e?.kind == "gameover" && e.retry != null) game.restart(e.retry) else game.restart() }
    }

    /** The menu's "Start again": the game from its very beginning. */
    fun startAgain() {
        audio.stop()
        feed.clear()
        feed += FeedItem.Note("Starting again!")
        paused = false
        silences = 0
        perform { game.restart() }
    }

    val canGoOn: Boolean
        get() = end?.let { e -> e.kind == "chapter" && e.next?.let { game.hasChapter(it) } == true } ?: false

    fun nextChapter() {
        feed += FeedItem.Note("Next chapter")
        paused = false
        silences = 0
        perform { game.nextChapter() }
    }

    /** Back to the game list (posted, as it closes this game's player from inside its own callbacks). */
    fun leave() {
        stopListening()
        audio.stop()
        Handler(Looper.getMainLooper()).post(onLeave)
    }

    private companion object {
        /** A second tap this soon after a new question is a double tap. */
        const val DOUBLE_TAP_MS = 500L
    }
}
