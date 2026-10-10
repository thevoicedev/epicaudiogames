package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * How the mic opens (docs/DESIGN.md › Sounds, haptics and the microphone): a Bluetooth headset's call link first, then
 * the listening sound (over the link when it's held), then the recogniser, once the sound is over, so it never hears
 * it. A stop at any step leaves nothing to come, and cuts the sound short. iOS: GameControllerTests' cue cases.
 */
class ListenSequenceTest {
    private val log = mutableListOf<String>()
    /** A Bluetooth headset is connected; its call link is up. */
    private var headset = false
    private var linked = false
    /** The route waiting for the headset's link to come up. */
    private var linkComes: (() -> Unit)? = null
    /** The sound playing: done, as the player has heard it out. */
    private var soundOver: (() -> Unit)? = null
    /** No sound to play (the listening sounds off): done at once. */
    private var silent = false

    private val sequence = ListenSequence(
        route = { then ->
            when {
                !headset -> then()
                linked -> then()
                else -> {
                    log += "waiting for the link"
                    linkComes = {
                        linked = true
                        then()
                    }
                }
            }
        },
        callLink = { linked },
        cue = { callLink, done ->
            if (silent) {
                done()
                ({ log += "nothing to cut" })
            } else {
                log += if (callLink) "sound over the call link" else "sound"
                soundOver = done
                ({ log += "sound cut" })
            }
        },
        recognise = { id -> log += "recogniser $id" },
    )

    @Test
    fun withoutAHeadsetTheSoundPlaysThenTheRecogniserStarts() {
        val id = sequence.start()
        assertEquals(listOf("sound"), log)
        // The recogniser waits for the sound to be over.
        soundOver!!()
        assertEquals(listOf("sound", "recogniser $id"), log)
        assertTrue(sequence.isCurrent(id))
    }

    @Test
    fun withAHeadsetTheSoundWaitsForTheLinkAndGoesOverIt() {
        headset = true
        val id = sequence.start()
        assertEquals(listOf("waiting for the link"), log)
        linkComes!!()
        assertEquals(listOf("waiting for the link", "sound over the call link"), log)
        soundOver!!()
        assertEquals(listOf("waiting for the link", "sound over the call link", "recogniser $id"), log)
    }

    @Test
    fun stoppedWhileWaitingForTheLinkNothingMoreHappens() {
        headset = true
        sequence.start()
        sequence.stop()
        linkComes!!()
        assertEquals(listOf("waiting for the link"), log)
    }

    @Test
    fun stoppedDuringTheSoundItsCutShortAndTheRecogniserDoesntStart() {
        val id = sequence.start()
        sequence.stop()
        assertEquals(listOf("sound", "sound cut"), log)
        assertFalse(sequence.isCurrent(id))
        // The sound's end, should it still come, starts nothing.
        soundOver!!()
        assertEquals(listOf("sound", "sound cut"), log)
    }

    @Test
    fun theSameListenAgainHasNoSound() {
        val first = sequence.start()
        soundOver!!()
        // The recogniser started again (online after offline, or more time to answer): at once, no second sound.
        val again = sequence.start(withCue = false)
        assertEquals(listOf("sound", "recogniser $first", "recogniser $again"), log)
        assertFalse(sequence.isCurrent(first))
        assertTrue(sequence.isCurrent(again))
    }

    @Test
    fun theSameListenAgainKeepsTheHeadsetsLink() {
        headset = true
        linked = true
        val id = sequence.start(withCue = false)
        assertEquals(listOf("recogniser $id"), log)
    }

    @Test
    fun aNewListenCutsTheLastOnesSound() {
        val first = sequence.start()
        val firstOver = soundOver!!
        val second = sequence.start()
        assertEquals(listOf("sound", "sound cut", "sound"), log)
        firstOver()
        assertEquals(listOf("sound", "sound cut", "sound"), log)
        soundOver!!()
        assertEquals(listOf("sound", "sound cut", "sound", "recogniser $second"), log)
        assertFalse(sequence.isCurrent(first))
    }

    @Test
    fun aSoundReportedOverTwiceStartsTheRecogniserOnce() {
        // The track's last-frame marker and its watchdog can both come.
        val id = sequence.start()
        soundOver!!()
        soundOver!!()
        assertEquals(listOf("sound", "recogniser $id"), log)
    }

    @Test
    fun withTheSoundsOffTheRecogniserStartsAtOnceAndThereIsNothingToCut() {
        silent = true
        val id = sequence.start()
        assertEquals(listOf("recogniser $id"), log)
        sequence.stop()
        assertEquals(listOf("recogniser $id"), log)
    }

    @Test
    fun aStopWithNothingPlayingCutsNothing() {
        sequence.stop()
        val id = sequence.start()
        soundOver!!()
        sequence.stop()
        assertEquals(listOf("sound", "recogniser $id"), log)
    }
}
