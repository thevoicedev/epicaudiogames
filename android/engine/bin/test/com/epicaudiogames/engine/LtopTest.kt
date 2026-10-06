package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Leaning Tower of Pizza plays as the skill does (Games/leaning-tower-of-pizza/index.js, and the responses that
 * tools/capture.js recorded from it): the question order, the nose, the win and the challenge mode.
 */
class LtopTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val map = GameMap.load(File(gamesDir, "leaning-tower-of-pizza/map.json"))

    private fun Turn.plays() = steps.mapNotNull {
        when (it) {
            is Step.Play -> it.path
            is Step.Bed -> "bed:${it.path}"
            else -> null
        }
    }

    private fun Turn.said() = steps.filterIsInstance<Step.Play>().flatMap { p -> p.lines.map { it.text } }

    /** The word that lies (or tells the truth) at the current question. */
    private fun Session.word(lie: Boolean): String {
        val a = map.node(node).ask!!.answers.first { it.match is Match.Words && it.go == Go.To(if (lie) "lie" else "honest") }
        return (a.match as Match.Words).phrases.first().text
    }

    private fun Session.lie() = answer(word(true))
    private fun Session.truth() = answer(word(false))

    @Test
    fun firstBattle() {
        val s = Session(map)
        val intro = s.start()
        assertEquals("first_intro", intro.node)
        assertEquals("bed:audio/background", intro.plays().first())
        assertTrue(intro.said().last().endsWith("Are you ready to play?"))

        val battle = s.answer("yes")
        assertTrue("an easy first question", battle.node.startsWith("q_ez"))
        assertEquals(listOf("bed:audio/background", "bed:audio/throw-loop"), battle.plays().take(2))
        assertTrue(battle.said().contains("Let's save the city!"))
        assertEquals("True, or false?", battle.said().last())

        val lie = s.lie()
        assertEquals(10.0, s.vars["nose"])
        assertTrue(lie.plays().containsAll(listOf("audio/fx/correct-ping", "bed:audio/throw-loop")))
        assertTrue(lie.plays().any { it.startsWith("mix/lie-40-") })
        assertTrue(lie.said().any { it == "Only 40 metres to go!" })
        assertTrue("then the main questions", lie.node.startsWith("q_q"))

        val honest = s.truth()
        assertEquals(10.0, s.vars["nose"])
        assertTrue(honest.said().contains("40 metres to go!"))
        assertTrue(honest.plays().any { it.startsWith("mix/wrong-") })

        s.truth()
        assertTrue("the 4th question is a trick", s.node.startsWith("q_tr"))
        repeat(3) { s.lie() }
        assertEquals(40.0, s.vars["nose"])
        assertTrue("on the very first battle the winning question is a double negative", s.node.startsWith("q_dn"))
        assertEquals("the 5th lie wins, and unlocks challenge mode", "unlock", s.lie().node)
    }

    @Test
    fun winUnlocksChallengeMode() {
        val s = Session(map)
        s.start()
        s.answer("yes")
        var t: Turn
        do t = s.lie() while (t.ask != null && s.node.startsWith("q_") && s.vars["nose"] != 50.0)
        assertEquals("unlock", t.node)
        assertTrue(t.plays().contains("audio/never-stop-2"))
        assertTrue(t.plays().contains("bed:null"))
        assertTrue(t.said().contains("You've just unlocked challenge mode!"))
        assertEquals(true, s.vars["unlocked"])

        val start = s.answer("yes")
        assertTrue(start.plays().contains("audio/gepetto/intro-first-time"))
        assertTrue(start.node.startsWith("q_ez"))
        assertEquals(true, s.vars["playedChallenge"])

        val one = s.lie()
        assertEquals(1.0, s.vars["streak"])
        assertTrue(one.plays().any { it.startsWith("audio/gepetto/milestone-1/") })
        assertTrue(one.plays().contains("audio/grow-nose"))         // the skill's ltop-nose-grow.mp3 isn't on the CDN
        assertTrue(one.said().contains("Your nose is 10 metres long."))
        s.lie()
        s.lie()
        assertTrue("a trick question after the 3rd lie in a row", s.node.startsWith("q_tr"))

        val q = s.vars["q"] as String
        val over = s.truth()
        assertEquals("c_over", over.node)
        assertEquals("gameover", over.end?.kind)
        assertTrue(over.said().contains("Your streak was 3!"))
        assertEquals(3.0, s.vars["best"])
        assertNotNull(q)

        // Played again: the mode question, Gepetto's welcome back, the high scores.
        val again = s.restart("start")
        assertEquals("mode_select", again.node)
        assertEquals("scores", s.answer("what's my high score").node)
        assertTrue(s.answer("challenge").plays().any { it.startsWith("audio/gepetto/intro-return/") })
        s.restart("start")
        assertTrue(s.answer("battle please").node.startsWith("q_ez"))
    }

    @Test
    fun resumingPlaysTheRandomPartsToo() {
        val s = Session(map)
        s.start()
        val back = Session(map).resume(s.save())
        assertTrue("the intro's robot line (a pick) is played on a resume", back.plays().any { it.startsWith("audio/monster/") })
    }

    @Test
    fun answerWords() {
        val s = Session(map)
        s.start()
        s.answer("yes")
        val lieIsTrue = s.word(true) in listOf("true", "too", "two", "2")
        val lieWord = if (lieIsTrue) "two" else "pause"            // "pause" is a mishear of "false"
        assertEquals("lie", s.answer(lieWord).visited.first())

        val asked = s.node
        val banana = s.answer("banana")
        assertEquals(asked, banana.node)
        assertTrue(banana.said().last() == "True, or false?")
        val falseIsLie = s.word(true) !in listOf("true", "too", "two", "2")
        val yesNo = s.answer("yes no")                              // the last word: "no", so false
        assertEquals(if (falseIsLie) "lie" else "honest", yesNo.visited.first())
    }
}
