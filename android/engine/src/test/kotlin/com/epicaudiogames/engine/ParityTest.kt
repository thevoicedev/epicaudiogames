package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Answers played through the maps take the same paths as in the Alexa skills (the rules are in each game's
 * alexa/lambda/Games/<game>/index.js in all-minigames-sites).
 */
class ParityTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private fun load(id: String) = GameMap.load(File(gamesDir, "$id/map.json"))

    private fun Session.at(node: String, vararg vars: Pair<String, Any>): Session {
        restore(Saved(node, vars.toMap(), false))
        return this
    }

    private fun Turn.plays() = steps.filterIsInstance<Step.Play>().map { it.path }

    @Test
    fun noodleRush() {
        val map = load("noodle-rush")
        val s = Session(map) { 0 }
        assertEquals("Page1", s.start().node)
        // doNoodleNo: "no" on the title leaves with "No problem!".
        s.answer("no").let { assertTrue(it.quit); assertEquals(listOf("common/no-problem"), it.plays()) }
        assertEquals("Page2", s.restart().let { s.answer("yes") }.node)
        // doNoodleYes: no "yes" branch, one forward option ("inside"): yes takes it.
        assertEquals("go", s.answer("yeah").node)
        assertEquals("walkaway", s.at("Page2").answer("nope").node)
        assertEquals("cut", s.at("go").answer("I'll skip the line").node)
        assertEquals("wait", s.at("go").answer("wait patiently").node)
        // The longest phrase wins.
        assertEquals("redlever", s.at("rehearse").answer("the red one").node)
        assertEquals("show", s.at("rehearse").answer("green").node)
        // The "nana" flag hands "search" over to "search-nana".
        s.at("chase", "nana" to true).answer("yes").let {
            assertEquals("search-nana", it.node)
            assertTrue("search" !in it.visited)
        }
        assertEquals("search", s.at("chase").answer("yes").node)
        // A one-option question: "no" gives up.
        s.at("sellmore").answer("no").let { assertTrue(it.quit); assertEquals(listOf("common/give-up"), it.plays()) }
        // repromptNoodle: anything else plays the question again.
        s.at("go").answer("banana").let { assertEquals("go", it.node); assertEquals(listOf("prompts/queue"), it.plays()) }
        // The skill has no repeat intent: "repeat" plays the question again, like any answer it doesn't know.
        assertEquals(listOf("prompts/queue"), s.at("go").answer("say that again").plays())
        s.at("order").answer("spicy").let {
            assertEquals("dragonfire", it.node)
            assertEquals("Dragon Fire Ending", it.end?.title)
            assertNull(it.ask)
        }
    }

    @Test
    fun frootopia() {
        val map = load("frootopia")
        val s = Session(map)
        assertEquals("fr-1", s.start().node)
        assertEquals("fr-2", s.answer("fine").node)                              // YES_EXACT
        s.at("fr-1").answer("I'm fine").let {                                     // not a whole-answer "fine"
            assertEquals("fr-1", it.node)
            assertEquals(listOf("common/unhandled"), it.plays())
        }
        assertEquals("fr-1a", s.at("fr-1").answer("I guess not").node)          // "guess not" beats "i guess"
        assertEquals("fr-1a", s.at("fr-1").answer("don't go").node)             // "don't" beats "go"
        assertEquals(listOf("scenes/fr-1"), s.at("fr-1").answer("repeat that").plays())
        assertEquals("fr-10a", s.at("fr-9").answer("let's fight").node)          // NODE_CHOICE_WORDS
        assertEquals("fr-10b", s.at("fr-9").answer("run away").node)
        assertEquals("fr-13", s.at("fr-12").answer("a pipe please").node)        // NAMED_ANSWER_IS
        assertEquals("fr-12a", s.at("fr-12").answer("no thanks").node)
        s.at("fr-gameover-1").answer("yes").let {
            assertEquals(listOf("_restart", "fr-1"), it.visited)
            assertEquals("common/restart", it.plays().first())
        }
        s.at("fr-gameover-1").answer("no").let { assertTrue(it.quit); assertEquals(listOf("scenes/fr-exit"), it.plays()) }
        // The endings: the scene, then the sting, then story 2 in the pack.
        for (ending in listOf("fr-54", "fr-55")) {
            val (from, said) = map.nodes.values.firstNotNullOf { n ->
                n.ask?.answers?.firstOrNull { it.go == Go.To(ending) }?.let { a -> n.id to (if (a.match is Match.Yes) "yes" else "no") }
            }
            s.at(from).answer(said).let {
                assertEquals(ending, it.node)
                assertEquals(listOf("scenes/$ending", "scenes/fr-sting"), it.plays())
                assertEquals("chapter", it.end?.kind)
                assertEquals("frootopia-stories", it.end?.locked)
            }
        }
    }

    @Test
    fun signalDecoders() {
        val map = load("signal-decoders")
        val s = Session(map)
        s.start().let {
            assertEquals(listOf("ai-title", "ai-open-1", "ai-open-2"), it.visited)
            assertEquals("ai-open-2", it.node)
        }
        // "Not sure" (a "sure" in it) asks again, with the sorry clip.
        s.answer("I'm not sure").let {
            assertEquals("ai-open-2", it.node)
            assertEquals(listOf("common/unhandled", "prompts/ai-open-2"), it.plays())
        }
        assertEquals("ai-open-no", s.answer("no thanks").node)
        assertTrue(s.answer("nope").quit)
        assertEquals("ai-p1", s.at("ai-open-2").answer("yes").node)

        // Puzzle 1: wrong, the hint; wrong again, the reveal, which flows on; tries back to 0.
        s.at("ai-p1").answer("a c a").let { assertEquals("ai-p1-hint", it.node); assertEquals(1.0, s.vars["tries"]) }
        s.answer("c c a").let {
            assertTrue(it.visited.containsAll(listOf("ai-p1-reveal", "ai-p1-yes")))
            assertEquals("ai-s3c", it.node)
            assertEquals(0.0, s.vars["tries"])
        }
        assertEquals("ai-s3c", s.at("ai-p1").answer("see a see").node)
        assertEquals("ai-s3c", s.at("ai-p1").answer("c ac").node)                   // a spelled run
        assertEquals("ai-s3c", s.at("ai-p1").answer("kak").node)                    // the regular expression
        assertEquals("ai-p1-again", s.at("ai-p1").answer("repeat").node)
        assertEquals("ai-s3c", s.at("ai-p1").answer("c a c again").node)             // an answer, not a repeat

        // Puzzle 2: "two two one one" only counts after the hint.
        assertEquals("ai-p2-hint", s.at("ai-p2", "tries" to 0.0).answer("two two one one").node)
        assertTrue(s.answer("two two one one").visited.contains("ai-p2-yes"))
        assertTrue(s.at("ai-p2").answer("forty two thousand two hundred and eleven").visited.contains("ai-p2-yes"))

        // The choice, its negation, and chapter 2 picking it up.
        s.at("ai-choice").answer("don't follow it").let {
            assertEquals("ai-fin-hide", it.node)
            assertEquals("chapter", it.end?.kind)
            assertEquals("ai2-title", it.end?.next)
        }
        assertEquals("hide", s.vars["episode1Choice"])
        s.nextChapter().let { assertTrue(it.visited.containsAll(listOf("ai2-title", "ai2-s1h"))) }
        assertEquals("ai-fin-follow", s.at("ai-choice").answer("follow the signal").node)
        s.at("ai-choice").answer("hmm").let {
            assertEquals("ai-choice", it.node)
            assertEquals(listOf("common/unhandled", "prompts/ai-choice"), it.plays())
        }
        // Chapter 5's end is the end of the season.
        val last = map.node("ai5-fin").end
        assertNotNull(last)
        assertEquals("ending", last!!.kind)
    }
}
