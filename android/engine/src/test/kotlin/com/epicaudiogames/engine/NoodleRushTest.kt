package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Noodle Rush takes a yes or a no only as the whole answer, as the skill's doNoodleAnswer does, from a longer list
 * than the skill's ("okay", "I do", "not now"), and the title takes being ready.
 */
class NoodleRushTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val map = GameMap.load(File(gamesDir, "noodle-rush/map.json"))

    /** The answer to the title's "Are you ready to play?". */
    private fun title(said: String): Turn = Session(map).run {
        start()
        answer(said)
    }

    @Test
    fun theTitleTakesBeingReady() {
        // fixed: only the skill's own words were taken, so "I'm ready" or "okay" asked again
        for (said in listOf("I'm ready", "yes I'm ready", "let's play", "yeah let's go", "okay", "sure thing", "yes okay")) {
            assertEquals(said, "Page2", title(said).node)
        }
        for (said in listOf("not now", "no thank you")) assertTrue(said, title(said).quit)
        assertEquals("not a yes", "Page1", title("I'm not sure").node)
        assertEquals("a no inside a sentence isn't the answer", "Page1", title("I have no idea").node)
    }

    @Test
    fun laterQuestionsTakeTheLongerListsToo() {
        val s = Session(map)
        s.start()
        s.answer("yes")
        assertEquals("Page2: do you want to go inside?", "go", s.answer("I do").node)
        val s2 = Session(map)
        s2.start()
        s2.answer("yes")
        assertEquals("being ready is only the title's", "Page2", s2.answer("let's go").node)
    }
}
