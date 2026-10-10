package com.epicaudiogames.app.ui

import android.content.Context
import android.view.KeyEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * A keyboard's shortcut (docs/DESIGN.md › Tablets… › Keyboard), as the app uses it: Space is the game's one button,
 * Escape pauses the game (or closes what's open), and Ctrl with 1 to 4 picks a tab. iOS: .keyboardShortcut on each.
 */
sealed interface Shortcut {
    /** Space: what tapping the talking circle does (skip, talk, stop listening, carry on). */
    data object OneButton : Shortcut

    /** Escape: pause the game or carry on from the pause, leave it at its end, close a page (Settings › Licences). */
    data object Escape : Shortcut

    /** Ctrl with a tab's number, in the bar's order: Ctrl+2 is the Shop. */
    data class ToTab(val tab: Tab) : Shortcut

    companion object {
        /** The shortcut a key event is, if it's one. */
        fun of(event: KeyEvent): Shortcut? =
            of(event.keyCode, event.isCtrlPressed, event.isAltPressed, event.isShiftPressed, event.isMetaPressed)

        /**
         * The shortcut a key is, with the modifier keys held: Space and Escape on their own, a number (the top row's
         * or the keypad's) with Ctrl alone. Anything else isn't one.
         */
        fun of(keyCode: Int, ctrl: Boolean, alt: Boolean, shift: Boolean, meta: Boolean): Shortcut? {
            val plain = !ctrl && !alt && !shift && !meta
            return when {
                keyCode == KeyEvent.KEYCODE_SPACE && plain -> OneButton
                keyCode == KeyEvent.KEYCODE_ESCAPE && plain -> Escape
                ctrl && !alt && !shift && !meta -> tabNumber(keyCode)?.let { ToTab(Tab.entries[it - 1]) }
                else -> null
            }
        }

        /** 1 to 4, from the number row or the keypad; null for any other key. */
        private fun tabNumber(keyCode: Int): Int? = when (keyCode) {
            in KeyEvent.KEYCODE_1..KeyEvent.KEYCODE_4 -> keyCode - KeyEvent.KEYCODE_0
            in KeyEvent.KEYCODE_NUMPAD_1..KeyEvent.KEYCODE_NUMPAD_4 -> keyCode - KeyEvent.KEYCODE_NUMPAD_0
            else -> null
        }?.takeIf { it <= Tab.entries.size }
    }
}

/**
 * Where the keyboard's shortcuts go: the screens showing say what they do with each ([KeyShortcuts]), the newest
 * first (the game's, while it's over the tabs), and track a key a shortcut used, so its repeats and its release go
 * with it. MainActivity hands it Space before anything else sees it ([FirstKeys]): in a game it's the one button
 * wherever the focus is, but in the answer box, where it types (Enter still presses a focused button). Escape and
 * Ctrl with a number come once nothing on screen has used them. A sheet or a dialog is a window of its own and keeps
 * its keys, Escape included.
 */
class Shortcuts {
    private val handlers = mutableListOf<(Shortcut) -> Boolean>()
    /** The key whose press a shortcut used: its repeats and its release are used up too. */
    private var used: Int? = null

    /** A shortcut pressed: true if a screen did something with it. */
    fun handle(shortcut: Shortcut): Boolean = handlers.asReversed().any { it(shortcut) }

    /**
     * A [shortcut]'s key going down or up: down, a screen does what it's for (true if one did); held down or let go,
     * it's used up if its press was.
     */
    fun key(event: KeyEvent, shortcut: Shortcut): Boolean = key(event.action, event.keyCode, event.repeatCount, shortcut)

    /** [key], from the event's action (KeyEvent.ACTION_DOWN or ACTION_UP), key code and repeat count. */
    internal fun key(action: Int, keyCode: Int, repeatCount: Int, shortcut: Shortcut): Boolean = when (action) {
        KeyEvent.ACTION_DOWN -> when {
            repeatCount > 0 -> used == keyCode
            handle(shortcut) -> true.also { used = keyCode }
            else -> false
        }
        KeyEvent.ACTION_UP -> released(keyCode)
        else -> false
    }

    /** A key let go: true if its press was a shortcut's (the release is used up with it). */
    fun released(keyCode: Int): Boolean = (used == keyCode).also { if (it) used = null }

    internal fun add(handler: (Shortcut) -> Boolean) {
        handlers += handler
    }

    internal fun remove(handler: (Shortcut) -> Boolean) {
        handlers -= handler
    }
}

/**
 * The activity's content, which is offered each key ([onKey], true if it used it) before the screen, the soft
 * keyboard or Android's own handling of it. Space has to come here first to be the game's one button: a focused button
 * takes it as a press of its own, and Android takes a first Space or Enter pressed in touch mode to put the keyboard's
 * focus on the first thing on screen. Android offers a key this early only along the focus, so with none (cleared in
 * touch mode) that first key still goes its way; the game then puts the focus on its talking circle (GameScreen). It
 * also hears where the screen reader's focus goes ([onScreenReaderFocus]).
 */
class FirstKeys(context: Context, private val onKey: (KeyEvent) -> Boolean) : FrameLayout(context) {
    /**
     * The screen reader's focus moved to or from one of the screen's elements ([ScreenReaderFocus]): told with the
     * view it moved in. Every accessibility event of the screen's comes up through here on its way to TalkBack.
     */
    var onScreenReaderFocus: ((View) -> Unit)? = null

    override fun dispatchKeyEventPreIme(event: KeyEvent): Boolean = onKey(event) || super.dispatchKeyEventPreIme(event)

    override fun onRequestSendAccessibilityEvent(child: View, event: AccessibilityEvent): Boolean {
        if (ScreenReaderFocus.moves(event)) onScreenReaderFocus?.invoke(child)
        return super.onRequestSendAccessibilityEvent(child, event)
    }
}

/** The app's [Shortcuts] (MainActivity's); none in a test that shows a screen on its own. */
val LocalShortcuts = staticCompositionLocalOf<Shortcuts?> { null }

/**
 * What this screen does with the keyboard's shortcuts, for as long as it shows: [onKey] is true for one it used.
 * One it doesn't use goes on to the screens under it, then to Android.
 */
@Composable
fun KeyShortcuts(onKey: (Shortcut) -> Boolean) {
    val shortcuts = LocalShortcuts.current ?: return
    val current by rememberUpdatedState(onKey)
    DisposableEffect(shortcuts) {
        val handler: (Shortcut) -> Boolean = { current(it) }
        shortcuts.add(handler)
        onDispose { shortcuts.remove(handler) }
    }
}
