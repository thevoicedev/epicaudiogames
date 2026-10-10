package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.epicaudiogames.app.CircleAction
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.isAccessibilityTextSize
import com.epicaudiogames.engine.Button
import com.epicaudiogames.engine.End
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The game's parts as TalkBack meets them, each on its own state (docs/DESIGN.md › Game): the talking circle in every
 * state (its name and state from CircleAction, the line under it, and at an end only a picture), the question's
 * options (a heading "Options" over a group of buttons, each named by its words), each kind of end (a pane named by
 * its heading, which takes the focus, and the buttons for what's next), and the pause. Each in every look, the
 * compact layout at twice the text size (as the game screen has it). GameScreenTest plays a whole game.
 */
@RunWith(AndroidJUnit4::class)
open class GameComponentsTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val looks by lazy { Looks(compose) }
    private val taps = mutableListOf<String>()
    private var end by mutableStateOf(ENDS.first())
    @Volatile private var carriedOn = 0

    @Before
    fun setUp() = compose.enableEpicChecks()

    @Test
    fun theCircleSaysWhatATapDoesInEachState() {
        showCircles()
        for ((name, s) in CIRCLES) {
            val action = s.action ?: continue
            val circle = circle(name)
            circle.assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription,
                listOf(compose.activity.getString(action.label))))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription,
                    compose.activity.getString(action.state)))
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            if (action.enabled) circle.assertIsEnabled().performClick() else circle.assertIsNotEnabled()
            // The line under it, in words, never a live region (the mic must never hear TalkBack).
            val status = STATUS.getValue(name)
            if (status.isNotEmpty()) {
                compose.onNode(hasText(status) and hasAnyAncestor(hasTestTag("circle-$name")))
                    .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.LiveRegion))
            }
        }
        compose.runOnIdle { assertEquals(CIRCLES.filter { it.second.action?.enabled == true }.map { it.first }, taps) }
    }

    @Test
    fun listeningWithNothingHeardYetItSaysSo() {
        // (On a screen of its own: two circles listening would both be "Stop listening", which the checks take for
        // two buttons that can't be told apart. A game has one.)
        looks.show { TalkingCircle(CircleState(GAME, CircleAction.STOP_LISTENING, listening = true), {}, compact = false) }
        compose.onNodeWithTag("talking-circle").tryPerformAccessibilityChecks()
        compose.onNodeWithText("Listening…").assertExists()
    }

    @Test
    fun atAnEndTheCircleIsAPictureOnly() {
        showCircles()
        circle("end")
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.ContentDescription))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsActions.OnClick))
    }

    @Test
    fun theOptionsAreAHeadedGroupOfButtons() {
        showCircles()
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Options")))
            .performScrollTo()
            .assert(isHeading())
            .assert(SemanticsMatcher("a collection of ${OPTIONS.size}") {
                it.config.getOrNull(SemanticsProperties.CollectionInfo)?.rowCount == OPTIONS.size
            })
        for (option in OPTIONS) {
            val chip = compose.onNodeWithText(option.label).performScrollTo()
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                .assertHasClickAction()
            // At least 48 dp tall, its words whole however long.
            assertTrue(chip.fetchSemanticsNode().boundsInRoot.height >= 48 * density() - 1)
            chip.performClick()
        }
        compose.runOnIdle { assertEquals(OPTIONS.map { "option ${it.value}" }, taps) }
    }

    @Test
    fun eachEndIsAPaneWhoseHeadingTakesTheFocus() {
        showEnd()
        for (e in ENDS) {
            compose.runOnIdle { end = e }
            compose.waitForIdle()
            compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, e.heading)).assertExists()
            compose.onNodeWithTag("end-heading").assert(isHeading()).assert(hasText(e.heading))
            compose.mainClock.advanceTimeBy(400)
            compose.waitUntil(5_000) {
                compose.onAllNodes(isHeading() and hasText(e.heading) and isFocused()).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText(e.end.title).assertExists()
            for ((tag, words) in e.buttons) {
                if (words == null) {
                    compose.onNodeWithTag(tag).assertDoesNotExist()
                } else {
                    compose.onNodeWithTag(tag).performScrollTo().assert(hasText(words)).assertHasClickAction()
                }
            }
            e.note?.let { compose.onNodeWithText(it).performScrollTo() }
        }
    }

    @Test
    fun pausedIsAPaneWithItsButtons() {
        looks.show { Paused(onCarryOn = { carriedOn++ }, onHelp = { taps += "help" }, onLeave = { taps += "leave" }) }
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, "Paused")).assertExists()
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) {
            compose.onAllNodes(isHeading() and hasText("Paused") and isFocused()).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("paused-carry-on").assert(hasText("Carry on")).performClick()
        compose.onNodeWithTag("paused-help").assert(hasText("How to play")).performClick()
        compose.onNodeWithTag("paused-leave").assert(hasText("Leave game")).performClick()
        compose.runOnIdle {
            assertEquals(1, carriedOn)
            assertEquals(listOf("help", "leave"), taps)
        }
    }

    @Test
    fun inEveryLook() {
        showCircles()
        looks.each { look -> compose.checkAll("the circle and options, $look") }
    }

    @Test
    fun everyEndInEveryLook() {
        showEnd()
        looks.each { look ->
            for (e in ENDS) {
                compose.runOnIdle { end = e }
                compose.checkAll("${e.heading}, $look")
            }
        }
    }

    @Test
    fun pausedInEveryLook() {
        looks.show { Paused(onCarryOn = {}, onHelp = {}, onLeave = {}) }
        looks.each { look -> compose.checkAll("Paused, $look") }
    }

    /** Every circle state, then the options, in one column that scrolls. */
    private fun showCircles() = looks.show {
        Column(Modifier.fillMaxSize().background(EpicTheme.colors.background).verticalScroll(rememberScrollState())) {
            for ((name, s) in CIRCLES) {
                Box(Modifier.fillMaxWidth().testTag("circle-$name"), contentAlignment = Alignment.Center) {
                    TalkingCircle(s, onTap = { taps += name }, compact = isAccessibilityTextSize())
                }
            }
            Options(OPTIONS) { taps += "option ${it.value}" }
        }
    }

    /** The end panel for [end], at the foot of the screen as in a game. */
    private fun showEnd() = looks.show { EndScreen(end) }

    @Composable
    private fun EndScreen(e: EndCase) {
        Column(Modifier.fillMaxSize().background(EpicTheme.colors.background)) {
            Box(Modifier.weight(1f))
            EndPanel(e.end, e.pack, e.canGoOn, onNext = {}, onAgain = {}, onBack = {}, onStore = {})
        }
    }

    private fun circle(name: String) =
        compose.onNode(hasTestTag("talking-circle") and hasAnyAncestor(hasTestTag("circle-$name"))).performScrollTo()

    private fun density() = compose.activity.resources.displayMetrics.density

    /** An end, the pack it's locked by, whether its next chapter is here, and what the panel shows. */
    class EndCase(
        val end: End,
        val pack: PackInfo?,
        val canGoOn: Boolean,
        val heading: String,
        /** Each button's tag and words (null: not there). */
        val buttons: List<Pair<String, String?>>,
        val note: String? = null,
    )

    private companion object {
        const val GAME = "noodle-rush"

        /** The circle in each state the game has: what its tap does, what the game is doing. */
        val CIRCLES = listOf(
            "speaking" to CircleState(GAME, CircleAction.SKIP, speaking = true),
            "heard" to CircleState(GAME, CircleAction.STOP_LISTENING, listening = true, partial = "yes please",
                level = { 0.6f }),
            "talk" to CircleState(GAME, CircleAction.TALK, asked = true),
            "mic-off" to CircleState(GAME, CircleAction.MIC_REFUSED, asked = true, micReady = false),
            "no-recogniser" to CircleState(GAME, CircleAction.NO_RECOGNITION, asked = true, micReady = false),
            "waiting" to CircleState(GAME, CircleAction.WAIT),
            "paused" to CircleState(GAME, CircleAction.CARRY_ON, paused = true, asked = true),
            "end" to CircleState(GAME, null, ended = true),
        )

        /** What the line under the circle says in each. */
        val STATUS = mapOf(
            "speaking" to "Tap the picture to skip",
            "heard" to "“yes please”",
            "talk" to "Your turn! Tap the mic to talk",
            "mic-off" to "Your turn!",
            "no-recogniser" to "Your turn!",
            "waiting" to "",
            "paused" to "Paused",
        )

        val OPTIONS = listOf(
            Button("Yes please", "yes"),
            Button("No", "no"),
            Button("Tell me about the moon first, and then the cake, and then the moon again", "moon"),
        )

        val PACK = PackInfo("test-more", GAME, "45 more mysteries", "More.", "test_more", 1, 15_000_000, "0".repeat(64))

        val ENDS = listOf(
            EndCase(
                End("chapter", "Chapter One", next = "c2", retry = null, locked = null), null, canGoOn = true,
                "Chapter complete",
                listOf("end-next" to "Next chapter", "end-get" to null, "end-again" to "Play again",
                    "end-back" to "Back to games"),
            ),
            EndCase(
                End("chapter", "Part one", next = "more1", retry = null, locked = PACK.id), PACK, canGoOn = false,
                "Chapter complete",
                listOf("end-next" to null, "end-get" to "Get 45 more mysteries", "end-again" to "Play again"),
                note = "What happens next is in 45 more mysteries.",
            ),
            EndCase(
                End("chapter", "Part one", next = "more1", retry = null, locked = "not-in-the-catalog"), null,
                canGoOn = false, "Chapter complete", listOf("end-get" to null),
                note = "What happens next is coming soon, in a story pack.",
            ),
            EndCase(
                End("gameover", "Too much cake", next = null, retry = "q1", locked = null), null, canGoOn = false,
                "Game over", listOf("end-next" to null, "end-again" to "Try again", "end-back" to "Back to games"),
            ),
            EndCase(
                End("end", "Happily ever after", next = null, retry = null, locked = null), null, canGoOn = false,
                "The end", listOf("end-next" to null, "end-again" to "Play again"),
            ),
        )
    }
}

/** The game's parts on a tablet turned sideways. */
class GameComponentsTabletTest : GameComponentsTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
