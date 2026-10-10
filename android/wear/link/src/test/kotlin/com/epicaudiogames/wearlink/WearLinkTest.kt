package com.epicaudiogames.wearlink

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What goes between the phone and the watch (WearLink.kt): the state both ways, as plain values; the actions' and
 * commands' names; and the watch's inbox, newest first, with its buzzes. iOS: WatchLinkTests.swift.
 */
class WearLinkTest {
    private val listening = WearState(
        title = "Noodle Rush", state = "Listening…", action = WearAction.STOP_LISTENING, label = "Stop listening",
        enabled = true, listening = true, canPause = true,
    )
    private val turn = listening.copy(state = "Your turn", action = WearAction.TALK, label = "Talk", listening = false)

    @Test
    fun aStateGoesAndComesBackAsItWas() {
        for (state in listOf(listening, turn, WearState.NONE, turn.copy(action = null, label = "", enabled = false))) {
            assertEquals(Stamped(state, 1_700_000_000_123L), WearState.from(state.toMap(at = 1_700_000_000_123L)))
        }
    }

    @Test
    fun itTravelsAsPlainValuesUnderIosNames() {
        val map = listening.toMap(at = 42L)
        assertEquals(
            mapOf(
                "title" to "Noodle Rush", "state" to "Listening…", "action" to "stopListening",
                "label" to "Stop listening", "enabled" to true, "listening" to true, "canPause" to true, "at" to 42L,
            ),
            map,
        )
        // No action: an empty name, as iOS sends it.
        assertEquals("", WearState.NONE.toMap(at = 1L)["action"])
    }

    @Test
    fun anythingElseIsNoState() {
        val map = listening.toMap(at = 42L)
        assertNull(WearState.from(emptyMap()))
        for (key in map.keys) assertNull(key, WearState.from(map - key))
        assertNull(WearState.from(map + ("enabled" to "yes")))
        assertNull(WearState.from(map + ("at" to 42)))           // an Int, not the Long the phone puts
        assertNull(WearState.from(map + ("title" to null)))
    }

    @Test
    fun anActionThisWatchDoesntKnowStillShowsItsButton() {
        val state = checkNotNull(WearState.from(listening.toMap(at = 1L) + ("action" to "somethingNew"))).state
        assertNull(state.action)
        assertEquals("Stop listening", state.label)
        assertTrue(state.enabled)
    }

    @Test
    fun actionsHaveTheIphonesNames() {
        // ios/EpicEngine/Sources/EpicAppCore/WatchLink.swift's WatchAction raw values, in its order.
        assertEquals(
            listOf("carryOn", "skip", "stopListening", "talk", "micRefused", "noRecognition", "wait"),
            WearAction.entries.map { it.key },
        )
        for (action in WearAction.entries) assertEquals(action, WearAction.of(action.key))
        assertNull(WearAction.of(""))
    }

    @Test
    fun commandsGoAsTheirNamesToTheCommandPath() {
        assertArrayEquals("primary".encodeToByteArray(), WearCommand.PRIMARY.payload)
        assertArrayEquals("pause".encodeToByteArray(), WearCommand.PAUSE.payload)
        for (command in WearCommand.entries) {
            assertEquals(command, WearCommand.from(WearLink.COMMAND_PATH, command.payload))
            assertNull(WearCommand.from(WearLink.STATE_PATH, command.payload))
        }
        assertNull(WearCommand.from(WearLink.COMMAND_PATH, "jump".encodeToByteArray()))
        assertNull(WearCommand.from(WearLink.COMMAND_PATH, null))
        assertNull(WearCommand.from(WearLink.COMMAND_PATH, ByteArray(0)))
    }

    @Test
    fun theFirstStateShowsWithoutABuzz() {
        val inbox = WearInbox()
        assertEquals(WearState.NONE, inbox.state)
        assertNull(inbox.at)
        assertEquals(WearInbox.Taken(shown = true, haptic = null), inbox.take(listening, at = 1_000L))
        assertEquals(listening, inbox.state)
        assertEquals(1_000L, inbox.at)
    }

    @Test
    fun theMicrophoneOpeningAndClosingBuzzDifferently() {
        val inbox = WearInbox()
        inbox.take(turn, at = 1_000L)
        assertEquals(WearHaptic.LISTENING_STARTED, inbox.take(listening, at = 2_000L).haptic)
        // Nothing new about the microphone: no buzz.
        assertNull(inbox.take(listening.copy(state = "Still listening"), at = 2_500L).haptic)
        assertEquals(WearHaptic.LISTENING_STOPPED, inbox.take(turn, at = 3_000L).haptic)
        assertNull(inbox.take(turn.copy(state = "Speaking"), at = 4_000L).haptic)
    }

    @Test
    fun theGameClosingDoesntBuzz() {
        val inbox = WearInbox()
        inbox.take(turn, at = 1_000L)
        inbox.take(listening, at = 2_000L)
        assertEquals(WearInbox.Taken(shown = true, haptic = null), inbox.take(WearState.NONE, at = 3_000L))
        assertFalse(inbox.state.gameOpen)
    }

    @Test
    fun aStateCaughtUpWithShowsWithoutABuzz() {
        val inbox = WearInbox()
        inbox.take(turn, at = 1_000L)
        // Back on the watch's screen, the microphone opened meanwhile: shown, not buzzed.
        val taken = inbox.take(listening, at = 9_000L, catchingUp = true)
        assertEquals(WearInbox.Taken(shown = true, haptic = null), taken)
        assertEquals(listening, inbox.state)
        assertEquals(WearHaptic.LISTENING_STOPPED, inbox.take(turn, at = 10_000L).haptic)
    }

    @Test
    fun anOlderStateReadLateIsLetGo() {
        val inbox = WearInbox()
        inbox.take(listening, at = 10_000L)
        assertEquals(WearInbox.Taken(shown = false, haptic = null), inbox.take(turn, at = 9_000L))
        assertEquals(listening, inbox.state)
        assertEquals(10_000L, inbox.at)
        // The same time again is the same state, or a newer one made in the same millisecond: taken.
        assertTrue(inbox.take(turn, at = 10_000L).shown)
    }

    @Test
    fun thePhonesClockPutBackIsTakenAsNew() {
        val inbox = WearInbox()
        inbox.take(turn, at = 100_000L)
        // More than a minute older: only the phone's clock going back makes that.
        val taken = inbox.take(listening, at = 100_000L - WearInbox.CLOCK_JUMP_MS - 1)
        assertEquals(WearInbox.Taken(shown = true, haptic = WearHaptic.LISTENING_STARTED), taken)
        assertEquals(listening, inbox.state)
    }

    @Test
    fun gameOpenIsHavingATitle() {
        assertTrue(turn.gameOpen)
        assertFalse(WearState.NONE.gameOpen)
    }
}
