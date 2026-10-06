package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Pirate Quest plays as the skill does (Games/pirate-quest/index.js, and the responses tools/capture.js recorded):
 * the choices and the skill's words for them, the stats that change what is heard (coins for the dice, reputation
 * for the Spanish trick, the royal information at the tavern), and leaving with the place kept.
 */
class PirateQuestTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val map = GameMap.load(File(gamesDir, "pirate-quest/map.json"))

    private fun Turn.plays() = steps.mapNotNull { (it as? Step.Play)?.path }

    private fun Turn.said() = steps.filterIsInstance<Step.Play>().flatMap { p -> p.lines.map { it.text } }

    /** A session at a node, with these stats (the rest as at the start). */
    private fun at(node: String, vararg vars: Pair<String, Any>, choose: (Int) -> Int = { 0 }) =
        Session(map, choose).apply { restore(Saved(node, map.vars + vars, false)) }

    @Test
    fun theStartAndTheFirstChoices() {
        val s = Session(map) { 0 }
        val start = s.start()
        assertEquals("ac-1", start.node)
        assertEquals("audio/pirate-quest-intro", start.plays().first())
        assertTrue(start.said().last().endsWith("Are you ready to begin your quest?"))

        val plan = s.answer("yes")
        assertEquals("ac-1a", plan.node)
        assertTrue(plan.plays().contains("audio/one-eyed-will-intro"))
        assertEquals(listOf("map", "supplies"), s.ask!!.buttons.map { it.value })

        val supplies = s.answer("stock up")
        assertEquals("ac-2", supplies.node)
        assertEquals("supplies once: 50 + 5", 55.0, s.vars["coins"])
        val again = s.answer("repeat")
        assertEquals("repeat plays the node again, and the coins aren't given twice", "ac-2", again.node)
        assertTrue(again.plays().contains("audio/supplies-sailor"))
        assertEquals(55.0, s.vars["coins"])
        assertEquals("ac-3", s.answer("hire").node)
        assertEquals("You can say FIGHT, FLEE, or TALK", s.answer("banana").said().single())
    }

    @Test
    fun noToStartingLeavesTheGame() {
        val s = Session(map) { 0 }
        s.start()
        val bye = s.answer("no")
        assertTrue(bye.quit)
        assertFalse(bye.keep)
        assertEquals(listOf("Begin your pirate adventure another time."), bye.said())
    }

    @Test
    fun notSailingOnLeavesWithThePlaceKept() {
        val s = at("ac-3")
        val fled = s.answer("flee")
        assertEquals("ac-3b", fled.node)
        assertEquals(5.0, s.vars["reputation"])
        val bye = s.answer("no")
        assertEquals(listOf("Thanks for playing."), bye.said())
        assertTrue(bye.quit && bye.keep)
        assertEquals("the question it left from", "ac-3b", s.node)

        val back = Session(map).resume(s.save())
        assertEquals("ac-3b", back.node)
        assertTrue(back.plays().contains("audio/pirate-flee"))
        assertEquals("the reputation isn't taken twice", 5.0, s.vars["reputation"])
    }

    @Test
    fun theDiceGame() {
        // Every die a 1: a draw.
        val draw = at("ac-8", "coins" to 50.0).answer("dice")
        assertEquals("ac-8b", draw.node)
        assertTrue(draw.said().containsAll(listOf("You have 50 coins.", "You wager 10 coins.",
            "You rolled 1, 1, 1 for a total of 3!", "They rolled 1, 1, 1 for a total of 3.")))
        assertTrue(draw.plays().contains("audio/tie-message"))

        // Three sixes against three ones: 10 coins won, the dice read highest first.
        val rolls = ArrayDeque(listOf(5, 4, 3, 0, 1, 0))
        val s = at("ac-8", "coins" to 50.0) { n -> if (n == 6) rolls.removeFirstOrNull() ?: 0 else 0 }
        val won = s.answer("dice")
        assertTrue(won.said().containsAll(listOf("You rolled 6, 5, 4 for a total of 15!",
            "They rolled 2, 1, 1 for a total of 4.", "You won 10 coins.", "You have 60 coins.")))
        assertEquals(60.0, s.vars["coins"])
        assertEquals("roll again", "ac-8b", s.answer("roll").node)

        // No coins: the pouch is empty, and on to the inn.
        val broke = at("ac-8", "coins" to 5.0).answer("dice")
        assertTrue(broke.plays().contains("audio/pouch-empty"))
        assertEquals("ac-9", broke.node)
        // At the second dice game, on to the tavern (the skill sends you back to the first inn).
        val broke2 = at("ac-22", "coins" to 0.0).answer("dice")
        assertEquals("ac-25", broke2.node)
    }

    @Test
    fun statsChangeTheStory() {
        assertTrue(at("ac-16b", "reputation" to 50.0).answer("yes").plays().contains("audio/convinced-spanish"))
        assertTrue(at("ac-16b", "reputation" to 10.0).answer("yes").plays().contains("audio/suspicious-spaniard"))
        assertEquals("no royal information: Captain Blacktooth", "ac-25", at("ac-22a").answer("yes").node)
        val tavern = at("ac-22a", "royalInfo" to true).answer("yes")
        assertEquals("ac-23", tavern.node)
        assertTrue(tavern.plays().contains("audio/introduce-english"))
    }

    @Test
    fun theSkillsOwnWordsAndNumbers() {
        assertEquals("no is a duel (a mishear of joe)", "ac-3a2", at("ac-3a1").answer("no").node)
        assertEquals("4 is board", "ac-16a", at("ac-15").answer("4").node)
        assertEquals("5 is fight", "ac-16", at("ac-15").answer("five").node)
        val end = at("ac-shanty").answer("no")
        assertEquals("ending", end.end?.kind)
        assertFalse(at("ac-28a").answer("yes").said().any { it.contains("minigames") })
    }
}
