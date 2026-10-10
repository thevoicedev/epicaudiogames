package com.epicaudiogames.app

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Whether a screen reader is on (TalkBack, or another that explores the screen by touch), as Compose state that
 * follows the phone's switch while the app runs. With one on, the game doesn't open the mic by itself (MicPolicy.kt):
 * the recogniser would hear it reading the screen. iOS asks UIAccessibility.isVoiceOverRunning (A11y.swift).
 *
 * Switch Access and Voice Access don't explore by touch or read the screen aloud: they don't count.
 *
 * The screens read it as a plain Boolean, LocalScreenReader (EpicTheme), which a UI test of one screen can provide
 * itself; a test of the whole app sets [simulated].
 */
class ScreenReader(context: Context) {
    private val manager = context.getSystemService(AccessibilityManager::class.java)
    private var following by mutableStateOf(manager?.isTouchExplorationEnabled == true)

    /** For UI tests: a screen reader taken as on (true) or off (false) whatever the phone says; null follows it. */
    var simulated by mutableStateOf<Boolean?>(null)

    /** A screen reader is on (or [simulated]). */
    val on: Boolean get() = simulated ?: following

    // Called on the main thread as the switch changes.
    private val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled -> following = enabled }

    init {
        manager?.addTouchExplorationStateChangeListener(listener)
    }

    /** Stops following the switch (the app's model going away). */
    fun close() {
        manager?.removeTouchExplorationStateChangeListener(listener)
    }
}
