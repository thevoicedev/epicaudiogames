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
        assertEquals("42211", Text.digits("for to to one one"))
        assertEquals("11224", Text.digits("won won to to for"))
        assertEquals("400", Text.digits("for hundred"))
        // fixed: "to", "for", "won" and "oh" on their own were numbers ("I want to play" said 2)
        assertEquals("", Text.digits("I want to play"))
        assertEquals("", Text.digits("go for it"))
        assertEquals("", Text.digits("I need to listen to it again"))
        assertEquals("", Text.digits("oh yes I won"))
        assertEquals("1", Text.digits("I want to play this one"))
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
        assertTrue(Text.negated("of course not", "of course"))
        assertTrue(Text.negated("i would not", "i would"))
        assertFalse(Text.negated("follow not hide", "follow"))      // a "not" after it only when it ends the answer
        assertFalse(Text.negated("not", "not"))
    }

    @Test
    fun findsUnsureAnswers() {
        assertTrue(Text.unsure("i'm not sure"))
        assertTrue(Text.unsure("i don't know"))
        assertTrue(Text.unsure("dunno"))
        assertFalse(Text.unsure("sure"))
        assertFalse(Text.unsure("i know"))
        assertFalse(Text.unsure("not surely"))
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
