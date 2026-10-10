package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.Catalog
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Games as TalkBack meets it (docs/DESIGN.md › Games): its heading and how to play in a line; each game a card that's
 * one element ("The Werewolf. In progress. …"), whose action is Play or Carry on, with More stories and levels among its
 * actions while a pack is still to get; under it, Get <pack>, named with its game, or "All packs installed". The
 * covers give way at accessibility text sizes; on an expanded window the cards are two to a row. In every look, every
 * card checked. The build's own catalog; which games are in progress and which packs are in is the test's to say.
 */
@RunWith(AndroidJUnit4::class)
open class HomeScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val games = Catalog.load(InstrumentationRegistry.getInstrumentation().targetContext.assets)
    private var installedAll by mutableStateOf(false)
    private var focusHeading by mutableStateOf(false)
    private val opened = mutableListOf<String>()
    private val stores = mutableListOf<String>()
    private val looks by lazy { Looks(compose) }

    /** Noodle Rush is in progress; with [installedAll] every pack is in, else none is. */
    private fun inProgress(id: String) = id == "noodle-rush"

    @Before
    fun setUp() {
        compose.enableEpicChecks()
        looks.show {
            HomeScreen(
                LazyGridState(), games, ::inProgress, { _: PackInfo -> installedAll },
                onOpen = { opened += it.id }, onStore = { stores += it.id },
                focusHeading = focusHeading, onHeadingFocused = { focusHeading = false },
            )
        }
    }

    @Test
    fun theHeadingAndHowToPlay() {
        compose.onNodeWithTag("games-heading").assert(isHeading()).assert(hasText("Games"))
        compose.onNodeWithText("Put on your headphones, listen, and answer out loud.").assertExists()
    }

    @Test
    fun eachCardIsOneElementThatOpensItsGame() {
        for (game in games) {
            val card = card(game)
            val config = card.fetchSemanticsNode().config
            // Read as one element: its title first, "In progress" where it is, then what it's about and what's free.
            val spoken = config.getOrNull(SemanticsProperties.ContentDescription)?.single().orEmpty()
            assertTrue(spoken, spoken.startsWith(game.title))
            assertEquals(game.id, inProgress(game.id), "In progress." in spoken)
            card.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            // What a double tap does, said as the action.
            assertEquals(if (inProgress(game.id)) "Carry on" else "Play", config[SemanticsActions.OnClick].label)
            card.performClick()
        }
        compose.runOnIdle { assertEquals(games.map { it.id }, opened) }
    }

    @Test
    fun aPackToGetIsAButtonNamedWithItsGameAndAnAction() {
        for (game in games.filter { it.packs.isNotEmpty() }) {
            val pack = game.packs.first()
            card(game).assert(SemanticsMatcher("its actions have More stories and levels") { node ->
                node.config.getOrNull(SemanticsActions.CustomActions).orEmpty().any { it.label == "More stories and levels" }
            })
            compose.onNodeWithTag("packs-${game.id}").performScrollTo()
                .assert(SemanticsMatcher.expectValue(
                    SemanticsProperties.ContentDescription, listOf("Get ${pack.title} for ${game.title}")))
                .assertHasClickAction()
                .performClick()
        }
        compose.runOnIdle { assertEquals(games.filter { it.packs.isNotEmpty() }.map { it.id }, stores) }
    }

    @Test
    fun everyPackInSaysSoAndHasNoAction() {
        compose.runOnIdle { installedAll = true }
        for (game in games.filter { it.packs.isNotEmpty() }) {
            card(game).assert(SemanticsMatcher.keyNotDefined(SemanticsActions.CustomActions))
            compose.onNodeWithTag("packs-${game.id}").assertDoesNotExist()
        }
        assertTrue(compose.onAllNodesWithText("All packs installed").fetchSemanticsNodes().isNotEmpty())
    }

    @Test
    fun theHeadingTakesTheFocusAfterTheIntro() {
        compose.runOnIdle { focusHeading = true }
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) {
            compose.onAllNodes(isHeading() and hasText("Games") and isFocused()).fetchSemanticsNodes().isNotEmpty()
        }
        compose.runOnIdle { assertEquals(false, focusHeading) }
    }

    @Test
    fun onAWideWindowTheCardsAreTwoToARow() {
        val first = card(games[0]).fetchSemanticsNode().boundsInRoot
        val second = card(games[1]).fetchSemanticsNode().boundsInRoot
        if (wide()) {
            // Side by side in the first row (neither scrolled), each at most 480 dp.
            val firstNow = compose.onNodeWithTag("game-${games[0].id}").fetchSemanticsNode().boundsInRoot
            assertEquals(firstNow.top, second.top, 1f)
            assertTrue(second.left > firstNow.right)
            assertTrue(firstNow.width <= 480 * density() + 1)
        } else {
            // One column: each card as wide as the other, one under the other.
            assertEquals(first.left, second.left, 1f)
            assertEquals(first.width, second.width, 1f)
        }
    }

    @Test
    fun inEveryLook() {
        looks.each { look ->
            // At accessibility text sizes the covers give way to the words; every card is still there.
            for (game in games) card(game)
            compose.checkAll("Games, $look")
        }
    }

    /** A game's card, scrolled into sight. */
    private fun card(game: GameInfo) =
        compose.onNodeWithTag("game-${game.id}").also { runCatching { gridScrollTo(game.id) } }.performScrollTo()

    private fun gridScrollTo(id: String) =
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex)).performScrollToKey(id)

    /** Whether the window is an expanded one (840 dp and wider): the tablet's. */
    private fun wide() = compose.activity.resources.configuration.screenWidthDp >= 840

    private fun density() = compose.activity.resources.displayMetrics.density
}

/** Games on a tablet turned sideways: the rail beside it, and the cards two to a row. */
class HomeScreenTabletTest : HomeScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
