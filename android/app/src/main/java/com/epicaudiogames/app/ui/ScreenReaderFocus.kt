package com.epicaudiogames.app.ui

import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.epicaudiogames.app.ui.theme.LocalScreenReader

/**
 * Where the screen reader's focus is (TalkBack's: what it reads, and what a double tap presses): the test tag of the
 * element it's on, as Compose state; null when it's on none of the app's tagged elements, or on nothing.
 *
 * TalkBack says it again whenever the name or state of what its focus is on changes. On the game's one button that
 * would be all the time, as the button's name and state follow the game: "Speaking, Skip" over the voice as each turn
 * starts, and "Listening, Stop listening" as the mic opens, which the recogniser would hear (docs/DESIGN.md › Sounds:
 * never a spoken "Listening"; the sound is the cue). So those elements keep the words TalkBack last read while its
 * focus stays on them ([heldWhileRead]), and take the game's as it moves away: coming back to them, TalkBack reads
 * what they do now. VoiceOver doesn't say a button's new name or value by itself, and the iPhone's circle starts a
 * media session, so VoiceOver stays quiet after a tap: the iPhone needs nothing like this (GameView.swift).
 *
 * MainActivity's root view ([FirstKeys]) hears TalkBack's focus coming and going ([follow]); a test sets [tag] itself.
 */
class ScreenReaderFocus {
    /** The tag of the element the screen reader's focus is on, if it's one of the app's. */
    var tag by mutableStateOf<String?>(null)
        internal set

    /**
     * The screen reader's focus has moved (an accessibility focus event from [view], the app's Compose view or a
     * view holding it): where it is now, from the view's node provider (Compose's, which knows which element has it).
     */
    fun follow(view: View) {
        tag = view.nodeProvider()?.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)?.viewIdResourceName
    }

    companion object {
        /** Whether [event] is the screen reader's focus arriving on an element, or leaving it. */
        fun moves(event: AccessibilityEvent): Boolean =
            event.eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED ||
                event.eventType == AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUS_CLEARED
    }
}

/** The node provider of [this] view, or of the first view in it that has one (a ComposeView holds Compose's). */
private fun View.nodeProvider(): AccessibilityNodeProvider? {
    accessibilityNodeProvider?.let { return it }
    if (this is ViewGroup) for (i in 0 until childCount) getChildAt(i).nodeProvider()?.let { return it }
    return null
}

/** The app's [ScreenReaderFocus] (MainActivity's); one that's never told anything in a test that doesn't set it. */
val LocalScreenReaderFocus = staticCompositionLocalOf { ScreenReaderFocus() }

/**
 * [value] as the screen reader last had it, while its focus stays on the element tagged [tag] (a screen reader on);
 * [value] itself otherwise. For an element's name and state ([ScreenReaderFocus] says why): with the focus on it they
 * don't change, so TalkBack doesn't say them again as the game moves on, and once it moves away they're the game's
 * again, for when it comes back.
 */
@Composable
internal fun <T> heldWhileRead(tag: String, value: T): T {
    val reading = LocalScreenReader.current && LocalScreenReaderFocus.current.tag == tag
    val held = remember { Held(value) }
    if (!reading) held.value = value
    return held.value
}

/** What [heldWhileRead] keeps: set as the screen draws, never read by anything else. */
private class Held<T>(var value: T)
