package com.epicaudiogames.app

import androidx.compose.ui.graphics.Color
import com.epicaudiogames.app.ui.theme.EpicColors
import com.epicaudiogames.app.ui.transcriptText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The transcript's highlight (docs/DESIGN.md › Game › Transcript): which word the voice is on as a line is said
 * ([currentWord]), and how the line is drawn around it ([transcriptText]): only that word in inverse colours, the
 * words still to come at full strength or hidden but in place. iOS: EpicAppCore's TranscriptTests.swift.
 */
class HighlightTest {
    private val line = "Hello there, friend"

    @Test
    fun aLineJustBegunIsOnItsFirstWord() {
        assertEquals(CurrentWord("", "Hello", " there, friend"), currentWord(line, 0))
        assertEquals(CurrentWord("", "Hello", " there, friend"), currentWord(line, 3))
    }

    @Test
    fun theWordIsTheOneTheNextCharacterIsIn() {
        // "Hello th|ere,": inside "there,", with its comma.
        assertEquals(CurrentWord("Hello ", "there,", " friend"), currentWord(line, 8))
        // "Hello |there": the space said, "there," is next.
        assertEquals(CurrentWord("Hello ", "there,", " friend"), currentWord(line, 6))
    }

    @Test
    fun onTheSpaceAfterAWordItsStillThatWord() {
        assertEquals(CurrentWord("", "Hello", " there, friend"), currentWord(line, 5))
        assertEquals(CurrentWord("Hello ", "there,", " friend"), currentWord(line, 12))
    }

    @Test
    fun aLineSaidToItsEndStaysOnItsLastWord() {
        assertEquals(CurrentWord("Hello there, ", "friend", ""), currentWord(line, line.length))
        // Beyond the end (a line that joined another counts on), and before the start: held to the line.
        assertEquals(CurrentWord("Hello there, ", "friend", ""), currentWord(line, line.length + 10))
        assertEquals(CurrentWord("", "Hello", " there, friend"), currentWord(line, -3))
    }

    @Test
    fun spacesAroundTheWordsStayWhereTheyAre() {
        assertEquals(CurrentWord("  ", "Hi", "  you "), currentWord("  Hi  you ", 0))
        assertEquals(CurrentWord("  ", "Hi", "  you "), currentWord("  Hi  you ", 5))
        assertEquals(CurrentWord("  Hi  ", "you", " "), currentWord("  Hi  you ", 6))
        assertEquals(CurrentWord("  Hi  ", "you", " "), currentWord("  Hi  you ", 10))
        assertEquals(CurrentWord("one\n", "two", ""), currentWord("one\ntwo", 4))
    }

    @Test
    fun aLineWithNoWordsHasNoneToHighlight() {
        assertEquals(CurrentWord("", "", ""), currentWord("", 0))
        assertEquals(CurrentWord("   ", "", ""), currentWord("   ", 2))
    }

    @Test
    fun theThreePartsAreAlwaysTheWholeLineAndTheWordMovesOnlyForward() {
        for (text in listOf(line, "  Hi  you ", "One.", "A b  c, d!", "“Quick,” said Pip. “Run!”")) {
            var lastStart = 0
            for (said in -2..text.length + 2) {
                val (before, word, after) = currentWord(text, said)
                assertEquals("$text at $said", text, before + word + after)
                assertTrue("$text at $said: \"$word\"", word.isNotEmpty() && word.none { it.isWhitespace() })
                assertTrue("$text at $said went back", before.length >= lastStart)
                lastStart = before.length
            }
        }
    }

    @Test
    fun aLineNotBeingSpokenIsDrawnAsItIs() {
        val text = transcriptText(line, saidChars = null, highlight = true, wholeLine = false, colors = EpicColors.dark)
        assertEquals(line, text.text)
        assertTrue(text.spanStyles.isEmpty())
    }

    @Test
    fun onlyTheCurrentWordIsHighlightedInInverseColours() {
        val c = EpicColors.light
        val text = transcriptText(line, saidChars = 8, highlight = true, wholeLine = true, colors = c)
        assertEquals(line, text.text)
        val span = text.spanStyles.single()
        assertEquals("there,", line.substring(span.start, span.end))
        assertEquals(c.highlightText, span.item.color)
        assertEquals(c.highlightBg, span.item.background)
    }

    @Test
    fun withoutTheWholeLineTheWordsToComeAreHiddenButKeepTheirPlace() {
        val text = transcriptText(line, saidChars = 8, highlight = true, wholeLine = false, colors = EpicColors.dark)
        // Every character is still there, so the bubble doesn't change size as the words appear.
        assertEquals(line, text.text)
        val hidden = text.spanStyles.single { it.item.color == Color.Transparent }
        assertEquals(" friend", line.substring(hidden.start, hidden.end))
    }

    @Test
    fun withTheHighlightOffTheWordsAreAllTheSame() {
        val plain = transcriptText(line, saidChars = 8, highlight = false, wholeLine = true, colors = EpicColors.dark)
        assertTrue(plain.spanStyles.isEmpty())
        // The whole line off still hides what's to come, with no word marked.
        val hiding = transcriptText(line, saidChars = 8, highlight = false, wholeLine = false, colors = EpicColors.dark)
        val hidden = hiding.spanStyles.single()
        assertEquals(Color.Transparent, hidden.item.color)
        assertEquals(" friend", line.substring(hidden.start, hidden.end))
    }
}
