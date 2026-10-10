package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The game's one button (the talking circle, the notification's button): docs/DESIGN.md's table of names and states
 * (the words res/values/strings.xml has for them), and which action wins, over every combination of the game's
 * state; and the mic button's name, from the same table.
 */
class CircleActionTest {
    private data class Row(val action: CircleAction, val label: String, val state: String, val enabled: Boolean = true)

    private data class State(
        val paused: Boolean,
        val speaking: Boolean,
        val listening: Boolean,
        val end: Boolean,
        val ask: Boolean,
        val micAllowed: Boolean,
        val micWorks: Boolean,
    ) {
        val action get() = CircleAction.of(paused, speaking, listening, end, ask, micAllowed, micWorks)
    }

    /** All 128 states. */
    private val states = (0 until 128).map { bits ->
        fun bit(i: Int) = (bits and (1 shl i)) != 0
        State(bit(0), bit(1), bit(2), bit(3), bit(4), bit(5), bit(6))
    }

    @Test
    fun namesAndStatesAreTheDesignTables() {
        val table = listOf(
            Row(CircleAction.CARRY_ON, "Carry on", "Paused"),
            Row(CircleAction.SKIP, "Skip", "Speaking"),
            Row(CircleAction.STOP_LISTENING, "Stop listening", "Listening"),
            Row(CircleAction.TALK, "Talk", "Your turn"),
            Row(CircleAction.MIC_REFUSED, "Talk (the microphone is off)", "Your turn"),
            Row(CircleAction.NO_RECOGNITION, "Talk (speech recognition isn't available)", "Your turn"),
            Row(CircleAction.WAIT, "Talk", "Wait for the question", enabled = false),
        )
        assertEquals(CircleAction.entries.toSet(), table.map { it.action }.toSet())
        for (row in table) {
            val action = row.action
            assertEquals(row, Row(action, TestWords.text(action.label), TestWords.text(action.state), action.enabled))
        }
    }

    @Test
    fun pausedItCarriesOnWhateverElse() {
        for (s in states.filter { it.paused }) assertEquals("$s", CircleAction.CARRY_ON, s.action)
    }

    @Test
    fun speakingItSkips() {
        for (s in states.filter { !it.paused && it.speaking }) assertEquals("$s", CircleAction.SKIP, s.action)
    }

    @Test
    fun listeningItStopsListening() {
        for (s in states.filter { !it.paused && !it.speaking && it.listening }) {
            assertEquals("$s", CircleAction.STOP_LISTENING, s.action)
        }
    }

    @Test
    fun atAnEndItDoesNothing() {
        for (s in states.filter { !it.paused && !it.speaking && !it.listening && it.end }) assertNull("$s", s.action)
    }

    @Test
    fun withNoQuestionYetItWaitsDisabled() {
        for (s in waiting().filter { !it.ask }) {
            assertEquals("$s", CircleAction.WAIT, s.action)
            assertFalse("$s", s.action!!.enabled)
        }
    }

    @Test
    fun askedItTalksOrSaysWhyItCant() {
        val asked = waiting().filter { it.ask }
        assertEquals(4, asked.size)
        for (s in asked) {
            val expected = when {
                // The mic not allowed comes first: a tap asks for it, whether or not the recogniser works.
                !s.micAllowed -> CircleAction.MIC_REFUSED
                !s.micWorks -> CircleAction.NO_RECOGNITION
                else -> CircleAction.TALK
            }
            assertEquals("$s", expected, s.action)
        }
    }

    @Test
    fun theMicButtonIsTheCircleWithAQuestionAsked() {
        // Whatever the voice is doing (while it speaks, the mic cuts it short and listens: Talk, not Skip).
        for (s in states) {
            assertEquals(
                "$s",
                CircleAction.of(false, false, s.listening, false, true, s.micAllowed, s.micWorks),
                CircleAction.mic(s.listening, s.micAllowed, s.micWorks),
            )
        }
    }

    @Test
    fun theMicButtonSaysTalkStopListeningOrWhyItCant() {
        assertEquals("Stop listening", mic(listening = true, micAllowed = true, micWorks = true))
        assertEquals("Talk", mic(listening = false, micAllowed = true, micWorks = true))
        assertEquals("Talk (the microphone is off)", mic(listening = false, micAllowed = false, micWorks = true))
        assertEquals("Talk (the microphone is off)", mic(listening = false, micAllowed = false, micWorks = false))
        assertEquals("Talk (speech recognition isn't available)", mic(listening = false, micAllowed = true, micWorks = false))
        // Never the circle's other actions, and never disabled: the mic button always does something.
        val all = states.map { CircleAction.mic(it.listening, it.micAllowed, it.micWorks) }.toSet()
        val talking = setOf(
            CircleAction.STOP_LISTENING, CircleAction.TALK, CircleAction.MIC_REFUSED, CircleAction.NO_RECOGNITION,
        )
        assertEquals(talking, all)
    }

    /** The mic button's name, in the app's words. */
    private fun mic(listening: Boolean, micAllowed: Boolean, micWorks: Boolean) =
        TestWords.text(CircleAction.mic(listening, micAllowed, micWorks).label)

    /** Not paused, speaking, listening or at an end. */
    private fun waiting() = states.filter { !it.paused && !it.speaking && !it.listening && !it.end }
}
