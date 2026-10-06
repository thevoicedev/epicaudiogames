package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExprTest {
    private fun eval(src: String, vararg vars: Pair<String, Any>) = Expr.parse(src).eval(vars.toMap())

    @Test
    fun arithmetic() {
        assertEquals(14.0, eval("2 + 3 * 4"))
        assertEquals(20.0, eval("(2 + 3) * 4"))
        assertEquals(3.0, eval("7 % 4"))
        assertEquals(-3.0, eval("-5 + 2"))
        assertEquals(70.0, eval("streak * 10", "streak" to 7.0))
        assertEquals(9.0, eval("max(best, streak)", "best" to 9.0, "streak" to 4.0))
        assertEquals(2.0, eval("floor(streak / 3)", "streak" to 8.0))
        assertEquals(1.0, eval("missing + 1"))
    }

    @Test
    fun logic() {
        val trick = Expr.parse("streak >= 3 && (streak - 3) % 4 == 0")
        assertTrue(trick.test(mapOf("streak" to 7.0)))
        assertFalse(trick.test(mapOf("streak" to 5.0)))
        assertFalse(trick.test(mapOf("streak" to 0.0)))
        assertEquals(8.0, eval("a > b ? a : b", "a" to 8.0, "b" to 3.0))
        assertTrue(Expr.parse("choice == \"hide\"").test(mapOf("choice" to "hide")))
        assertTrue(Expr.parse("!missing").test(emptyMap()))
        assertTrue(Expr.parse("mode == \"challenge\" || nose >= 50").test(mapOf("mode" to "battle", "nose" to 50.0)))
        assertEquals(setOf("streak", "best"), Expr.parse("streak > best && streak >= 2").names)
    }

    @Test
    fun rejectsNonsense() {
        for (bad in listOf("a >> 2", "(a", "max(", "a +", "foo(1)", "a = 2")) {
            try {
                Expr.parse(bad)
                throw AssertionError("accepted \"$bad\"")
            } catch (e: MapException) {
                // expected
            }
        }
    }
}

/** The steps that vary (when, pick, by), beds, computed values and decks, on a small map. */
class StepsTest {
    private fun clip(path: String) = """{ "play": "$path", "dur": 1.0, "lines": [{ "at": 0, "len": 1, "who": "H", "text": "$path" }] }"""

    private val map = GameMap.parse(
        """
        {
          "format": 1, "id": "t", "title": "T", "start": "a",
          "vars": { "n": 0, "best": 0, "mode": "x", "deck_d": "" },
          "keep": ["best", "deck_d"],
          "who": { "H": "" },
          "nodes": {
            "a": {
              "set": { "n": "+1", "best": "=n > best ? n : best" },
              "say": [
                { "bed": "music", "volume": 0.25, "dur": 9 },
                ${clip("always")},
                { "when": "n == 1", "play": "first", "dur": 1, "lines": [] , "sfx": true },
                { "when": "n != 1", "play": "later", "dur": 1, "lines": [], "sfx": true },
                { "pick": [[${clip("p0")}], [${clip("p1")}]] },
                { "by": "mode", "cases": { "x": [${clip("modeX")}] }, "else": [${clip("other")}] },
                { "bed": null }
              ],
              "go": { "draw": ["q1", "q2", "q3"], "deck": "d" }
            },
            "q1": { "say": [${clip("q1")}], "ask": { "answers": [{ "any": true, "go": "a" }] } },
            "q2": { "say": [${clip("q2")}], "ask": { "answers": [{ "any": true, "go": "a" }] } },
            "q3": { "say": [${clip("q3")}], "ask": { "answers": [{ "any": true, "go": "a" }] } }
          }
        }
        """.trimIndent(),
    )

    private fun paths(t: Turn) = t.steps.map {
        when (it) {
            is Step.Play -> it.path
            is Step.Bed -> "bed:${it.path}"
            else -> it.toString()
        }
    }

    @Test
    fun resolvesStepsAsTheTurnPlays() {
        val s = Session(map) { 1 }
        val first = s.start()
        assertEquals(listOf("bed:music", "always", "first", "p1", "modeX", "bed:null"), paths(first).take(6))
        assertEquals(1.0, s.vars["n"])
        assertEquals(1.0, s.vars["best"])
        val again = s.answer("anything")
        assertTrue("later" in paths(again))
        assertEquals(2.0, s.vars["best"])
    }

    @Test
    fun decksDrawEachNodeOnceThenStartAgain() {
        val s = Session(map) { 0 }
        val drawn = mutableListOf(s.start().node)
        repeat(2) { drawn += s.answer("go").node }
        assertEquals(setOf("q1", "q2", "q3"), drawn.toSet())
        drawn += s.answer("go").node          // all three drawn: the deck starts again
        assertTrue(drawn.last() in setOf("q1", "q2", "q3"))
        assertEquals(1, (s.vars["deck_d"] as String).split(',').size)
    }

    @Test
    fun keepsDecksAndBestAcrossRestarts() {
        val s = Session(map) { 0 }
        s.start()
        s.answer("go")
        val deck = s.vars["deck_d"]
        s.restart()
        assertEquals(1.0, s.vars["n"])                       // a fresh play
        assertEquals(2.0, s.vars["best"])                    // kept from the first play (2), not beaten by 1
        assertTrue((s.vars["deck_d"] as String).startsWith(deck as String))
    }
}
