package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TextTest {
    @Test
    fun normalises() {
        assertEquals("don't follow it", Text.normalise("Don’t FOLLOW it!"))
        assertEquals("c a c", Text.normalise("  C, A... C?  "))
        assertEquals("", Text.normalise("?!"))
    }

    @Test
    fun matchesWholeWords() {
        assertTrue(Text.phraseLength("the red one", Phrase("red", false)) > 0)
        assertEquals(-1, Text.phraseLength("i'm ready", Phrase("red", false)))
        assertTrue(Text.phraseLength("fine", Phrase("fine", true)) > 0)
        assertEquals(-1, Text.phraseLength("i'm fine", Phrase("fine", true)))
        assertEquals("no rehearsal", Text.longest("no rehearsal please", listOf(Phrase("rehearsal", false), Phrase("no rehearsal", false)))?.text)
    }

    @Test
    fun readsDigitsLikeTheSkill() {
        assertEquals("42211", Text.digits("four two two one one"))
        assertEquals("42211", Text.digits("4 2 2 1 1"))
        assertEquals("42211", Text.digits("four twenty-two eleven"))
        assertEquals("42211", Text.digits("forty two thousand two hundred and eleven"))
        assertEquals("314", Text.digits("three one four"))
        assertEquals("2211", Text.digits("to too won one"))
        assertEquals("10", Text.digits("ten"))
        assertEquals("100", Text.digits("one hundred"))
        assertEquals("", Text.digits("a hundred"))          // as in the skill: no number word, no digits
        assertEquals("", Text.digits("no idea"))
    }

    @Test
    fun readsSymbols() {
        val letters = mapOf("c" to listOf("c", "see", "sea"), "a" to listOf("a", "ay", "eh"))
        assertEquals("cac", Text.symbols("see a see", letters))
        assertEquals("c", Text.symbols("c ac", letters))
        assertEquals("cac", Text.symbols("c ac", letters, spelled = true))
        val turns = mapOf("l" to listOf("left", "lift"), "r" to listOf("right", "write"))
        assertEquals("lrrl", Text.symbols("left, right, write, lift!", turns))
    }

    @Test
    fun findsNegation() {
        assertTrue(Text.negated("don't follow it", "follow"))
        assertTrue(Text.negated("i really don't want to follow", "follow"))
        assertTrue(Text.negated("let's not hide", "hide"))
        assertFalse(Text.negated("follow it", "follow"))
        assertFalse(Text.negated("don't you want to go on and follow", "follow"))
    }
}

class ConditionTest {
    @Test
    fun tests() {
        val vars = mapOf("tries" to 2.0, "choice" to "hide", "nana" to true, "empty" to "")
        assertTrue(Condition.parse("tries >= 2").test(vars))
        assertFalse(Condition.parse("tries < 2").test(vars))
        assertTrue(Condition.parse("choice == \"hide\"").test(vars))
        assertTrue(Condition.parse("nana && tries != 3").test(vars))
        assertTrue(Condition.parse("!empty").test(vars))
        assertTrue(Condition.parse("missing || nana").test(vars))
        assertFalse(Condition.parse("missing").test(vars))
        assertEquals(setOf("nana", "tries"), Condition.parse("nana && tries > 1").names)
    }

    @Test(expected = MapException::class)
    fun rejectsNonsense() {
        Condition.parse("tries >> 2")
    }
}
