package com.epicaudiogames.app

import com.epicaudiogames.wearlink.WearAction
import com.epicaudiogames.wearlink.WearCommand
import com.epicaudiogames.wearlink.WearLink
import com.epicaudiogames.wearlink.WearState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The Wear OS app's link on the phone (WearBridge.kt): what the watch is told as a game goes (docs/DESIGN.md › Watches,
 * in the words of res/values/strings.xml), when it's told, and what its two buttons do; and that the phone's manifest
 * and resources name what the watch app looks for (WearLink.kt). iOS: WatchBridgeTests.swift.
 */
class WearBridgeTest {
    /** A game as the watch sees it, set by the test. */
    private class Game(
        override var action: CircleAction? = CircleAction.SKIP,
        override var listening: Boolean = false,
        override var paused: Boolean = false,
        override var endKind: String? = null,
    ) : WearGame {
        override val id = "noodle-rush"
        override val title = "Noodle Rush"
        val pressed = mutableListOf<String>()

        override fun circle() {
            pressed += "circle"
        }

        override fun pause() {
            pressed += "pause"
        }
    }

    /** The watch's end of the link, as a test's: what it was told, in order. */
    private class Link : WearLinking {
        override var onReady: () -> Unit = {}
        val told = mutableListOf<WearState>()
        var started = 0

        override fun start() {
            started++
        }

        override fun tell(state: WearState) {
            told += state
        }
    }

    private fun state(game: WearGame?) = wearState(TestWords, game)

    /** A bridge to [link] for [game], logging nowhere (the JVM has no Android log). */
    private fun bridge(link: WearLinking = Link(), game: () -> WearGame?) =
        WearBridge(link, TestWords, log = {}, game = game)

    @Test
    fun eachOfTheCirclesActionsAsTheWatchShowsIt() {
        data class Row(val state: String, val action: WearAction, val label: String, val enabled: Boolean)
        val table = mapOf(
            CircleAction.CARRY_ON to Row("Paused", WearAction.CARRY_ON, "Carry on", true),
            CircleAction.SKIP to Row("Speaking", WearAction.SKIP, "Skip", true),
            // As the status line says it, not the circle's "Listening".
            CircleAction.STOP_LISTENING to Row("Listening…", WearAction.STOP_LISTENING, "Stop listening", true),
            CircleAction.TALK to Row("Your turn", WearAction.TALK, "Talk", true),
            // Only the phone can ask for the microphone: dimmed, named as on the phone, which says why.
            CircleAction.MIC_REFUSED to Row("Your turn", WearAction.MIC_REFUSED, "Talk (the microphone is off)", false),
            // A press tries the recogniser again, as a tap on the circle does.
            CircleAction.NO_RECOGNITION to
                Row("Your turn", WearAction.NO_RECOGNITION, "Talk (speech recognition isn't available)", true),
            CircleAction.WAIT to Row("Wait for the question", WearAction.WAIT, "Talk", false),
        )
        assertEquals(CircleAction.entries.toSet(), table.keys)
        for ((action, row) in table) {
            val s = state(Game(action = action, paused = action == CircleAction.CARRY_ON))
            assertEquals("$action", "Noodle Rush", s.title)
            assertEquals("$action", row, Row(s.state, checkNotNull(s.action), s.label, s.enabled))
        }
    }

    @Test
    fun actionsGoUnderTheirOwnNames() {
        for (action in CircleAction.entries) assertEquals(action.name, wearAction(action).name)
    }

    @Test
    fun listeningAndPauseFollowTheGame() {
        val listening = state(Game(action = CircleAction.STOP_LISTENING, listening = true))
        assertTrue(listening.listening)
        assertTrue(listening.canPause)
        val paused = state(Game(action = CircleAction.CARRY_ON, paused = true))
        assertFalse(paused.listening)
        assertFalse("nothing to pause over a pause", paused.canPause)
    }

    @Test
    fun atAnEndItsHeadingAndNoButton() {
        val headings = mapOf("chapter" to "Chapter complete", "gameover" to "Game over", "ending" to "The end")
        for ((kind, heading) in headings) {
            for (paused in listOf(false, true)) {
                val game = Game(action = if (paused) CircleAction.CARRY_ON else null, paused = paused, endKind = kind)
                assertEquals(
                    "$kind, paused $paused",
                    WearState(
                        title = "Noodle Rush", state = heading, action = null, label = "", enabled = false,
                        listening = false, canPause = false,
                    ),
                    state(game),
                )
            }
        }
    }

    @Test
    fun noGameIsNoState() {
        assertEquals(WearState.NONE, state(null))
    }

    @Test
    fun startingTellsTheWatchAndFollowsTheGame() {
        val link = Link()
        val game = Game()
        val wear = bridge(link) { game }
        val scope = CoroutineScope(Dispatchers.Unconfined)
        try {
            wear.start(scope)
            assertEquals(1, link.started)
            assertSame(wear, WearBridge.current)
            // Told once as it starts; the state followed from there is the same, so it isn't told again.
            assertEquals(listOf(state(game)), link.told)
            // The link found the watch: told again, changed or not.
            link.onReady()
            assertEquals(listOf(state(game), state(game)), link.told)
        } finally {
            scope.cancel()
            wear.stop()
        }
        assertNull(WearBridge.current)
        assertEquals("the model gone: no game", WearState.NONE, link.told.last())
    }

    @Test
    fun aChangeIsToldOnceAndNoChangeNotAtAll() {
        val link = Link()
        val game = Game(action = CircleAction.TALK)
        val wear = bridge(link) { game }
        wear.tell()
        wear.tell()
        assertEquals(1, link.told.size)
        game.action = CircleAction.STOP_LISTENING
        game.listening = true
        wear.tell()
        wear.tell()
        assertEquals(listOf("Your turn", "Listening…"), link.told.map { it.state })
        wear.tell(again = true)
        assertEquals(3, link.told.size)
    }

    @Test
    fun theBigButtonIsTheHeadphonesButton() {
        for (action in CircleAction.entries) {
            val game = Game(action = action)
            bridge { game }.perform(WearCommand.PRIMARY)
            assertEquals("$action", listOf("circle"), game.pressed)
        }
    }

    @Test
    fun theBigButtonDoesNothingAtAnEnd() {
        val game = Game(action = null, endKind = "chapter")
        bridge { game }.perform(WearCommand.PRIMARY)
        assertEquals(emptyList<String>(), game.pressed)
    }

    @Test
    fun pausePausesUnlessPausedOrAtAnEnd() {
        val playing = Game()
        bridge { playing }.perform(WearCommand.PAUSE)
        assertEquals(listOf("pause"), playing.pressed)
        val paused = Game(action = CircleAction.CARRY_ON, paused = true)
        bridge { paused }.perform(WearCommand.PAUSE)
        assertEquals(emptyList<String>(), paused.pressed)
        val ended = Game(action = null, endKind = "gameover")
        bridge { ended }.perform(WearCommand.PAUSE)
        assertEquals(emptyList<String>(), ended.pressed)
    }

    @Test
    fun withoutAGameTheButtonsDoNothing() {
        val link = Link()
        val wear = bridge(link) { null }
        for (command in WearCommand.entries) wear.perform(command)
        assertEquals(emptyList<WearState>(), link.told)
    }

    @Test
    fun theManifestTakesTheWatchsButtonsWhereTheWatchSendsThem() {
        val manifest = xml("src/main/AndroidManifest.xml")
        val services = manifest.getElementsByTagName("service")
        val commands = (0 until services.length).map { services.item(it) as Element }
            .single { it.getAttribute("android:name") == ".WearCommands" }
        assertEquals("true", commands.getAttribute("android:exported"))
        val action = commands.getElementsByTagName("action").item(0) as Element
        assertEquals("com.google.android.gms.wearable.MESSAGE_RECEIVED", action.getAttribute("android:name"))
        val data = commands.getElementsByTagName("data").item(0) as Element
        assertEquals("wear", data.getAttribute("android:scheme"))
        assertEquals("*", data.getAttribute("android:host"))
        assertEquals(WearLink.COMMAND_PATH, data.getAttribute("android:path"))
    }

    @Test
    fun thePhoneSaysItHasTheCapabilityTheWatchLooksFor() {
        val items = xml("src/main/res/values/wear.xml").getElementsByTagName("item")
        val capabilities = (0 until items.length).map { items.item(it).textContent.trim() }
        assertEquals(listOf(WearLink.PHONE_CAPABILITY), capabilities)
    }

    /** An XML file of the app's (the tests run in android/app). */
    private fun xml(path: String) =
        DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(path)).documentElement
}
