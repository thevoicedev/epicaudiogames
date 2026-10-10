package com.epicaudiogames.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.viewModelScope
import com.epicaudiogames.app.ui.AppStart
import com.epicaudiogames.app.ui.Tab
import kotlinx.coroutines.Job
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.lang.ref.WeakReference

/**
 * Plays the app without touching it, from its launch's intent extras (debug builds only; a release build's DebugLaunch,
 * src/release/, does nothing), for the store screenshots (tools/store_shots.py, brand/scenes.json), the preview video
 * (tools/make_preview.py) and checks. The extras have the iOS app's launch arguments' names
 * (ios/EpicAudioGames/Debug/DebugLaunch.swift):
 * - `EpicReset`: every game's save is cleared, so no card on the list is "In progress", and the settings stored are
 *   forgotten, so a run that changed one (a theme, a switch) doesn't leave it for the next;
 * - `EpicFresh`: the game's save is cleared first;
 * - `EpicOpen <game id>`: opens the game;
 * - `EpicSay "yes|no|fight"`: answers each question in turn with these (typed), once the game waits; a last answer
 *   ending in "*" ("yes*") is given again and again, until the game ends;
 * - `EpicSayDelay <seconds>`: each of those answers waits this long after its question is asked (0: at once);
 * - `EpicSkip`: skips each turn's voice as soon as it plays;
 * - `EpicPauseAt <seconds>`: pauses the game that long after it opens;
 * - `EpicStore <game id>`: opens that game's store sheet;
 * - `EpicMic off`: the games don't listen (as on a phone with no recogniser: no microphone, no permission asked);
 * - `EpicHear "~|yes|?"`: the games hear these instead of the mic (ScriptedListener), the mic counting as allowed;
 * - `EpicPacksURL <url>`: the pack server, in place of the build's;
 *
 * and the way in, the tabs and the look (docs/DESIGN.md's; the automated runs start with `EpicReset`, `EpicNoIntro`,
 * `EpicSkipOnboarding` and `EpicAnalytics off`):
 * - `EpicNoIntro`: no intro this launch; `EpicIntro`: the intro, even so (and even with Settings › Play the intro sound
 *   off);
 * - `EpicSkipOnboarding`: no onboarding this launch (nothing stored); `EpicOnboarding`: onboarding, from its first
 *   page, even after it was finished (and even with EpicSkipOnboarding);
 * - `EpicTab <games|shop|help|settings>`: the tab the app starts on; `EpicHelp <topic id>`: the Help tab on that topic
 *   ("voice"; an id that isn't one: its list);
 * - `EpicTheme <system|light|dark|contrast>`, `EpicTextSize <1.0|1.15|1.3>` and `EpicSpeed <0.75 … 2>` (the voice
 *   speed): those settings, stored as if picked in Settings (the next EpicReset forgets them);
 * - `EpicAnalytics off`, or a server's address: read by UsageData.launchedWith (analytics/Analytics.kt): off, nothing
 *   is recorded or sent this run (the setting itself is left as it is); an address, usage data goes there.
 *
 * A flag is `--ez EpicSkip true` (or `--es EpicSkip YES`); the rest are text (`--es`, numbers too, or `--ef`/`--ei`):
 * `adb shell am start -S -W -n com.epicaudiogames.app/.MainActivity --ez EpicReset true --ez EpicNoIntro true
 * --ez EpicSkipOnboarding true --es EpicAnalytics off --es EpicOpen noodle-rush --ez EpicSkip true --es EpicHear Yes`.
 * A launch for the activity already showing (`--activity-single-top`) acts on its extras again ([newIntent]), but for
 * the way in, which is a cold start's.
 *
 * What the app is doing goes to the log, tag EpicShots, for the tools to wait for (`adb logcat -s EpicShots`):
 * - `intro`, `onboarding`: shown; `tab <key>`: the tabs showing, on that tab (and each time it changes);
 *   `store-sheet <game id>`: the store sheet open; `open <game id>`: a game open. Each once the system's splash has
 *   gone ([splashGone]), after the frame that draws it.
 * - In a game: `asking` (a turn's voice is over and the game waits for an answer) or `spoken` (it's over, with no
 *   question: an end, or a turn that carries on), one of them for each turn; `listening` (the mic opening, with its
 *   sound); `heard "…"`, `heard ?` or `silence` (ScriptedListener, as it reports); `paused`; `end <kind>` (the end panel).
 * - `script-done`: the launch's extras have all been acted on (a game's answers given, its pause made).
 * A turn so short it never shows as speaking (no audio at all) has neither line, unless it's the game's first: its
 * state as the game shows gives the line (its voice may have been skipped already).
 */
object DebugLaunch {
    private const val TAG = "EpicShots"

    /** This launch's extras, read as it starts ([launching]), or by a new intent. */
    private var options = Options(null)
    /** The model the log lines follow (one at a time), and the script playing in it. */
    private var watched = WeakReference<AppModel>(null)
    private var script: Job? = null

    /**
     * MainActivity.onCreate, before the app's model is made, for a launch (not the activity made again): EpicReset,
     * then the settings the launch gives (stored, so the model reads them as the player's), and with a script or no
     * mic, nothing asked of Android (its dialogs would cover the screen).
     */
    fun launching(context: Context, intent: Intent?) {
        options = Options(intent?.extras)
        if (options.isEmpty) return
        Log.i(TAG, "launch: ${options.names.joinToString(" ")}")
        if (options.flag("EpicReset")) {
            Saves(context).clearAll()
            SharedPrefs(context).clear()
        }
        settings(AppSettings(SharedPrefs(context)), options)
        if (options.hearing != null) {
            Permissions.micAsked = true
            Permissions.notificationsAsked = true
        }
    }

    /** How the games hear, if the launch says (EpicMic off, EpicHear); null for the phone's recogniser. */
    val hearing: Hearing? get() = options.hearing

    /** The pack server, if the launch names one (EpicPacksURL). */
    val packsUrl: String? get() = options.text("EpicPacksURL")

    /**
     * What shows before the tabs this launch (AppModel, as it's made): [start] (from the settings) with EpicNoIntro,
     * EpicIntro, EpicSkipOnboarding and EpicOnboarding.
     */
    fun start(start: AppStart): AppStart {
        var intro = start.intro
        var onboarding = start.onboarding
        if (options.flag("EpicNoIntro")) intro = false
        if (options.flag("EpicIntro")) intro = true
        if (options.flag("EpicSkipOnboarding")) onboarding = false
        if (options.flag("EpicOnboarding")) onboarding = true
        return AppStart(intro, onboarding)
    }

    /**
     * The model made for a launch: the tab, the log lines, then a store sheet or a game played by itself. (In that
     * order, so the first tab line is the launch's tab, and script-done comes after it.)
     */
    fun launched(model: AppModel) {
        if (!options.isEmpty) tabs(model, options)
        watch(model)
        if (!options.isEmpty) play(model, options)
    }

    /** A new intent for the activity already showing: its extras, but for the way in (a cold start's). */
    fun newIntent(model: AppModel, intent: Intent?) {
        val o = Options(intent?.extras)
        if (o.isEmpty) return
        Log.i(TAG, "new intent: ${o.names.joinToString(" ")}")
        options = o
        if (o.flag("EpicReset")) {
            model.saves.clearAll()
            model.home()
        }
        settings(model.settings, o)
        if (o.hearing != null) {
            Permissions.micAsked = true
            Permissions.notificationsAsked = true
        }
        tabs(model, o)
        watch(model)
        play(model, o)
    }

    /** EpicTheme, EpicTextSize and EpicSpeed, set as Settings sets them (and stored). */
    private fun settings(settings: AppSettings, o: Options) {
        o.text("EpicTheme")?.let { key -> ThemeChoice.entries.firstOrNull { it.key == key }?.let { settings.theme = it } }
        o.number("EpicTextSize")?.let { settings.textScale = it.toFloat() }
        o.number("EpicSpeed")?.let { settings.voiceSpeed = it.toFloat() }
    }

    /** EpicTab and EpicHelp: the tab the app shows, at once. */
    private fun tabs(model: AppModel, o: Options) {
        o.text("EpicTab")?.let { key -> Tab.entries.firstOrNull { it.key == key }?.let(model::select) }
        o.text("EpicHelp")?.let { topic ->
            model.select(Tab.HELP)
            if (model.helpPages.any { it.id == topic }) model.showTopic(topic)
        }
    }

    /** Once the way in is over, the store sheet and the game ([run]); then script-done, once that's on screen. */
    private fun play(model: AppModel, o: Options) {
        script?.cancel()
        script = model.viewModelScope.launch {
            run(model, o)
            shown("script-done")
        }
    }

    /**
     * The store sheet, and the game played as the extras say: its voice skipped, its questions answered, paused. Ten
     * minutes at the most (iOS: DebugLaunch.run).
     */
    private suspend fun run(model: AppModel, o: Options) {
        // A store sheet or a game waits for the intro and onboarding to be over, as a player's would.
        while (model.intro || model.onboarding) delay(POLL_MS)
        o.text("EpicStore")?.let { id -> model.games.firstOrNull { it.id == id }?.let { model.showStore(it) } }
        val info = o.text("EpicOpen")?.let { id -> model.games.firstOrNull { it.id == id } } ?: return
        if (o.flag("EpicFresh")) model.saves.clear(info.id)
        model.open(info)
        val answers = o.text("EpicSay")?.split('|')?.filter { it.isNotEmpty() }.orEmpty()
        val skip = o.flag("EpicSkip")
        val pauseAt = ((o.number("EpicPauseAt") ?: 0.0) * 1000).toLong()
        val sayDelay = ((o.number("EpicSayDelay") ?: 0.0) * 1000).toLong()
        val opened = SystemClock.elapsedRealtime()
        val since = { SystemClock.elapsedRealtime() - opened }
        var next = 0
        var paused = false
        // When the game began waiting for this answer (the question asked, its voice over).
        var waitingSince: Long? = null
        while (since() < MAX_MS) {
            delay(POLL_MS)
            // Played once its screen shows, as a player would: before that, the screen hasn't said yet that the mic is
            // allowed, and a voice skipped then would leave its question waiting, not listening.
            val game = model.game?.takeIf { it === gameShown.value } ?: continue
            if (pauseAt > 0 && !paused && since() >= pauseAt) {
                paused = true
                game.pause()
            }
            if (game.paused) continue
            if (skip && game.speaking) game.skip()
            val waiting = !game.speaking && game.ask != null
            waitingSince = if (waiting) waitingSince ?: SystemClock.elapsedRealtime() else null
            val waited = waitingSince?.let { SystemClock.elapsedRealtime() - it } ?: 0L
            if (waiting && next < answers.size && waited >= sayDelay) {
                val answer = answers[next]
                if (answer.endsWith("*") && next == answers.lastIndex) {
                    game.answer(answer.dropLast(1))
                } else {
                    game.answer(answer)
                    next++
                }
                waitingSince = null
            }
            if (game.end != null && answers.lastOrNull()?.endsWith("*") == true) next = answers.size
            if (next >= answers.size && !game.speaking && (pauseAt <= 0 || paused)) return
        }
    }

    /** The log lines (see above) for [model]'s screens and games, once for each model. */
    private fun watch(model: AppModel) {
        if (watched.get() === model) return
        watched = WeakReference(model)
        val scope = model.viewModelScope
        scope.launch { snapshotFlow { model.intro }.collect { if (it) shown("intro") } }
        scope.launch { snapshotFlow { model.onboarding }.collect { if (it) shown("onboarding") } }
        scope.launch {
            snapshotFlow {
                model.tab.takeIf { !model.intro && !model.onboarding && model.game == null && model.opening == null }
            }.collect { tab -> if (tab != null) shown("tab ${tab.key}") }
        }
        scope.launch { snapshotFlow { model.storeFor?.id }.collect { id -> if (id != null) shown("store-sheet $id") } }
        scope.launch { snapshotFlow { model.game }.collectLatest { game -> if (game != null) follow(game) } }
    }

    /** What a game is doing, as far as the log lines go. */
    private data class Moment(
        val speaking: Boolean,
        val listening: Boolean,
        val paused: Boolean,
        val asking: Boolean,
        val end: String?,
    )

    /**
     * A game's lines, from its state as it changes, until it closes. Its first turn's voice may be over before the
     * game shows (skipped at once, or a turn with no audio): that state, as the lines start, says so too.
     */
    private suspend fun follow(game: GameController) {
        shown("open ${game.info.id}")
        gameShown.value = game
        var was: Moment? = null
        snapshotFlow { Moment(game.speaking, game.listening, game.paused, game.ask != null, game.end?.kind) }
            .collect { now ->
                val before = was
                was = now
                if ((before == null || before.speaking) && !now.speaking) {
                    Log.i(TAG, if (now.asking && now.end == null) "asking" else "spoken")
                }
                if (now.listening && before?.listening != true) Log.i(TAG, "listening")
                if (now.paused && before?.paused != true) Log.i(TAG, "paused")
                if (now.end != null && before?.end == null) Log.i(TAG, "end ${now.end}")
            }
    }

    /**
     * The system's splash has gone (MainActivity, as it takes it away): until then, it covers whatever the app draws,
     * so a line saying something shows would come too soon (a slow start drew under it for seconds).
     */
    fun splashGone() {
        splash.value = true
    }

    private val splash = MutableStateFlow(false)

    /** The game whose screen has shown (its "open" line): the script plays it from then on ([run]). */
    private val gameShown = MutableStateFlow<GameController?>(null)

    /**
     * A line for something now on screen: once the system's splash has gone (a start with no splash never says so,
     * hence the time limit), after the frame that draws it (a launch's first one takes a moment).
     */
    private suspend fun shown(line: String) {
        withTimeoutOrNull(SPLASH_WAIT_MS) { splash.first { it } }
        repeat(2) { withTimeoutOrNull(FRAME_WAIT_MS) { awaitFrame() } }
        Log.i(TAG, line)
    }

    /** A launch's extras, read as flags, text or numbers whichever way am gave them. */
    private class Options(extras: Bundle?) {
        @Suppress("DEPRECATION")
        private val values: Map<String, Any?> =
            extras?.keySet()?.filter { it.startsWith("Epic") }?.associateWith { extras.get(it) }.orEmpty()

        val isEmpty get() = values.isEmpty()
        val names get() = values.keys.sorted()

        /** A flag: true for --ez true, or text YES, true, on or 1. */
        fun flag(name: String): Boolean = when (val v = values[name]) {
            is Boolean -> v
            is String -> v.trim().lowercase() in setOf("yes", "true", "on", "1")
            is Number -> v.toInt() != 0
            else -> false
        }

        fun text(name: String): String? = values[name]?.toString()?.takeIf { it.isNotBlank() }

        fun number(name: String): Double? = when (val v = values[name]) {
            is Number -> v.toDouble()
            is String -> v.trim().toDoubleOrNull()
            else -> null
        }

        /** EpicHear's script, or EpicMic off: none; null for the phone's recogniser. */
        val hearing: Hearing? = text("EpicHear")?.let { script ->
            val entries = script.split('|')
            Hearing { _, events -> ScriptedListener(entries, events) }
        } ?: if (text("EpicMic") == "off") Hearing.NONE else null
    }

    /** How often the script looks at the game (ms), and the longest it plays for. */
    private const val POLL_MS = 250L
    private const val MAX_MS = 600_000L
    /** The longest a log line waits for a frame (the screen off has none), and for the system's splash to go. */
    private const val FRAME_WAIT_MS = 500L
    private const val SPLASH_WAIT_MS = 10_000L
}
