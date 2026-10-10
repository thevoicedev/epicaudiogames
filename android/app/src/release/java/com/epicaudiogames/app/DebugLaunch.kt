package com.epicaudiogames.app

import android.content.Context
import android.content.Intent
import com.epicaudiogames.app.ui.AppStart

/**
 * A release build's launch: its intent extras do nothing here, as any app on the phone can start this one with
 * extras. The debug build's DebugLaunch (src/debug/, the same functions) plays the app from them, for screenshots, the
 * preview video and checks; MainActivity and AppModel call it the same way in both builds.
 */
object DebugLaunch {
    fun launching(context: Context, intent: Intent?) = Unit

    val hearing: Hearing? get() = null

    val packsUrl: String? get() = null

    fun start(start: AppStart): AppStart = start

    fun launched(model: AppModel) = Unit

    fun newIntent(model: AppModel, intent: Intent?) = Unit

    fun splashGone() = Unit
}
