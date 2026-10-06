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
        assertEquals("level_intro", deported.end?.retry)
        assertTrue(deported.said().containsAll(listOf("Access denied", "You have been deported back to Earth")))

        assertEquals("the same level again", "L0_intro", s.restart("level_intro").node)
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
}
