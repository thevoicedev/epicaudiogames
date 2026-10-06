package com.epicaudiogames.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.Commands
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.Matcher
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.Step
import com.epicaudiogames.engine.Turn
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** One entry in the game's transcript. */
sealed interface FeedItem {
    /** A line of the game, shown as it is spoken. */
    data class Spoken(val who: String, val name: String, val text: String) : FeedItem

    /** What the player said, typed or tapped. */
    data class Reply(val text: String) : FeedItem

    data class Note(val text: String) : FeedItem
}

/**
 * One game being played: the engine's session, the audio, the listening, and what the screen shows. A turn plays
 * its clips while their lines appear in the feed; then the game waits for an answer (listening by itself, as
 * Alexa does), shows its end, or leaves.
 */
class GameController(
    context: Context,
    val info: GameInfo,
    val map: GameMap,
    private val saves: Saves,
    private val onLeave: () -> Unit,
) {
    private val scope = MainScope()
    private val session = Session(map)
    private val audio = AudioPlayer(context, info.id) { finishTurn() }
    private val listener = Listener(
        context,
        onPartial = { partial = it },
        onHeard = ::heard,
        onSilence = ::silence,
        onLevel = { level = it },
        onUnavailable = { listening = false; micWorks = false },
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

    private var turn: Turn? = null
    private var clipLines: List<List<Line>> = emptyList()
    private var revealed: IntArray = IntArray(0)
    private var entryOfLine = mutableMapOf<Pair<Int, Int>, Int>()
    /** Where each line starts in its feed entry: a line can carry on the one before it (see [reveal]). */
    private var offsetOfLine = mutableMapOf<Pair<Int, Int>, Int>()
    private var turnStart = 0
    private var ticker: Job? = null
    private var silences = 0

    fun open() {
        val saved = saves.load(info.id)
        val turn = if (saved != null && !saved.ended && map.nodes[saved.node]?.ask != null) {
            feed += FeedItem.Note("Welcome back!")
            session.resume(saved)
        } else {
            session.start()
        }
        play(turn)
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
        ask = t.ask         // its buttons show at once: an answer can cut the voice short
        end = null
        partial = ""
        stopListening()
        val clips = t.steps.filterIsInstance<Step.Play>()
        clipLines = clips.map { it.lines }
        revealed = IntArray(clips.size)
        entryOfLine.clear()
        offsetOfLine.clear()
        turnStart = feed.size
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
     * in this turn ends with a comma, as in a list of names made of one clip per name) joins that entry.
     */
    private fun reveal(clip: Int, t: Double) {
        val lines = clipLines.getOrNull(clip) ?: return
        while (revealed[clip] < lines.size && lines[revealed[clip]].at <= t) {
            val line = lines[revealed[clip]]
            val key = clip to revealed[clip]
            val last = feed.lastOrNull()
            if (last is FeedItem.Spoken && feed.lastIndex >= turnStart && last.who == line.who && last.text.endsWith(",")) {
                entryOfLine[key] = feed.lastIndex
                offsetOfLine[key] = last.text.length + 1
                feed[feed.lastIndex] = last.copy(text = "${last.text} ${line.text}")
            } else {
                entryOfLine[key] = feed.size
                offsetOfLine[key] = 0
                feed += FeedItem.Spoken(line.who, map.who[line.who] ?: line.who, line.text)
            }
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
                // "Leave" keeps the player's place (the question they answered), as an ended Alexa session did.
                if (t.keep) saves.store(info.id, session.save()) else saves.clear(info.id)
                leave()
            }
            t.end != null -> {
                end = t.end
                saves.store(info.id, session.save())
            }
            t.ask != null -> {
                ask = t.ask
                saves.store(info.id, session.save())
                if (!paused) listen()
            }
        }
    }

    // ----- Answers -----

    /** A typed answer or a tapped button (also while the voice is still talking: it stops). */
    fun answer(text: String) {
        if (text.isBlank() || ask == null) return
        if (Commands.isPause(text)) {
            pause()
            return
        }
        stopListening()
        if (speaking) {
            audio.stop()
            ticker?.cancel()
            for (c in clipLines.indices) reveal(c, Double.MAX_VALUE)
            speaking = false
            activeEntry = -1
        }
        feed += FeedItem.Reply(text.trim())
        silences = 0
        play(session.answer(text))
    }

    /** The recogniser's guesses, best first: the first that the question takes, else the best. */
    private fun heard(guesses: List<String>) {
        listening = false
        partial = ""
        val a = ask ?: return
        if (guesses.isEmpty()) {
            // Speech it couldn't make out: "sorry?" (the game's else); twice running, the game waits for a tap.
            feed += FeedItem.Reply("…")
            if (++silences >= 2) pause() else play(session.answer(""))
            return
        }
        val best = guesses.firstOrNull { g ->
            Commands.isPause(g) || Matcher.match(map, a, session.vars, g).let { it.index != null || it.repeat }
        } ?: guesses.first()
        answer(best)
    }

    /** Nobody answered: the question again; after a second silence, the game waits for a tap. */
    private fun silence() {
        listening = false
        partial = ""
        if (ask == null) return
        silences++
        if (silences >= 2) pause() else play(session.silence())
    }

    // ----- Listening -----

    fun listen() {
        if (!micAllowed || !micWorks || ask == null || speaking) return
        partial = ""
        listening = true
        listener.start()
    }

    private fun stopListening() {
        listener.stop()
        listening = false
        level = 0f
    }

    /** The mic button: listen now (cutting the voice short), or stop listening. After a failure, it tries again. */
    fun mic() {
        micWorks = true
        when {
            listening -> stopListening()
            speaking -> {
                skip()
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
        if (ask != null) play(session.silence())
    }

    // ----- Ends -----

    fun playAgain() {
        feed.clear()
        feed += FeedItem.Note("Starting again!")
        paused = false
        val e = end
        play(if (e?.kind == "gameover" && e.retry != null) session.restart(e.retry) else session.restart())
    }

    /** The menu's "Start again": the game from its very beginning. */
    fun startAgain() {
        audio.stop()
        feed.clear()
        feed += FeedItem.Note("Starting again!")
        paused = false
        silences = 0
        play(session.restart())
    }

    val canGoOn: Boolean
        get() = end?.let { it.kind == "chapter" && it.next != null && it.next in map.nodes } ?: false

    fun nextChapter() {
        feed += FeedItem.Note("Next chapter")
        play(session.nextChapter())
    }

    /** Back to the game list (posted, as it closes this game's player from inside its own callbacks). */
    fun leave() {
        stopListening()
        audio.stop()
        Handler(Looper.getMainLooper()).post(onLeave)
    }
}
