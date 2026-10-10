package com.epicaudiogames.app

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Hears a script instead of the mic (debug builds, DebugLaunch's EpicHear), one entry each time the game listens: a
 * word or words are heard (after a moment showing as the partial result, with the level up); "~" is a silence; "?" is
 * speech it couldn't make out. Once the script runs out, it listens and hears nothing. The mic counts as allowed, with
 * no permission asked. Each listen opens with the listening sound and its tick, as the recogniser's do (the events'
 * cue), and the script's moment counts from the sound's end. What it hears goes to the log (EpicShots), for the tools:
 * it's the script's words, never the player's. iOS: Debug/ScriptedListener.swift.
 */
class ScriptedListener(script: List<String>, private val events: ListenerEvents) : Listening {
    private val script = ArrayDeque(script)
    private val main = Handler(Looper.getMainLooper())
    /** Bumped by each start and stop: a listen that's over reports nothing more. */
    private var session = 0
    private var cut: () -> Unit = {}

    override val available get() = true
    override val needsPermission get() = false
    override var settleMs: Long? = null

    override fun start(withCue: Boolean) {
        val id = ++session
        cut()
        cut = {}
        val next = script.removeFirstOrNull()
        val listen = { if (next != null) hearLater(id, next) }
        if (withCue) cut = events.cue(false) { listen() } else listen()
    }

    /** The script's [next] entry for listen [id], a moment from now (unless that listen is over by then). */
    private fun hearLater(id: Int, next: String) {
        main.postDelayed({
            if (session != id) return@postDelayed
            when (next) {
                "~" -> {
                    Log.i(TAG, "silence")
                    events.onSilence()
                }
                "?" -> {
                    Log.i(TAG, "heard ?")
                    events.onHeard(emptyList())
                }
                else -> {
                    events.onLevel(0.6f)
                    events.onPartial(next)
                    main.postDelayed({
                        if (session != id) return@postDelayed
                        Log.i(TAG, "heard \"$next\"")
                        events.onHeard(listOf(next))
                    }, WORDS_MS)
                }
            }
        }, LISTEN_MS)
    }

    /**
     * A scripted silence is a whole one: the time to answer is up, so the game counts it rather than listening on
     * (GameController's silence, listensAgain).
     */
    override fun heardFor() = Long.MAX_VALUE

    override fun stop() {
        session++
        cut()
        cut = {}
    }

    override fun release() = stop()

    private companion object {
        const val TAG = "EpicShots"
        /** How long it listens before the entry comes (ms), and how long the words show as partial before they count. */
        const val LISTEN_MS = 1_500L
        const val WORDS_MS = 2_000L
    }
}
