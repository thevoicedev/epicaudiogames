package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Answers the games used to take the wrong way: a negated or unsure answer taken as a yes (or "I don't know" as a
 * no), and "to", "for", "won" or "oh" read as numbers. These depart from the Alexa skills on purpose.
 */
class AnswersTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private fun load(id: String) = GameMap.load(File(gamesDir, "$id/map.json"))

    /** The answer [said] is taken as at [node], or null. */
    private fun taken(map: GameMap, node: String, said: String): Answer? =
        Matcher.match(map, map.node(node).ask!!, map.vars, said).index?.let { map.node(node).ask!!.answers[it] }

    @Test
    fun aNegatedOrUnsureAnswerIsNeitherYesNorNo() {
        val asks = listOf("frootopia" to "fr-1a", "signal-decoders" to "ai-open-2", "alien-customs" to "L0_intro",
            "pirate-quest" to "ac-3a2")
        for ((game, node) in asks) {
            val map = load(game)
            assertTrue("$game: yes", taken(map, node, "yes")?.match is Match.Yes)
            for (said in listOf("I'm not sure", "of course not", "definitely not", "I'm not ready", "probably not",
                "I don't know", "no idea")) {
                val a = taken(map, node, said)
                assertFalse("$game: \"$said\" is a yes", a?.match is Match.Yes)
                val unsure = said in listOf("I don't know", "no idea")
                assertFalse("$game: \"$said\" is a no", a?.match is Match.No && unsure)
            }
        }
        val froot = load("frootopia")
        assertTrue(taken(froot, "fr-1a", "of course")?.match is Match.Yes)
        assertTrue(taken(froot, "fr-1a", "I guess not")?.match is Match.No)          // "guess not" is a no word
        assertTrue(taken(froot, "fr-1a", "no I'm not ready")?.match is Match.No)
        // Still heard, so the app doesn't take another of the recogniser's guesses ("of course") instead.
        val s = Session(froot).apply { restore(Saved("fr-1a", emptyMap(), false)) }
        for (said in listOf("I'm not sure", "of course not", "I don't know")) assertTrue(said, s.understands(said))
        assertFalse(s.understands("banana"))
    }

    @Test
    fun notTrueIsFalse() {
        // fixed: "not true" was a true (the skill's parseTrueFalse looks for "true" first); now it's a false
        val map = load("leaning-tower-of-pizza")
        val node = map.nodes.keys.first { it.startsWith("q_") && map.node(it).ask != null }
        val truth = taken(map, node, "true")?.go
        val falsehood = taken(map, node, "false")?.go
        assertNotEquals(truth, falsehood)
        for (said in listOf("not true", "that's not true")) assertEquals(said, falsehood, taken(map, node, said)?.go)
        assertEquals(truth, taken(map, node, "not false")?.go)
        assertEquals(null, taken(map, node, "I'm not too sure"))      // a mishear of true, said with "not": neither
    }

    @Test
    fun aChoiceStillTakesItsOpposite() {
        val map = load("signal-decoders")
        fun choice(said: String) = (taken(map, "ai-choice", said)?.set?.get("choice") as? SetValue.Assign)?.value
        assertEquals("hide", choice("don't follow it"))
        assertEquals("follow", choice("follow it"))
        // fixed: the "not" of "not sure" made it a "don't follow", so it hid
        assertEquals(null, taken(map, "ai-choice", "I'm not sure, follow"))
    }

    @Test
    fun toAndForArentNumbersOnTheirOwn() {
        // fixed: "I want to play" read as 2 and picked story 2; "go for it" as 4
        val wolf = load("the-werewolf")
        fun at(said: String) = taken(wolf, "offer", said)?.go?.let { (it as Go.To).node }
        for (said in listOf("I want to play", "yes I want to play", "I'm ready to play")) {
            assertEquals(said, "offer_yes", at(said))
        }
        assertEquals("offer_n4", at("four"))
        assertNotEquals("offer_n2", at("I'd love to"))
        assertNotEquals("offer_n4", at("go for it"))

        // A request to hear the puzzle again isn't a guess.
        val sd = load("signal-decoders")
        val s = Session(sd)
        s.restore(Saved("ai3-p2", mapOf("tries" to 0.0), false))
        assertNotEquals("digits", s.answer("I need to listen to it again").heard?.how)
        assertEquals(0.0, s.vars["tries"])
        s.restore(Saved("ai5-p1", mapOf("tries" to 0.0), false))
        assertTrue(s.answer("one zero").visited.contains("ai5-p1-yes"))
    }
}
