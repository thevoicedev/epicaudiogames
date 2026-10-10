package com.epicaudiogames.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Settings › Licences shows the font's licence as headings and paragraphs that reflow at any text size, and the
 * licence asks for itself in full in every copy: every word of the shipped file is shown, in order
 * (content/app/licences/OFL-AtkinsonHyperlegibleNext.txt, as the app has it).
 */
class LicenceTextTest {
    private val text = File("../../content/app/licences/OFL-AtkinsonHyperlegibleNext.txt").readText()
    private val blocks = licenceBlocks(text)

    @Test
    fun theLicencesSectionsAreHeadings() {
        assertEquals(
            listOf(
                "SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007",
                "PREAMBLE", "DEFINITIONS", "PERMISSION & CONDITIONS", "TERMINATION", "DISCLAIMER",
            ),
            blocks.filter { it.heading }.map { it.text },
        )
    }

    @Test
    fun everyWordIsShownInItsOrder() {
        // The rules of dashes are the only thing left out (a dash or two within a line stays).
        val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() && !(it.length >= 3 && it.all { c -> c == '-' }) }
        assertEquals(words, blocks.flatMap { it.text.split(" ") })
    }

    @Test
    fun paragraphsAreJoinedLinesThatReflow() {
        assertTrue(blocks.first().text.startsWith("Copyright 2020-2024 The Atkinson Hyperlegible Next Project Authors"))
        for (block in blocks) {
            assertFalse(block.text, block.text.contains('\n') || block.text.contains("  "))
        }
        // The conditions stay a paragraph each.
        assertTrue(blocks.any { !it.heading && it.text.startsWith("1) Neither the Font Software nor") })
        assertTrue(blocks.any { !it.heading && it.text.startsWith("5) The Font Software, modified or unmodified") })
    }

    @Test
    fun aHeadingStartsWithAWordInCapitalsAndDoesntEndASentence() {
        assertEquals(
            listOf(
                LicenceBlock("TITLE", heading = true),
                LicenceBlock("line one line two", heading = false),
                LicenceBlock("THE END OF IT.", heading = false),
                LicenceBlock("Plain words", heading = false),
            ),
            licenceBlocks("TITLE\nline one\n  line two  \n\n-----\nTHE END OF IT.\n\nPlain words\n"),
        )
    }
}
