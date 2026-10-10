package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The notification's button (BackgroundPlay.kt): named by CircleAction now, it shows in the same states as before, over
 * every combination of the game's state. A tap on it is still a tap on the talking circle.
 */
class NotificationButtonTest {
    private data class State(
        val paused: Boolean,
        val speaking: Boolean,
        val listening: Boolean,
        val end: Boolean,
        val ask: Boolean,
        val micAllowed: Boolean,
        val micWorks: Boolean,
    ) {
        val button
            get() = notificationButton(CircleAction.of(paused, speaking, listening, end, ask, micAllowed, micWorks), end)
    }

    /** All 128 states. */
    private val states = (0 until 128).map { bits ->
        fun bit(i: Int) = (bits and (1 shl i)) != 0
        State(bit(0), bit(1), bit(2), bit(3), bit(4), bit(5), bit(6))
    }

    /** The button's name before CircleAction (BackgroundPlay's own Circle), or null where it had none. */
    private fun before(s: State): String? = when {
        s.end -> null
        s.paused -> "Carry on"
        s.speaking -> "Skip"
        s.listening -> "Stop listening"
        s.ask && s.micAllowed -> "Talk"
        else -> null
    }

    @Test
    fun itShowsWhereItDidBefore() {
        for (s in states) assertEquals("$s", before(s) != null, s.button != null)
    }

    @Test
    fun itHasItsOldNameExceptWithNoRecogniser() {
        for (s in states) {
            val button = s.button ?: continue
            // The recogniser not available was a plain "Talk"; now the circle's name says why (a tap still tries).
            val expected = if (button == CircleAction.NO_RECOGNITION) {
                "Talk (speech recognition isn't available)"
            } else {
                before(s)
            }
            assertEquals("$s", expected, TestWords.text(button.label))
        }
    }

    @Test
    fun noneAtAnEndEvenWhenPaused() {
        for (s in states.filter { it.end }) assertNull("$s", s.button)
    }

    @Test
    fun noneForARefusedMicOrBeforeTheQuestion() {
        // Asking for the mic needs the screen; with no question yet, there's nothing to do.
        assertNull(notificationButton(CircleAction.MIC_REFUSED, end = false))
        assertNull(notificationButton(CircleAction.WAIT, end = false))
        assertNull(notificationButton(null, end = false))
    }
}
