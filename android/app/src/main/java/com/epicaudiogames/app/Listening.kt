package com.epicaudiogames.app

import android.content.Context
import android.os.Handler
import android.os.Looper

/**
 * What a game listens for its answers with (GameController's listener): the phone's speech recogniser ([Listener]),
 * none at all ([UnavailableListener]), or, in a debug build launched to play by itself, a script (DebugLaunch's
 * ScriptedListener, in src/debug). It reports through the [ListenerEvents] it was made with. iOS: EpicAppCore's
 * Listening.swift.
 */
interface Listening {
    /** Whether it can listen at all (the phone has a speech recogniser): if not, answers are typed or tapped. */
    val available: Boolean

    /**
     * Whether it hears through the microphone, which Android asks the player for: the recogniser does; a script
     * doesn't, so for it the microphone counts as allowed and nothing is asked.
     */
    val needsPermission: Boolean get() = true

    /**
     * How long the recogniser should wait once the player stops talking before it takes the answer as complete (Time
     * to answer's Longer and Longest); null for its own. Only a hint, which some recognisers don't take.
     */
    var settleMs: Long?

    /**
     * Listens for one answer: the listening sound first ([ListenerEvents.cue]), then what hears. [withCue] false is the
     * same listen going on (more time to answer), without the sound.
     */
    fun start(withCue: Boolean = true)

    /** How long it has been listening, since it first started for this listen (0 before it has). */
    fun heardFor(): Long

    /** Stops listening, reporting nothing more. */
    fun stop()

    /** Lets go of the recogniser for good (the game closing). */
    fun release()
}

/**
 * What a listener reports, on the main thread (iOS: ListenerEvents): the words as they come ([onPartial]); the
 * recogniser's guesses, best first ([onHeard]; an empty list for speech it couldn't make out); nobody speaking
 * ([onSilence]); the sound level, 0 to 1 ([onLevel]); listening not working here at all ([onUnavailable]: answers are
 * typed or tapped instead, and the mic button tries again); passing trouble that says nothing about the player
 * ([onTrouble]: the listen just ends). [cue] plays the listening sound (and its tick), over a headset's call link when
 * that's held, then calls done once it's heard out; it gives back a way to cut the sound short.
 */
class ListenerEvents(
    val onPartial: (String) -> Unit,
    val onHeard: (List<String>) -> Unit,
    val onSilence: () -> Unit,
    val onLevel: (Float) -> Unit,
    val onUnavailable: () -> Unit,
    val onTrouble: () -> Unit,
    val cue: (callLink: Boolean, done: () -> Unit) -> () -> Unit = { _, done -> done(); {} },
)

/**
 * How the games hear their answers (iOS: AppModel.Hearing): what makes each game's listener. The phone's speech
 * recogniser, once the player allows the microphone ([SPEECH], the app's); none ([NONE]: answers typed or tapped, as on
 * a phone with no recogniser); or, in a debug build, what its launch says (DebugLaunch: a script it hears instead).
 */
fun interface Hearing {
    fun listener(context: Context, events: ListenerEvents): Listening

    companion object {
        val SPEECH = Hearing { context, events -> Listener(context, events) }
        val NONE = Hearing { _, events -> UnavailableListener(events) }
    }
}

/**
 * A listener with no speech recogniser behind it (iOS: UnavailableListener.swift): it says so whenever it's asked to
 * listen, as [Listener] does when there's no recogniser for the language, after the listening sound and a moment
 * later (as the recogniser's errors come), and not once listening has been stopped. The mic shows as off; typing and
 * the answer chips work as ever. The microphone is still the phone's own, so it counts as allowed only once Android
 * says so (and isn't asked for while there's nothing to listen with).
 */
class UnavailableListener(private val events: ListenerEvents) : Listening {
    private val main = Handler(Looper.getMainLooper())
    /** Bumped by each start and stop: a report for a listen that's over is dropped. */
    private var session = 0
    private var cut: () -> Unit = {}

    override val available get() = false
    override var settleMs: Long? = null

    override fun start(withCue: Boolean) {
        val id = ++session
        val report = { main.post { if (session == id) events.onUnavailable() } }
        if (withCue) cut = events.cue(false) { report() } else report()
    }

    override fun heardFor() = 0L

    override fun stop() {
        session++
        cut()
        cut = {}
    }

    override fun release() = stop()
}
