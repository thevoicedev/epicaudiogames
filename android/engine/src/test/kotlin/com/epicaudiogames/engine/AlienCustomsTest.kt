package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Alien Customs plays as the skill does (Games/alien-customs/index.js, and the responses tools/capture.js recorded):
 * the welcome, Slug's announcement for each item in a shuffled order, the officer's questions, deportation after two
 * wrong answers, and the next level after three items cleared.
 */
class AlienCustomsTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val map = GameMap.load(File(gamesDir, "alien-customs/map.json"))

    private fun Turn.plays() = steps.mapNotNull {
        when (it) {
            is Step.Play -> it.path
            is Step.Bed -> "bed:${it.path}"
            else -> null
        }
    }

    private fun Turn.said() = steps.filterIsInstance<Step.Play>().flatMap { p -> p.lines.map { it.text } }

    /** Plays the level from its intro to its end, every answer to the officer right (or every one wrong). */
    private fun Session.playLevel(right: Boolean): Turn {
        var t = answer("yes")
        while (t.end == null) t = if (node.endsWith("_ann")) answer("play") else answer(reply(right))
        return t
    }

    /** The answer the officer wants at the current question (or the wrong one). */
    private fun Session.reply(right: Boolean): String {
        val ask = map.node(node).ask!!
        val yes = ask.answers.first { it.match is Match.Yes }
        val yesIsRight = Regex("""_r\d+$""").containsMatchIn((yes.go as Go.To).node)
        return if (yesIsRight == right) "yes" else "no"
    }

    @Test
    fun aLevelFromWelcomeToDeportation() {
        val s = Session(map)
        val welcome = s.start()
        assertEquals("L0_intro", welcome.node)
        assertTrue(welcome.said().first().startsWith("Welcome to Alien Customs."))

        val ann = s.answer("yes")
        assertTrue(ann.node.endsWith("_ann"))
        assertTrue(ann.said().first().startsWith("Listen carefully, there is an announcement about"))
        assertEquals("Repeat, or play?", ann.said().last())
        assertEquals("repeat replays the announcement", ann.node, s.answer("repeat").node)

        val start = s.answer("play")
        val item = start.node.removeSuffix("_q0")
        assertTrue("the level's intro comes before its first item", start.plays().any { it.startsWith("mix/intro-0-") })
        assertTrue(start.plays().any { it.startsWith("audio/dialogue/ordinal-first-") })
        assertTrue(start.plays().last().endsWith("$item-q1"))

        val wrong = s.answer(s.reply(false))
        assertTrue(wrong.plays().any { it.startsWith("mix/$item-w0-") })
        val host = wrong.steps.filterIsInstance<Step.Play>().filter { p -> p.lines.any { it.who == "HOST" } }
        assertEquals("one warning in Jessica's voice after the first mistake", 1, host.size)
        assertEquals("${item}_q1", wrong.node)

        val deported = s.answer(s.reply(false))
        assertEquals("gameover", deported.end?.kind)
        assertEquals("fixed: try again is the item's own level, not level_intro", "L0_intro", deported.end?.retry)
        assertTrue(deported.said().containsAll(listOf("Access denied", "You have been deported back to Earth")))

        assertEquals("the same level again", "L0_intro", s.restart(deported.end?.retry).node)
    }

    @Test
    fun clearingThreeItemsWinsTheLevel() {
        val s = Session(map)
        s.start()
        s.answer("yes")
        val items = mutableListOf<String>()
        var t = s.answer("play")
        while (t.end == null) {
            if (s.node.endsWith("_ann")) {
                t = s.answer("play")
                continue
            }
            items += s.node.substringBefore("_q")
            t = s.answer(s.reply(true))
        }
        assertEquals("chapter", t.end?.kind)
        assertEquals("L1_intro", t.end?.next)
        assertEquals(1.0, s.vars["level"])
        assertEquals("all three of the level's items, each once", 3, items.toSet().size)
        assertTrue(t.said().any { it.startsWith("Congratulations, traveler.") })

        // The next level, and the welcome back from level 3 on.
        assertEquals("L1_intro", s.nextChapter().node)
        s.restore(Saved("L1_intro", mapOf("level" to 2.0), false))
        assertEquals("L2_intro", s.restart("level_intro").node)
        assertTrue(s.restart("level_intro").said().first().startsWith("Welcome back to Alien Customs! You are currently on level 3"))
    }

    @Test
    fun theOfficerNeedsAYesOrNo() {
        val s = Session(map)
        s.start()
        s.answer("yes")
        s.answer("play")
        val asked = s.node
        val huh = s.answer("banana")
        assertEquals(asked, huh.node)
        assertEquals("The officer needs a yes or no answer.", huh.said().last())
        val forgiving = s.answer("yes it is")
        assertTrue(forgiving.visited.isNotEmpty())
    }

    @Test
    fun okayIsAYesAndNotNowANo() {
        // fixed: "okay", "ok" and "not now" weren't understood
        val s = Session(map)
        s.start()
        assertTrue(s.answer("okay").node.endsWith("_ann"))
        val leave = Session(map)
        leave.start()
        assertTrue(leave.answer("not now").quit)
    }

    @Test
    fun playAgainAfterTheLastFreeLevelKeepsTheLevelInStep() {
        // fixed: a win added 1 to level, so after PLAY AGAIN at "Level 5 cleared" it drifted (level 1 won made it 6)
        val s = Session(map)
        s.restore(Saved("L1_intro", mapOf("level" to 4.0), false))
        assertEquals("L4_intro", s.restart("level_intro").node)
        val five = s.playLevel(true)
        assertEquals("alien-customs-levels", five.end?.locked)
        assertEquals(5.0, s.vars["level"])

        assertEquals("level 6 is in the pack: level 1 again", "L0_intro", s.restart().node)
        val one = s.playLevel(true)
        assertEquals("L1_intro", one.end?.next)
        assertEquals(1.0, s.vars["level"])

        assertEquals("L1_intro", s.nextChapter().node)
        val deported = s.playLevel(false)
        assertEquals("gameover", deported.end?.kind)
        assertEquals("try again is level 2", "L1_intro", s.restart(deported.end?.retry).node)
    }

    @Test
    fun withThePackEachWinSetsItsOwnLevel() {
        // fixed: the pack's wins added 1 too, so a level that had drifted stayed off
        val packs = File(gamesDir, "alien-customs/packs").listFiles { f -> f.extension == "json" }.orEmpty().toList()
        val full = GameMap.load(File(gamesDir, "alien-customs/map.json"), packs)
        for (k in 0 until 15) {
            val s = Session(full)
            s.restore(Saved("L${k}_win", mapOf("level" to 9.0), false))
            val won = s.restart("L${k}_win")
            assertEquals("L${k}_win", if (k < 14) k + 1.0 else 0.0, s.vars["level"])
            assertEquals(if (k < 14) "L${k + 1}_intro" else "level_intro", won.end?.next)
        }
    }
}
