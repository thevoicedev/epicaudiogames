package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What TalkBack reads for each transcript entry, as one element (docs/DESIGN.md › Game › Transcript), in the app's
 * words (res/values/strings.xml).
 */
class FeedItemTest {
    @Test
    fun aLineIsReadWithItsSpeakerFirst() {
        assertEquals("Gribbo: Who goes there?", FeedItem.Spoken("GRIBBO", "Gribbo", "Who goes there?").readAs(TestWords))
    }

    @Test
    fun theNarratorsLinesAreReadAsTheyAre() {
        assertEquals("Night falls.", FeedItem.Spoken("NARRATOR", "Narrator", "Night falls.").readAs(TestWords))
        assertEquals("Night falls.", FeedItem.Spoken("NARRATOR", "", "Night falls.").readAs(TestWords))
    }

    @Test
    fun aLineWithNoNameIsReadAsItIs() {
        assertEquals("Welcome to the show!", FeedItem.Spoken("HOST", "", "Welcome to the show!").readAs(TestWords))
        assertEquals("Welcome to the show!", FeedItem.Spoken("HOST", "  ", "Welcome to the show!").readAs(TestWords))
    }

    @Test
    fun aReplyIsWhatYouSaid() {
        assertEquals("You said: yes please", FeedItem.Reply("yes please").readAs(TestWords))
    }

    @Test
    fun aNoteIsReadAsItIs() {
        assertEquals("Welcome back!", FeedItem.Note(R.string.note_welcome_back).readAs(TestWords))
    }
}
