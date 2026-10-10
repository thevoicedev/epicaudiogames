package com.epicaudiogames.app.ui

import android.Manifest
import android.os.SystemClock
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.core.app.ActivityCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.GameController
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.Permissions
import com.epicaudiogames.app.Saves
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Session
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The game screen as TalkBack meets it (docs/DESIGN.md › Game): the talking circle's name and state and where its tap
 * goes, the mic opening by itself only when it should, the transcript's lines as one element each, and the pause and
 * the end panel (panes whose headings take the focus, and their buttons' test tags); asking, paused and at its end in
 * every look (on a tablet, in two panes). A small game with no audio, so each turn's lines show at once; the test sets
 * the mic as it needs, and nothing asks the phone for it.
 */
@RunWith(AndroidJUnit4::class)
open class GameScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private lateinit var saves: Saves
    private lateinit var game: GameController
    @Volatile private var left = false

    @Before
    fun setUp() {
        // Android's accessibility checks (contrast, touch targets, names) on every screen an action leaves behind.
        compose.enableEpicChecks()
        // The system's permission dialogs would cover the screen: the mic and notifications count as asked.
        Permissions.micAsked = true
        Permissions.notificationsAsked = true
        saves = Saves(compose.activity)
        saves.clear(ID)
    }

    @After
    fun tearDown() {
        if (::game.isInitialized) compose.runOnUiThread { game.close() }
        saves.clear(ID)
    }

    @Test
    fun theCircleSaysWhatATapDoesAndTheGamesState() {
        show()
        // No question yet: nothing to do.
        circle().assert(named("Talk", "Wait for the question")).assertIsNotEnabled()
        open(micAllowed = false)
        circle().assert(named("Talk (the microphone is off)", "Your turn")).assertIsEnabled().assertHasClickAction()
        // The mic button is named the same way.
        compose.onAllNodesWithContentDescription("Talk (the microphone is off)").assertCountEquals(2)
        compose.runOnIdle {
            game.micAllowed = true
            game.micWorks = false
        }
        circle().assert(named("Talk (speech recognition isn't available)", "Your turn"))
        compose.onAllNodesWithContentDescription("Talk (speech recognition isn't available)").assertCountEquals(2)
        compose.runOnIdle { game.micWorks = true }
        circle().assert(named("Talk", "Your turn"))
    }

    @Test
    fun withTheMicRefusedTheCirclesTapLeadsToTheMic() {
        // Android asks again with its own dialog after a first refusal, which a test can't answer; otherwise (never
        // asked, refused for good, or allowed) the tap leads to the phone's settings, as the mic button's does.
        assumeFalse(ActivityCompat.shouldShowRequestPermissionRationale(compose.activity, Manifest.permission.RECORD_AUDIO))
        show()
        open(micAllowed = false)
        circle().performClick()
        compose.onNodeWithText("The microphone is off").assertExists()
    }

    @Test
    fun refusedForGoodTheFirstTapStillLeadsToTheMic() {
        // Refused for good in an earlier run of the app, which doesn't know it asked (Permissions.micAsked): Android
        // answers the ask at once, with no dialog, and the tap still leads to the phone's settings, not to nothing.
        assumeFalse(Permissions.micGranted(compose.activity))
        val fixed = "${compose.activity.packageName} ${Manifest.permission.RECORD_AUDIO} user-set user-fixed"
        shell("pm set-permission-flags $fixed")
        try {
            Permissions.micAsked = false
            show()
            open(micAllowed = false)
            circle().performClick()
            compose.waitUntil(10_000) {
                compose.onAllNodesWithText("The microphone is off").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("mic-off-settings").assertHasClickAction()
        } finally {
            shell("pm clear-permission-flags $fixed")
            Permissions.micAsked = true
        }
    }

    @Test
    fun underTalkBacksFocusTheOneButtonKeepsTheWordsItRead() {
        // TalkBack says again whatever changes in what its focus is on. The one button's name and state, the mic
        // button's and the line under the circle follow the game, so with TalkBack's focus on one of them it stays as
        // TalkBack read it (no "Listening" as the mic opens, which the recogniser would hear), and it's the game's
        // again once the focus moves on (ScreenReaderFocus.kt). Without a screen reader nothing is held.
        val focus = ScreenReaderFocus()
        var reader by mutableStateOf(true)
        make(listensByItself = false)
        compose.setContent {
            CompositionLocalProvider(LocalScreenReaderFocus provides focus) {
                EpicTheme { GameScreen(game, screenReader = reader, onStore = {}) }
            }
        }
        compose.waitForIdle()
        open(micAllowed = true)
        val talk = "Your turn! Tap the mic to talk"
        val none = "Talk (speech recognition isn't available)"
        circle().assert(named("Talk", "Your turn"))
        compose.onNodeWithTag(MIC_TAG).assert(described("Talk"))
        compose.onNodeWithTag(STATUS_TAG).assert(hasText(talk))
        for (tag in listOf(CIRCLE_TAG, MIC_TAG, STATUS_TAG)) {
            compose.runOnIdle {
                focus.tag = tag
                game.micWorks = false
            }
            circle().assert(if (tag == CIRCLE_TAG) named("Talk", "Your turn") else named(none, "Your turn"))
            compose.onNodeWithTag(MIC_TAG).assert(described(if (tag == MIC_TAG) "Talk" else none))
            compose.onNodeWithTag(STATUS_TAG).assert(hasText(if (tag == STATUS_TAG) talk else "Your turn!"))
            // The focus moves on: the game's, for when it comes back.
            compose.runOnIdle { focus.tag = null }
            circle().assert(named(none, "Your turn"))
            compose.onNodeWithTag(MIC_TAG).assert(described(none))
            compose.onNodeWithTag(STATUS_TAG).assert(hasText("Your turn!"))
            compose.runOnIdle { game.micWorks = true }
            circle().assert(named("Talk", "Your turn"))
        }
        compose.runOnIdle {
            reader = false
            focus.tag = CIRCLE_TAG
            game.micWorks = false
        }
        circle().assert(named(none, "Your turn"))
    }

    @Test
    fun pausedTheKeyboardsFocusStaysOnThePause() {
        // Under the opaque pause a keyboard's focus couldn't be seen, and a key pressed there would do what the pause
        // holds back (the mic would listen, Back would leave): Tab and Shift+Tab go round the pause's own. The keys
        // come as a keyboard's do, through the window.
        show()
        open(micAllowed = false)
        compose.runOnIdle { game.pause() }
        focusMovesTo(isHeading() and hasText("Paused"))
        val onThePause = isFocused() and hasAnyAncestor(paneTitled("Paused"))
        val visited = mutableSetOf<String>()
        for (back in listOf(false, true)) {
            repeat(6) {
                tab(back)
                val node = compose.onNode(onThePause).fetchSemanticsNode()
                node.config.getOrNull(SemanticsProperties.TestTag)?.let { visited += it }
            }
        }
        assertEquals(setOf("paused-carry-on", "paused-help", "paused-leave"), visited)
        compose.runOnIdle {
            assertTrue(game.paused)
            assertFalse(left)
        }
    }

    @Test
    fun itOpensTheMicByItselfOnlyWhenItShould() {
        show(listensByItself = false)
        open(micAllowed = true)
        // A question asked, the mic allowed and working: as with TalkBack on, it waits for the player to open it.
        compose.runOnIdle { assertFalse(game.listening) }
        circle().assert(named("Talk", "Your turn"))
        compose.runOnIdle {
            // The mic allowed again (back from the phone's settings): still not by itself.
            game.allowMic()
            assertFalse(game.listening)
            // Allowed after a tap on the mic button or the circle: it listens, as the tap would have.
            game.allowMic(listen = true)
            assertTrue(game.listening)
        }
    }

    @Test
    fun eachLineIsOneElementReadWithItsSpeaker() {
        show()
        open(micAllowed = false)
        // Pip's two lines join (the first ends with a comma): one element, the speaker first, its words not read twice.
        compose.onNodeWithContentDescription("Pip: Hello there, do you want cake?").assertExists()
        compose.onAllNodesWithText("Hello there, do you want cake?").assertCountEquals(0)
        answer("Yes please, cake")
        compose.onNodeWithContentDescription("You said: Yes please, cake").assertExists()
        // The narrator's lines are read as they are.
        compose.onNodeWithContentDescription("Cake for everyone.").assertExists()
    }

    @Test
    fun pausedItsAPaneWhoseHeadingTakesTheFocus() {
        show()
        open(micAllowed = false)
        compose.runOnIdle { game.pause() }
        compose.onNode(paneTitled("Paused")).assertExists()
        focusMovesTo(isHeading() and hasText("Paused"))
        compose.onNodeWithTag("paused-carry-on").assert(hasText("Carry on")).assertHasClickAction()
        compose.onNodeWithTag("paused-help").assert(hasText("How to play")).assertHasClickAction()
        compose.onNodeWithTag("paused-leave").assert(hasText("Leave game")).assertHasClickAction()
        compose.onNodeWithTag("paused-carry-on").performClick()
        compose.runOnIdle { assertFalse(game.paused) }
        compose.onNode(paneTitled("Paused")).assertDoesNotExist()
    }

    @Test
    fun leaveGameLeavesWithItsPlaceKept() {
        show()
        open(micAllowed = false)
        compose.runOnIdle { game.pause() }
        compose.onNodeWithTag("paused-leave").performClick()
        compose.waitForIdle()
        assertTrue(left)
        assertEquals("q1", saves.load(ID)?.node)
        assertFalse(saves.load(ID)!!.ended)
    }

    @Test
    fun theEndIsAPaneWhoseHeadingTakesTheFocus() {
        show()
        open(micAllowed = false)
        answer("Yes please, cake")
        compose.onNode(paneTitled("Chapter complete")).assertExists()
        compose.onNodeWithTag("end-heading").assert(isHeading()).assert(hasText("Chapter complete"))
        focusMovesTo(isHeading() and hasText("Chapter complete"))
        compose.onNodeWithTag("end-next").assert(hasText("Next chapter")).assertHasClickAction()
        compose.onNodeWithTag("end-again").assert(hasText("Play again")).assertHasClickAction()
        compose.onNodeWithTag("end-back").assert(hasText("Back to games")).assertHasClickAction()
        compose.onNodeWithTag("end-get").assertDoesNotExist()       // no pack to get in this game
        // At an end the circle is just a picture: no name, and nothing to tap.
        circle()
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsActions.OnClick))
    }

    @Test
    fun atTwiceTheTextSizeTheAnswerButtonsKeepTheirWordsWhole() {
        // The compact layout: Send and the mic show their words; the mic's longer names get a row of their own.
        make(listensByItself = false)
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) {
                EpicTheme { GameScreen(game, screenReader = false, onStore = {}) }
            }
        }
        compose.waitForIdle()
        open(micAllowed = false)
        compose.onNodeWithText("Send", useUnmergedTree = true).assertWordsWhole()
        compose.onNodeWithText("Talk (the microphone is off)", useUnmergedTree = true).assertWordsWhole()
        compose.runOnIdle {
            game.micAllowed = true
            game.micWorks = false
        }
        compose.onNodeWithText("Talk (speech recognition isn't available)", useUnmergedTree = true).assertWordsWhole()
    }

    @Test
    fun askingPausedAndAtItsEndInEveryLook() {
        make(listensByItself = false)
        val looks = Looks(compose)
        looks.show { GameScreen(game, screenReader = false, onStore = {}) }
        open(micAllowed = false)
        // Its question asked: the circle, the transcript with the options at its end, and the answer bar.
        looks.each { look -> compose.checkAll("the game asking, $look") }
        // Paused: the overlay alone.
        compose.runOnIdle { game.pause() }
        looks.each { look -> compose.checkAll("the game paused, $look") }
        compose.runOnIdle { game.carryOn() }
        answer("Yes please, cake")
        // A chapter's end: the end panel in the answer bar's place.
        compose.onNodeWithTag("end-heading").assertExists()
        looks.each { look -> compose.checkAll("the game at a chapter's end, $look") }
    }

    /** The game on screen, not opened yet. It opens the mic by itself only if [listensByItself]. */
    private fun show(listensByItself: Boolean = true) {
        make(listensByItself)
        compose.setContent { EpicTheme { GameScreen(game, screenReader = false, onStore = {}) } }
        compose.waitForIdle()
    }

    /** The game, not on screen yet. */
    private fun make(listensByItself: Boolean) {
        compose.runOnUiThread {
            game = GameController(
                compose.activity.applicationContext, GameInfo(ID, "Cake", "", "", emptyList()),
                Session(GameMap.parse(MAP)), saves, emptyList(), onLeave = { left = true },
                listensByItself = { listensByItself },
            )
        }
    }

    /**
     * Opens the game with the mic as given (after the screen has read the phone's): its first turn has no audio, so it
     * shows its lines and asks at once.
     */
    private fun open(micAllowed: Boolean, micWorks: Boolean = true) {
        compose.runOnIdle {
            game.micAllowed = micAllowed
            game.micWorks = micWorks
            game.open()
        }
        compose.waitForIdle()
    }

    /** Taps an option, once a double tap's moment after the question has passed (GameController.tap). */
    private fun answer(option: String) {
        Thread.sleep(600)
        compose.onNodeWithText(option).performClick()
        compose.waitForIdle()
    }

    /** Tab ([back]: Shift+Tab) pressed on a keyboard: the key goes to the window, as a keyboard's does. */
    private fun tab(back: Boolean) {
        val meta = if (back) KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON else 0
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            val now = SystemClock.uptimeMillis()
            instrumentation.sendKeySync(KeyEvent(now, now, action, KeyEvent.KEYCODE_TAB, 0, meta))
        }
        compose.waitForIdle()
    }

    /** The focus (and with it TalkBack's) moves to what [matcher] finds, a moment after it appears. */
    private fun focusMovesTo(matcher: SemanticsMatcher) {
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) { compose.onAllNodes(matcher and isFocused()).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun circle() = compose.onNodeWithTag("talking-circle")

    /** What TalkBack says for a button: its name, then its state ("Talk", "Your turn"). */
    private fun named(name: String, state: String) =
        SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(name)) and
            SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, state) and
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)

    private fun paneTitled(title: String) = SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, title)

    /** What TalkBack calls a button with no state: that name. */
    private fun described(name: String) =
        SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(name))

    private companion object {
        const val ID = "test-cake"

        /** A question whose two lines join (a comma), with options; a chapter end, a second chapter, a game over. */
        val MAP = """
            {
             "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
             "vars": { "score": 0 },
             "who": { "NARRATOR": "Narrator", "PIP": "Pip" },
             "words": { "yes": ["=yes"], "no": ["=no"], "repeat": ["say that again"] },
             "nodes": {
              "q1": {
               "say": [ { "play": "scenes/q1", "dur": 4, "lines": [
                 { "at": 0, "len": 2, "who": "PIP", "text": "Hello there," },
                 { "at": 2, "len": 2, "who": "PIP", "text": "do you want cake?" } ] } ],
               "ask": {
                "reprompt": [ { "play": "prompts/q1", "dur": 1, "lines": [
                  { "at": 0, "len": 1, "who": "NARRATOR", "text": "Cake? Say yes or no." } ] } ],
                "answers": [ { "yes": true, "go": "c1end" }, { "no": true, "go": "over" } ],
                "else": "c1end",
                "buttons": [ { "label": "Yes please, cake", "value": "yes" }, { "label": "No", "value": "no" } ]
               }
              },
              "c1end": {
               "say": [ { "play": "scenes/c1end", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "NARRATOR", "text": "Cake for everyone." } ] } ],
               "end": { "kind": "chapter", "title": "Chapter One", "next": "c2" }
              },
              "c2": {
               "say": [ { "play": "scenes/c2", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "PIP", "text": "More cake?" } ] } ],
               "ask": {
                "reprompt": [ { "play": "prompts/c2", "dur": 1, "lines": [
                  { "at": 0, "len": 1, "who": "PIP", "text": "More? Yes or no." } ] } ],
                "answers": [ { "yes": true, "go": "over" } ],
                "else": "over",
                "buttons": [ { "label": "Yes", "value": "yes" } ]
               }
              },
              "over": {
               "say": [ { "play": "scenes/over", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "NARRATOR", "text": "Too much cake." } ] } ],
               "end": { "kind": "gameover", "title": "Oh no", "retry": "q1" }
              }
             }
            }
        """.trimIndent()
    }
}

/** The game on a tablet turned sideways: two panes, its transcript beside the rest. */
class GameScreenTabletTest : GameScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
