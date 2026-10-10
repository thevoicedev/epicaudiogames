package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Time to answer (Settings › Sound and voice; docs/DESIGN.md): when Android's recogniser gives up on a silent listen
 * before the player's time is up, the mic listens on ([listensAgain]) rather than count a silence, until too little
 * time is left to be worth it. iOS waits for the time itself (EndpointerTests).
 */
class AnswerTimeTest {
    private val normal = AnswerTime.NORMAL.millis
    private val longer = AnswerTime.LONGER.millis
    private val longest = AnswerTime.LONGEST.millis

    @Test
    fun theTimesAreSixTenAndFifteenSeconds() {
        assertEquals(listOf(6_000L, 10_000L, 15_000L), AnswerTime.entries.map { it.millis })
    }

    @Test
    fun aRecogniserGivingUpEarlyListensOn() {
        assertTrue(listensAgain(heardForMs = 3_000, answerMs = normal, again = 0))
        assertTrue(listensAgain(heardForMs = 5_000, answerMs = longer, again = 0))
        assertTrue(listensAgain(heardForMs = 5_000, answerMs = longest, again = 0))
        assertTrue(listensAgain(heardForMs = 10_000, answerMs = longest, again = 1))
    }

    @Test
    fun withLittleTimeLeftTheSilenceCounts() {
        // Normal's six seconds: a recogniser's usual five is near enough.
        assertFalse(listensAgain(heardForMs = 5_000, answerMs = normal, again = 0))
        assertFalse(listensAgain(heardForMs = 4_001, answerMs = normal, again = 0))
        assertTrue(listensAgain(heardForMs = 4_000, answerMs = normal, again = 0))
        // The time up, or past it.
        assertFalse(listensAgain(heardForMs = 10_000, answerMs = longer, again = 1))
        assertFalse(listensAgain(heardForMs = 16_000, answerMs = longest, again = 2))
    }

    @Test
    fun theWholeLongestTimeWithARecogniserThatGivesUpEveryFiveSeconds() {
        var heard = 0L
        var again = 0
        while (true) {
            heard += 5_000
            if (!listensAgain(heard, longest, again)) break
            again++
        }
        // It listened at 0, 5 and 10 seconds: fifteen in all.
        assertEquals(2, again)
        assertEquals(15_000L, heard)
    }

    @Test
    fun aRecogniserThatGivesUpAtOnceIsntStartedOverForEver() {
        var again = 0
        while (listensAgain(heardForMs = 0, answerMs = longest, again = again)) again++
        assertEquals(MAX_LISTENS_AGAIN, again)
    }
}
