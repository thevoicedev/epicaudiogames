package com.epicaudiogames.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.StringRes
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
import com.epicaudiogames.app.analytics.Event
import com.epicaudiogames.app.analytics.Events
import com.epicaudiogames.app.analytics.MicAsked
import com.epicaudiogames.app.analytics.NoAnalytics
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

/** One entry in the game's transcript. */
sealed interface FeedItem {
    /**
     * What a screen reader says for the entry, read as one element (docs/DESIGN.md › Game › Transcript; FeedView.swift
     * reads the same), in the app's [words]. Never announced as it comes: the game is already saying it.
     */
    fun readAs(words: Words): String

    /**
     * A line of the game, shown as it is spoken. It's read with its speaker first ("Gribbo: …"), even where the name
     * isn't shown; the narrator's lines, and lines with no name, are read as they are.
     */
    data class Spoken(val who: String, val name: String, val text: String) : FeedItem {
        override fun readAs(words: Words) =
            if (name.isBlank() || who == "NARRATOR") text else words.text(R.string.line_with_speaker, name, text)
    }

    /** What the player said, typed or tapped: read "You said: …". */
    data class Reply(val text: String) : FeedItem {
        override fun readAs(words: Words) = words.text(R.string.reply_said, text)
    }

    /** The app's own line between the game's ("Welcome back!"): [text] is its string. */
    data class Note(@StringRes val text: Int) : FeedItem {
        override fun readAs(words: Words) = words.text(text)
    }
}

/**
 * One game being played: the engine's game (a map's session, or Nuclear War), the audio, the listening, and what the
 * screen shows. A turn plays its clips while their lines appear in the feed; then the game waits for an answer
 * (listening by itself, as Alexa does, unless [listensByItself] says not to), shows its end, or leaves.
 *
 * The microphone never opens without the listening sound and its tick, and closes with the falling one when the
 * recogniser ends the listen or the player turns it off (not when a new turn, typing, a pause or leaving stops it):
 * docs/DESIGN.md › Sounds, haptics and the microphone, as [settings] say. Each turn plays at the voice speed, its
 * music at the music volume; the player has the answer time chosen to start talking.
 *
 * An engine error doesn't crash the app: the feed gets a note and the game goes back to the list ([failure]).
 *
 * What happens in it goes to [onEvent], for the usage data (docs/DESIGN.md › Usage data): the game opened, an end
 * reached (and the free part's end), the next chapter, a restart, the game going wrong, and, as it closes, how it went
 * (turns, time, and how many answers were spoken, typed and tapped, and how many questions went unanswered: counts,
 * never an answer).
 */
class GameController(
    context: Context,
    val info: GameInfo,
    private val game: Play,
    private val saves: Saves,
    /** The installed packs this game was opened with (their folders). */
    val packs: List<File>,
    private val onLeave: () -> Unit,
    /**
     * Whether the game opens the mic by itself once a question is asked: the app asks MicPolicy.kt's listensByItself
     * (by default, not with TalkBack on, which the recogniser would hear). Asked each time, as the setting and the
     * screen reader can change mid-game. The player can always open it: the mic button, the circle, the headphones'
     * button. iOS: GameController.swift's listensByItself.
     */
    private val listensByItself: () -> Boolean = { true },
    /**
     * What happens in the game, for the usage data: an event's name and its details (analytics/Events.kt makes them;
     * the app's Analytics.track takes them; by default, as in tests, they go nowhere). iOS: GameController.swift's
     * onEvent.
     */
    private val onEvent: (String, Map<String, Any>) -> Unit = NoAnalytics::track,
    /**
     * The player's settings (the app's, AppSettings.kt): the listening sounds and tick, the voice speed, the music
     * volume and the time to answer, each read as it's needed, so a change applies from the next turn or listen.
     */
    private val settings: AppSettings = AppSettings(MemoryPrefs()),
    /**
     * What it hears answers with (Listening.kt): the phone's speech recogniser, or what the app says instead (none, in
     * a test; a debug build's script, DebugLaunch). iOS: AppModel.Hearing, as it makes the game's listener.
     */
    hearing: Hearing = Hearing.SPEECH,
) {
    private val scope = MainScope()
    /** The app's words, for the notes and replies it adds to the feed, and what went wrong. */
    private val words = Words.of(context)
    private val audio = AudioPlayer(context, info.id, packs, onFinished = { finishTurn() }, onInterrupted = { pause() })
    /** The service, notification, media session and wake lock that let the game go on with the screen off. */
    private val background = BackgroundPlay(context, this)
    private val earcons = Earcons(context)
    private val haptics = Haptics(context)
    private val listener: Listening = hearing.listener(
        context,
        ListenerEvents(
            onPartial = { partial = it },
            onHeard = ::heard,
            onSilence = ::silence,
            onLevel = { level = it },
            onUnavailable = ::unavailable,
            onTrouble = ::stopped,
            cue = ::opening,
        ),
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
    var micWorks by mutableStateOf(listener.available)
    var micAllowed by mutableStateOf(false)
    /**
     * Whether it hears through the microphone, which Android asks the player for (the recogniser); one that doesn't (a
     * debug build's script) counts as allowed, and the screen asks for nothing.
     */
    val micNeedsPermission: Boolean get() = listener.needsPermission
    /** What went wrong, when an engine error ended the game; the list tells the player. */
    var failure by mutableStateOf<String?>(null)
        private set

    /**
     * What the game's one button does now, and what TalkBack calls it: the talking circle's tap and the notification's
     * button ([CircleAction]). Null at an end.
     */
    val circleAction: CircleAction?
        get() = CircleAction.of(paused, speaking, listening, end != null, ask != null, micAllowed, micWorks)

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
    /** How many times this listen has gone on after the recogniser gave up early (time to answer; [silence]). */
    private var listenedOn = 0
    /** When the latest turn began: a tap on an option this soon after is the last tap's double (see [tap]). */
    private var askedAt = 0L

    // This play of the game, for the usage data's game_leave as it closes: counts, never what was said.
    /** When it opened (elapsedRealtime); 0 if it never did. */
    private var openedAt = 0L
    private var turns = 0
    private var answersSpoken = 0
    private var answersTyped = 0
    private var answersTapped = 0
    /** Questions that got no answer (every silence that counted: [silences] starts again from each answer). */
    private var unanswered = 0
    /** The turn whose end was reached last, or shown again as the game opened: its game_end goes once. */
    private var reached: Turn? = null
    private var closed = false

    /** Where a save is kept aside while its place isn't in the map (its pack missing, or not updated yet). */
    private val parked = "${info.id}.parked"

    fun open() {
        background.start()
        openedAt = SystemClock.elapsedRealtime()
        val saved = savedPlace()
        var resumed = false
        val t = try {
            game.open(saved).also { t ->
                if (saved != null && (game.canResume(saved) || (saved.ended && t.end != null))) {
                    feed += FeedItem.Note(R.string.note_welcome_back)
                    resumed = true
                }
            }
        } catch (e: Exception) {
            // A save the game can't open: it's cleared, and the game starts afresh.
            feed.clear()
            saves.clear(info.id)
            try {
                game.start()
            } catch (e2: Exception) {
                emit(Events.gameOpen(info.id, resumed = false))
                fail(e2)
                return
            }
        }
        emit(Events.gameOpen(info.id, resumed))
        // Opened at an end reached before (a chapter's end, its next chapter now here): not reached again.
        if (resumed && t.end != null) reached = t
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

    /** The game closes (left, or the app's model gone): how it went is usage data, once. */
    fun close() {
        if (!closed) {
            closed = true
            val seconds = if (openedAt == 0L) 0 else (SystemClock.elapsedRealtime() - openedAt) / 1000
            emit(Events.gameLeave(info.id, turn?.node, turns, seconds, answersSpoken, answersTyped, answersTapped,
                unanswered))
        }
        ticker?.cancel()
        background.stop()
        listener.release()
        audio.release()
        scope.cancel()
    }

    /** Something happened in the game: to [onEvent]. */
    private fun emit(e: Event) = onEvent(e.name, e.props)

    // ----- Turns -----

    private fun play(t: Turn) {
        turn = t
        turns++
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
        // At the voice speed and music volume the player has now (Settings › Sound and voice).
        audio.setSpeed(settings.voiceSpeed)
        audio.setMusicVolume(settings.musicVolume)
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
        emit(Events.gameError(info.id, turn?.node))
        feed += FeedItem.Note(R.string.note_went_wrong)
        failure = words.text(R.string.game_went_wrong, info.title)
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
                if (reached !== t) {
                    reached = t
                    t.end?.let { e -> ended(e, t.node) }
                }
            }
            t.ask != null -> {
                ask = t.ask
                saves.store(info.id, game.save())
                if (!paused && !typing && listensByItself()) listen()
            }
        }
    }

    /** An end reached, for the usage data: which, and where; and the free part's end, if a pack has what comes next. */
    private fun ended(e: End, node: String) {
        emit(Events.gameEnd(info.id, e.kind, node))
        e.locked?.let { pack -> if (!canGoOn) emit(Events.lockedEnd(info.id, pack)) }
    }

    // ----- Answers -----

    /** How an answer came, for the usage data's counts. */
    private enum class Given { SPOKEN, TYPED, TAPPED }

    /**
     * A typed answer (also while the voice is still talking: it stops). [shown] is what the reply shows. Answering
     * while paused carries on.
     */
    fun answer(text: String, shown: String = text) = give(text, shown, Given.TYPED)

    /** An answer, spoken, typed or tapped ([how], which only the usage data's counts care about). */
    private fun give(text: String, shown: String, how: Given) {
        if (text.isBlank() || ask == null) return
        if (Commands.isPause(text)) {
            pause()
            return
        }
        when (how) {
            Given.SPOKEN -> answersSpoken++
            Given.TYPED -> answersTyped++
            Given.TAPPED -> answersTapped++
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
        give(button.value, button.label, Given.TAPPED)
    }

    /** The recogniser's guesses, best first: the first that the question takes, else the best. */
    private fun heard(guesses: List<String>) {
        if (!listening) return          // a listen that's over
        listening = false
        partial = ""
        closing()
        if (ask == null) return
        if (guesses.isEmpty()) {
            // Speech it couldn't make out: "sorry?" (the game's else); twice running, the game waits for a tap.
            feed += FeedItem.Reply(words.text(R.string.reply_unclear))
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
        give(best, best, Given.SPOKEN)
    }

    private fun understands(said: String) = try {
        game.understands(said)
    } catch (e: Exception) {
        false
    }

    /**
     * Nobody answered: the question again; after a second silence, the game waits for a tap. A recogniser that gave up
     * before the player's time to answer is up (Settings) listens on instead, without a sound: the same listen.
     */
    private fun silence() {
        if (!listening) return          // a listen that's over
        if (ask != null && listensAgain(listener.heardFor(), settings.answerTime.millis, listenedOn)) {
            listenedOn++
            partial = ""
            listener.start(withCue = false)
            return
        }
        listening = false
        partial = ""
        closing()
        if (ask == null) return
        silences++
        unanswered++
        if (silences >= 2) pause() else perform { game.silence() }
    }

    /** Passing trouble with the recogniser, nothing to do with the player: the listen just ends (the mic tries again). */
    private fun stopped() {
        if (listening) closing()
        listening = false
        partial = ""
        level = 0f
    }

    /** No recogniser that can work now (none for the language, or no connection): answers are typed or tapped. */
    private fun unavailable() {
        if (listening) closing()
        listening = false
        micWorks = false
    }

    // ----- Listening -----

    /**
     * Listens for an answer: the listening sound first, then the recogniser (Listener). However the mic opens (by
     * itself, the mic button, the circle, the headphones' or the notification's button), it comes here. Calling it
     * while listening does nothing.
     */
    fun listen() {
        if (!micAllowed || !micWorks || ask == null || speaking || listening) return
        partial = ""
        listening = true
        listenedOn = 0
        // Longer and Longest also ask the recogniser to wait longer for the rest of an answer.
        listener.settleMs = if (settings.answerTime == AnswerTime.NORMAL) null else SETTLE_MS
        listener.start()
    }

    /**
     * The mic opening (Listener's cue, once a headset's link is up): the tick and the rising sound, as Settings say,
     * then [done] once the sound has been heard out (at once with the sounds off), when the recogniser starts.
     */
    private fun opening(callLink: Boolean, done: () -> Unit): () -> Unit {
        if (settings.listeningHaptics) haptics.micOpened()
        if (!settings.listeningSounds) {
            done()
            return {}
        }
        return earcons.play(Earcon.LISTEN_START, callLink, done)
    }

    /**
     * The mic closing because the recogniser ended the listen or the player turned it off: the falling sound and a
     * softer tick, as Settings say. Not when the game stops listening itself (a new turn, typing, a pause, leaving).
     */
    private fun closing() {
        if (settings.listeningHaptics) haptics.micClosed()
        if (settings.listeningSounds) earcons.play(Earcon.LISTEN_STOP)
    }

    /** Settings › Voice speed changed: the voice (and the music under it) goes at the new speed at once. */
    fun speedChanged() = audio.setSpeed(settings.voiceSpeed)

    /** Settings › Music volume changed: the music playing now follows it at once. */
    fun musicVolumeChanged() = audio.setMusicVolume(settings.musicVolume)

    private fun stopListening() {
        listener.stop()
        listening = false
        level = 0f
    }

    /**
     * The mic allowed now (the player said yes, or turned it on in Settings): the game listens if it's waiting and
     * listens by itself. When the player asked for the mic with a tap ([listen]: the mic button, or the circle), it
     * does what the tap would have done with the mic allowed, cutting the voice short, whatever [listensByItself]
     * says; but not over a pause.
     */
    fun allowMic(listen: Boolean = false) {
        micAllowed = true
        background.micAllowed()
        if (paused) return
        if (listen) {
            if (speaking) skip()
            this.listen()
        } else if (!typing && listensByItself()) {
            this.listen()
        }
    }

    /** What the player said to Android's microphone question, asked as the game opened or by a tap: usage data. */
    fun micAnswered(granted: Boolean) = emit(Events.micPermission(granted, MicAsked.GAME))

    /** A key typed in the text box: listening stops, and the silences count from nothing again. */
    fun typed() {
        if (listening) stopListening()
        silences = 0
    }

    /** The mic button: listen now (cutting the voice short), or stop listening. After a failure, it tries again. */
    fun mic() {
        micWorks = true
        when {
            listening -> {
                stopListening()
                closing()           // the player turned it off
            }
            speaking -> {
                skip()              // which may listen already: by itself, unless the player is typing
                listen()
            }
            else -> listen()
        }
    }

    /**
     * The talking circle, tapped; also the headphones' button and the notification's (see [BackgroundPlay]): carries on
     * when paused, skips while the voice speaks (then listens, if it listens by itself), and otherwise is the mic
     * button: listen, or stop listening. What it does, and its name, is [circleAction]; with the mic not allowed, the
     * screen asks for it instead.
     */
    fun circle() {
        when {
            paused -> carryOn()
            speaking -> skip()
            else -> mic()
        }
    }

    /** Stops the voice and shows the rest of the turn's lines. */
    fun skip() {
        if (!speaking) return
        audio.stop()
        paused = false
        finishTurn()
    }

    /**
     * "Stop", a second silence, the audio focus lost (a call), the headphones taken out, the store sheet or a web page
     * opened: everything waits for a tap. The screen going off or the app going to the background doesn't pause: the
     * game goes on in the pocket ([BackgroundPlay]).
     */
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
        emit(Events.gameRestart(info.id))
        feed.clear()
        feed += FeedItem.Note(R.string.note_starting_again)
        paused = false
        silences = 0
        val e = end
        perform { if (e?.kind == "gameover" && e.retry != null) game.restart(e.retry) else game.restart() }
    }

    /** The menu's "Start again": the game from its very beginning. */
    fun startAgain() {
        emit(Events.gameRestart(info.id))
        audio.stop()
        feed.clear()
        feed += FeedItem.Note(R.string.note_starting_again)
        paused = false
        silences = 0
        perform { game.restart() }
    }

    val canGoOn: Boolean
        get() = end?.let { e -> e.kind == "chapter" && e.next?.let { game.hasChapter(it) } == true } ?: false

    fun nextChapter() {
        end?.next?.let { emit(Events.chapterNext(info.id, it)) }
        feed += FeedItem.Note(R.string.next_chapter)
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
        /**
         * With a longer time to answer: how long the recogniser is asked to wait, once the player stops talking, before
         * the answer counts as complete (iOS: Endpointer's settle, 2 s for Longer and Longest).
         */
        const val SETTLE_MS = 2_000L
    }
}
