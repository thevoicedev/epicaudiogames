package com.epicaudiogames.app

/**
 * How the microphone opens, a step at a time (docs/DESIGN.md › Sounds, haptics and the microphone): a Bluetooth
 * headset's call link first ([route]: its mic is the one listened to, and the sound then reaches the headset), then the
 * listening sound ([cue], over the call link when it's held), then the recogniser ([recognise]). The recogniser starts
 * only once the sound has been heard out, so it never hears it; Android's onReadyForSpeech would come too late to wait
 * for, as the recogniser is recording by then.
 *
 * Each listen is a session: a step that comes for a session that's over (a [stop], or another [start]) does nothing,
 * and a sound still playing is cut short. Plain Kotlin, tested on the JVM (ListenSequenceTest). iOS does it in
 * GameController.listen(): cues.play(.listenStart), then listener.start(hints:after:), with MicInput dropping what the
 * mic heard before the sound was over.
 */
class ListenSequence(
    /** Makes a Bluetooth headset's mic the one listened to, then runs its argument (at once without a headset). */
    private val route: (then: () -> Unit) -> Unit,
    /** Whether the headset's call link is held now. */
    private val callLink: () -> Boolean,
    /**
     * Plays the listening sound (over the call link if asked), then runs done once it has been heard out; done may
     * come at once (no sound wanted). Gives back a way to cut the sound short, after which done doesn't come.
     */
    private val cue: (callLink: Boolean, done: () -> Unit) -> () -> Unit,
    /** Starts the recogniser, for listen [session]. */
    private val recognise: (session: Int) -> Unit,
) {
    /** The listen going on now (or the last one); bumped by every [start] and [stop]. */
    var session = 0
        private set
    /** Cuts short the sound playing for this listen, if one is. */
    private var cutShort: (() -> Unit)? = null

    /**
     * A listen: the route, then the sound ([withCue]), then the recogniser. Without the sound, it's the same listen
     * going on (the recogniser started again: online after offline failed, or more time to answer); the route is
     * kept, if it's held. Returns the listen's session.
     */
    fun start(withCue: Boolean = true): Int {
        cutCue()
        val id = ++session
        route {
            if (id != session) return@route
            if (!withCue) {
                recognise(id)
                return@route
            }
            var heard = false
            val cut = cue(callLink()) {
                if (id == session && !heard) {
                    heard = true
                    cutShort = null
                    recognise(id)
                }
            }
            // A sound that was over at once (none wanted) has nothing left to cut.
            if (!heard && id == session) cutShort = cut
        }
        return id
    }

    /** Nothing more for the listen going on: a step still to come doesn't, and the sound stops. */
    fun stop() {
        session++
        cutCue()
    }

    /** Whether [id] is the listen going on now (the recogniser's calls for an older one are let go). */
    fun isCurrent(id: Int) = id == session

    private fun cutCue() {
        val cut = cutShort
        cutShort = null
        cut?.invoke()
    }
}

/**
 * Time to answer (Settings › Sound and voice: Normal, Longer, Longest). Android's recogniser ends a listen that
 * nobody speaks in by itself, after a few seconds of its own choosing (about five, on most phones). When that silence
 * comes [heardForMs] after the recogniser started, with [answerMs] chosen, the mic listens on (without the sound, as
 * the same listen) while at least [MIN_MORE_MS] of the time is left, rather than count a silence. [again]: how many
 * times it has already listened on this time, so a recogniser that gives up at once isn't started over and over.
 * iOS waits for the time itself (Endpointer's noSpeech).
 */
fun listensAgain(heardForMs: Long, answerMs: Long, again: Int): Boolean =
    again < MAX_LISTENS_AGAIN && answerMs - heardForMs >= MIN_MORE_MS

/** The least time left for which the mic listens on: less, and the silence counts (a recogniser's own wait is longer). */
const val MIN_MORE_MS = 2_000L

/** The most times a listen goes on after the recogniser gave up (15 seconds is three or four of its usual waits). */
const val MAX_LISTENS_AGAIN = 8
