package com.epicaudiogames.wear

import android.content.Intent
import com.epicaudiogames.wearlink.WearAction
import com.epicaudiogames.wearlink.WearState

/**
 * `EpicWatchDemo <speaking|turn|listening|paused|wait|refused|end|none>` (debug builds only; a release build's
 * WatchDemo, src/release/, shows nothing): the watch app shows Noodle Rush in that state, worded as the phone sends it
 * (the app's WearBridge.kt, wearState), and hears nothing from a phone, so no phone changes it. For screenshots (Play's
 * Wear OS screenshots, docs/WEAR_OS.md) and checks:
 * `adb shell am start -S -n com.epicaudiogames.app/com.epicaudiogames.wear.WatchActivity --es EpicWatchDemo listening`.
 * The same states as iOS's watch's -EpicWatchDemo (ios/EpicWatch/WatchDemo.swift).
 */
object WatchDemo {
    const val EXTRA = "EpicWatchDemo"

    /** The state the launch asks for, if any. */
    fun state(intent: Intent?): WearState? = intent?.getStringExtra(EXTRA)?.let(::state)

    fun state(name: String): WearState? {
        val game = WearState(
            title = "Noodle Rush", state = "", action = null, label = "", enabled = true, listening = false,
            canPause = true,
        )
        return when (name) {
            "speaking" -> game.copy(state = "Speaking", action = WearAction.SKIP, label = "Skip")
            "turn" -> game.copy(state = "Your turn", action = WearAction.TALK, label = "Talk")
            "listening" -> game.copy(
                state = "Listening…", action = WearAction.STOP_LISTENING, label = "Stop listening", listening = true,
            )
            "paused" -> game.copy(state = "Paused", action = WearAction.CARRY_ON, label = "Carry on", canPause = false)
            "wait" -> game.copy(
                state = "Wait for the question", action = WearAction.WAIT, label = "Talk", enabled = false,
            )
            "refused" -> game.copy(
                state = "Your turn", action = WearAction.MIC_REFUSED, label = "Talk (the microphone is off)",
                enabled = false,
            )
            "end" -> game.copy(state = "Chapter complete", enabled = false, canPause = false)
            "none" -> WearState.NONE
            else -> null
        }
    }
}
