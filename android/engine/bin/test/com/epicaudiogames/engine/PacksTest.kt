package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A pack merged into its game: new nodes and variables, and the nodes it replaces (docs/MAP_FORMAT.md, Packs). */
class PacksTest {
    private val base = """
        {"format": 1, "id": "demo", "title": "Demo", "start": "a", "vars": {"level": 0}, "keep": ["level"],
         "who": {"HOST": ""},
         "nodes": {
           "a": {"say": [], "ask": {"reprompt": [], "answers": [{"yes": true, "go": "won1"}]}},
           "won1": {"set": {"level": "+1"}, "say": [],
                    "end": {"kind": "chapter", "title": "Level 1", "next": "level2", "locked": "demo-levels"}}
         }}
    """.trimIndent()

    private val pack = """
        {"format": 1, "game": "demo", "id": "demo-levels", "vars": {"stars": 0}, "keep": ["stars"],
         "who": {"GUIDE": "Guide"},
         "nodes": {
           "won1": {"set": {"level": "+1"}, "say": [], "end": {"kind": "chapter", "title": "Level 1", "next": "level2"}},
           "level2": {"set": {"stars": "+1"}, "say": [], "end": {"kind": "ending", "title": "All done"}}
         }}
    """.trimIndent()

    @Test
    fun withoutThePackTheNextLevelIsLocked() {
        val map = GameMap.parse(base)
        val s = Session(map)
        s.start()
        val won = s.answer("yes")
        assertEquals("demo-levels", won.end?.locked)
        assertFalse("level2" in map.nodes)
    }

    @Test
    fun thePackAddsAndReplacesNodes() {
        val map = GameMap.parse(base, listOf(pack))
        assertEquals(setOf("level", "stars"), map.keep)
        assertEquals("Guide", map.who["GUIDE"])
        val s = Session(map)
        s.start()
        val won = s.answer("yes")
        assertNull("the pack's own end isn't locked", won.end?.locked)
        val next = s.nextChapter()
        assertEquals("level2", next.node)
        assertEquals(1.0, s.vars["stars"])
        assertEquals(1.0, s.vars["level"])
    }

    @Test
    fun aPackForAnotherGameIsRefused() {
        val other = pack.replace("\"game\": \"demo\"", "\"game\": \"other\"")
        val e = runCatching { GameMap.parse(base, listOf(other)) }.exceptionOrNull()
        assertTrue(e is MapException)
    }
}
