package com.epicaudiogames.wear

import android.content.Intent
import com.epicaudiogames.wearlink.WearState

/**
 * A release build's launch: its extras show nothing here, as any app on the watch can start this one with extras. The
 * debug build's WatchDemo (src/debug/, the same function) shows a game's state without a phone, for screenshots.
 */
object WatchDemo {
    fun state(intent: Intent?): WearState? = null
}
