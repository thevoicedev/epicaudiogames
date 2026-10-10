package com.epicaudiogames.app

import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.Step
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The word marked as a help page is read aloud ([HelpHighlight]): from the line's word times where it has them, else
 * spread evenly over the line, as the game's transcript is; on a page, the paragraph its clip reads, with nothing for
 * an earcon's clip. iOS: EpicAppCore's HelpHighlightTests.
 */
class HelpHighlightTest {
    private val said = "Say “repeat” to hear it again."
    /** Its six words start 0, 0.4, 1.2, 1.4, 1.9 and 2.1 seconds into the line, which starts 0.5 s into its clip. */
    private val timed = Line(at = 0.5, len = 2.6, who = "HOST", text = said, words = listOf(0.0, 0.4, 1.2, 1.4, 1.9, 2.1))
    private val untimed = Line(at = 0.0, len = 2.0, who = "HOST", text = "Email us at james@hugo.fm.")

    @Test
    fun withWordTimesItsTheWordThatHasBegun() {
        assertEquals("Say", wordAt(timed, 0.5))
        assertEquals("Say", wordAt(timed, 0.89))
        assertEquals("“repeat”", wordAt(timed, 0.9))
        assertEquals("to", wordAt(timed, 1.75))
        assertEquals("again.", wordAt(timed, 2.75))
        // Past the line's end: still its last word.
        assertEquals("again.", wordAt(timed, 9.0))
        // Everything up to the end of the word being said counts as said.
        assertEquals(0 to "Say “repeat”".length, HelpHighlight.at(listOf(timed), 0.95))
    }

    @Test
    fun withoutWordTimesTheLinesTimeIsSpreadOverItsCharacters() {
        // As GameController.follow: half the time, half the characters.
        assertEquals(0 to untimed.text.length / 2, HelpHighlight.at(listOf(untimed), 1.0))
        assertEquals(0 to 0, HelpHighlight.at(listOf(untimed), 0.0))
        assertEquals(0 to untimed.text.length, HelpHighlight.at(listOf(untimed), 5.0))
    }

    @Test
    fun beforeTheFirstLineNothingIsMarked() {
        assertNull(HelpHighlight.at(listOf(timed), 0.2))
        assertNull(HelpHighlight.at(emptyList(), 1.0))
    }

    @Test
    fun aClipOfTwoLinesIsOneParagraph() {
        val first = Line(at = 0.0, len = 1.0, who = "HOST", text = "One two.")
        val second = Line(at = 1.0, len = 1.0, who = "HOST", text = "Three four.", words = listOf(0.0, 0.5))
        val page = page(listOf("One two. Three four."), listOf(0), listOf(play(first, second)))
        assertEquals(1 to "Three".length, HelpHighlight.at(listOf(first, second), 1.1))
        val h = HelpHighlight.of(page, clip = 0, seconds = 1.6)!!
        assertEquals(0, h.paragraph)
        assertEquals("four.", currentWord(page.text[0], h.chars).word)
    }

    @Test
    fun onAPageItsTheParagraphTheClipReads() {
        // Paragraph 0, an earcon (no paragraph), then paragraph 1.
        val page = page(
            listOf("When it opens, you hear this:", said),
            listOf(0, -1, 1),
            listOf(
                play(Line(0.0, 2.0, "HOST", "When it opens, you hear this:")),
                Step.Pause(0.2),
                Step.Play("earcons/listen-start-demo", 0.145, emptyList(), sfx = true),
                Step.Pause(0.6),
                play(timed),
            ),
        )
        assertEquals(0, HelpHighlight.of(page, clip = 0, seconds = 1.0)!!.paragraph)
        // The earcon has no words: nothing new to mark.
        assertNull(HelpHighlight.of(page, clip = 1, seconds = 0.1))
        val h = HelpHighlight.of(page, clip = 2, seconds = 1.75)!!
        assertEquals(1, h.paragraph)
        assertEquals("to", currentWord(said, h.chars).word)
        // A clip the page doesn't have.
        assertNull(HelpHighlight.of(page, clip = 7, seconds = 0.0))
    }

    @Test
    fun theRealWelcomeIsMarkedWordByWord() {
        val folder = File(System.getProperty("content.dir") ?: "../../content", "app")
        val welcome = AppManifest.parse(File(folder, "app.json").readText()).welcome!!
        val first = welcome.clipLines.first().single()
        val times = first.words!!
        val words = first.text.split(" ")
        // Just after each word starts, that word is the one marked, and the marks only go forward.
        var last = -1
        times.forEachIndexed { k, start ->
            // (A word said too quickly to be marked on its own is passed over.)
            if (k + 1 < times.size && times[k + 1] <= start + 0.01) return@forEachIndexed
            val h = HelpHighlight.of(welcome, clip = 0, seconds = first.at + start + 0.01)!!
            assertEquals(welcome.clipParagraph[0], h.paragraph)
            assertEquals(words[k], currentWord(welcome.text[h.paragraph], h.chars).word)
            assertTrue(h.chars > last)
            last = h.chars
        }
    }

    private fun wordAt(line: Line, seconds: Double): String {
        val (i, chars) = HelpHighlight.at(listOf(line), seconds)!!
        assertEquals(0, i)
        return currentWord(line.text, chars).word
    }

    private fun play(vararg lines: Line) = Step.Play("tts/clip", lines.sumOf { it.len }, lines.toList())

    private fun page(text: List<String>, clipParagraph: List<Int>, steps: List<Step>) =
        HelpPage("test", "Test", "", text, clipParagraph, steps, emptyList())
}
