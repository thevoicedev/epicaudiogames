package com.epicaudiogames.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.StringRes
import androidx.compose.runtime.snapshotFlow
import com.epicaudiogames.wearlink.WearAction
import com.epicaudiogames.wearlink.WearCommand
import com.epicaudiogames.wearlink.WearLink
import com.epicaudiogames.wearlink.WearState
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

// The phone's side of the Wear OS app (android/wear; docs/WEAR_OS.md): the game's state goes to the watch through Wear
// OS's Data Layer, and the watch's two buttons come back. What they say to each other is android/wear/link's
// WearLink.kt. iOS's Apple Watch app has the same: ios/EpicAudioGames/Watch/WatchBridge.swift.

/**
 * The Wear OS app's view of the game (docs/DESIGN.md › Watches): the open game's title, what it's doing in words, its
 * one button named as on the phone (the talking circle's CircleAction), whether the microphone is open, and whether
 * Pause can do anything ([wearState]). The watch is told whenever that changes (followed with snapshotFlow, as the
 * screen may not be drawn while the phone is locked) and again whenever its link can hear it ([link]'s onReady); its
 * two buttons come back as the headphones' button and the pause ([perform]). The game is read afresh each time
 * ([game]). The app's model starts it (AppModel.wear). iOS: WatchBridge.swift.
 */
class WearBridge(
    private val link: WearLinking,
    private val words: Words,
    /** Where what the watch's buttons did is logged (logcat's WearBridge; the JVM tests have no Android log). */
    private val log: (String) -> Unit = { Log.i(TAG, it) },
    private val game: () -> WearGame?,
) {
    /** What the watch was last told: a change that leaves it as it is isn't told again. */
    private var told: WearState? = null
    private var following: Job? = null

    /** Starts the link, tells the watch what's open now, and follows the game from here, in [scope]. */
    fun start(scope: CoroutineScope) {
        current = this
        link.onReady = { tell(again = true) }
        link.start()
        tell(again = true)
        following = scope.launch { snapshotFlow { state() }.collect { tell() } }
    }

    /** The app's model has gone, and its game with it: the watch is told no game is open. */
    fun stop() {
        following?.cancel()
        following = null
        if (current === this) current = null
        told = WearState.NONE
        link.tell(WearState.NONE)
    }

    /** The watch is told the game's state if it changed since it was last told, or [again] whatever it is. */
    fun tell(again: Boolean = false) {
        val now = state()
        if (!again && now == told) return
        told = now
        link.tell(now)
    }

    /** What the watch shows now. */
    fun state(): WearState = wearState(words, game())

    /**
     * A button on the watch. The big one does what the headphones' button does (BackgroundPlay's tap): carries on
     * after a pause, skips the voice, starts or stops listening ([GameController.circle]); the microphone's question
     * can't be asked from the wrist, so with the mic not allowed it does nothing (the watch shows it dimmed,
     * [wearState]). Pause pauses, as the lock screen's pause does: not over a pause, nor at an end. Nothing without a
     * game, and the big button nothing at an end (the watch has none then: a press sent just before it heard).
     */
    fun perform(command: WearCommand) {
        val g = game() ?: return
        when (command) {
            WearCommand.PRIMARY -> {
                val action = g.action?.name?.takeIf { g.endKind == null }
                log("${g.id}: watch -> ${action ?: "nothing"}")
                if (g.endKind == null) g.circle()
            }
            WearCommand.PAUSE -> {
                val pauses = !g.paused && g.endKind == null
                log("${g.id}: watch -> ${if (pauses) "pause" else "nothing"}")
                if (pauses) g.pause()
            }
        }
    }

    companion object {
        private const val TAG = "WearBridge"

        /** The app's model's bridge, while it has one: where the watch's buttons go ([WearCommands]). */
        @Volatile
        var current: WearBridge? = null
            private set
    }
}

/**
 * What the watch needs of the open game: what it shows, and its two buttons. The app's is a GameController
 * ([GameOnWatch]); the tests have their own.
 */
interface WearGame {
    /** The game's id, for the log. */
    val id: String
    val title: String
    /** What the talking circle does now ([GameController.circleAction]): null at an end. */
    val action: CircleAction?
    val listening: Boolean
    val paused: Boolean
    /** The end reached, by its kind ("chapter", "gameover"…); null while the game goes on. */
    val endKind: String?

    /** The talking circle, tapped: what the headphones' button does. */
    fun circle()

    fun pause()
}

/** A [GameController] as the watch sees it: its state read through, so snapshotFlow follows it. */
class GameOnWatch(private val game: GameController) : WearGame {
    override val id: String get() = game.info.id
    override val title: String get() = game.info.title
    override val action: CircleAction? get() = game.circleAction
    override val listening: Boolean get() = game.listening
    override val paused: Boolean get() = game.paused
    override val endKind: String? get() = game.end?.kind

    override fun circle() = game.circle()

    override fun pause() = game.pause()
}

/**
 * What the watch shows for [game] (null: none open), in the phone's [words]: the circle's name for the big button and
 * its state in words (listening as the status line has it, "Listening…"); at an end, no button and the end panel's
 * heading, whatever the circle says, as the end panel's choices are on the phone (the notification has no button then
 * either). With the mic not allowed the button can't do anything from the watch (only the phone can ask for the mic):
 * it's dimmed, still named "Talk (the microphone is off)", which says why. Before the question it's dimmed too, as the
 * circle is. iOS: WatchBridge.state(of:).
 */
fun wearState(words: Words, game: WearGame?): WearState {
    if (game == null) return WearState.NONE
    val end = game.endKind
    val action = game.action.takeIf { end == null }
    return WearState(
        title = game.title,
        state = when {
            action == CircleAction.STOP_LISTENING -> words.text(R.string.status_listening)
            action != null -> words.text(action.state)
            end != null -> words.text(endHeading(end))
            else -> ""
        },
        action = action?.let(::wearAction),
        label = action?.let { words.text(it.label) }.orEmpty(),
        enabled = action != null && action.enabled && action != CircleAction.MIC_REFUSED,
        listening = game.listening,
        canPause = !game.paused && end == null,
    )
}

/** The circle's action as the watch knows it: the same names. */
fun wearAction(action: CircleAction): WearAction = when (action) {
    CircleAction.CARRY_ON -> WearAction.CARRY_ON
    CircleAction.SKIP -> WearAction.SKIP
    CircleAction.STOP_LISTENING -> WearAction.STOP_LISTENING
    CircleAction.TALK -> WearAction.TALK
    CircleAction.MIC_REFUSED -> WearAction.MIC_REFUSED
    CircleAction.NO_RECOGNITION -> WearAction.NO_RECOGNITION
    CircleAction.WAIT -> WearAction.WAIT
}

/** The end panel's heading for an end of [kind] (ui/GameScreen.kt's EndPanel says the same). */
@StringRes
fun endHeading(kind: String): Int = when (kind) {
    "chapter" -> R.string.end_chapter
    "gameover" -> R.string.end_game_over
    else -> R.string.end_the_end
}

/** Where the watch's state goes: Wear OS's Data Layer ([DataLayerLink]), or a test's. */
interface WearLinking {
    /** The watch can be told again (the link has found Wear OS on the phone): the state goes again, changed or not. */
    var onReady: () -> Unit

    fun start()

    /** What the game is doing now, for the watch. */
    fun tell(state: WearState)
}

/**
 * Wear OS's Data Layer on the phone. [tell] keeps the state as a data item (WearLink.STATE_PATH), which Google Play
 * services copies to the phone's watches, urgently: a watch app reads it as it opens and hears each change while it's
 * on screen. Nothing goes until Play services says the phone has the Data Layer, and nothing at all on a phone without
 * it (no Google Play services, or too old): the app just has no watch. Phone to watch only: over Bluetooth, or through
 * Google's servers end-to-end encrypted when the watch is away from the phone; never to our server.
 */
class DataLayerLink(context: Context) : WearLinking {
    override var onReady: () -> Unit = {}
    private val data = Wearable.getDataClient(context.applicationContext)

    /** Whether the phone has the Data Layer: null until Play services has said. */
    private var available: Boolean? = null
    private var started = false

    override fun start() {
        if (started) return
        started = true
        GoogleApiAvailability.getInstance().checkApiAvailability(data)
            .addOnSuccessListener {
                available = true
                onReady()
            }
            .addOnFailureListener {
                available = false
                Log.i(TAG, "no Wear OS link on this phone: ${it.message}")
            }
    }

    override fun tell(state: WearState) {
        if (available == true) put(state)
    }

    /** Keeps [state] for the watches, stamped now. */
    fun put(state: WearState): Task<DataItem> {
        val request = PutDataMapRequest.create(WearLink.STATE_PATH)
        for ((key, value) in state.toMap(at = System.currentTimeMillis())) {
            when (value) {
                is String -> request.dataMap.putString(key, value)
                is Boolean -> request.dataMap.putBoolean(key, value)
                is Long -> request.dataMap.putLong(key, value)
            }
        }
        return data.putDataItem(request.asPutDataRequest().setUrgent())
            .addOnFailureListener { Log.w(TAG, "the watch's state wasn't kept", it) }
    }

    private companion object {
        const val TAG = "WearBridge"
    }
}

/**
 * The watch's buttons, as messages Google Play services hands over (WearLink.COMMAND_PATH; the manifest's intent
 * filter), starting the app if it isn't running. They go to the app's model's [WearBridge], on the main thread. With
 * no model (the app wasn't open, or its screen has gone) no game is open, so the watch is told so: its state may be
 * one left from before the app was stopped. iOS: WatchSession's didReceiveMessage.
 */
class WearCommands : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        val command = WearCommand.from(event.path, event.data) ?: return
        if (WearBridge.current == null) {
            // On Play services' thread: kept before this service may go, with the process it started.
            runCatching { Tasks.await(DataLayerLink(this).put(WearState.NONE), PUT_WAIT_S, TimeUnit.SECONDS) }
                .onFailure { Log.w(TAG, "couldn't tell the watch no game is open", it) }
            return
        }
        Handler(Looper.getMainLooper()).post { WearBridge.current?.perform(command) }
    }

    private companion object {
        const val TAG = "WearBridge"
        /** How long a state may take to be kept, at most (seconds). */
        const val PUT_WAIT_S = 5L
    }
}
