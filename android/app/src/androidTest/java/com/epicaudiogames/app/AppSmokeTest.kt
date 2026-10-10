package com.epicaudiogames.app

import android.content.Intent
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.ui.LargeText
import com.epicaudiogames.app.ui.TabletScreen
import com.epicaudiogames.app.ui.checkAll
import com.epicaudiogames.app.ui.enableEpicChecks
import com.epicaudiogames.engine.Saved
import org.junit.After
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The app itself, end to end, as it starts for the UI tests and the screenshot tools: launched with DebugLaunch's
 * extras (no intro, no onboarding, no usage data, no microphone: nothing is stored, and nothing asked of Android), the
 * four tabs each with their screen and its heading; a game opened from its card, its menu's store sheet opened and
 * closed, and Back to the list. The accessibility checks run on each. The game's save on this phone is put back after.
 */
@RunWith(AndroidJUnit4::class)
open class AppSmokeTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val launch = Intent(context, MainActivity::class.java)
        .putExtra("EpicNoIntro", true)
        .putExtra("EpicSkipOnboarding", true)
        .putExtra("EpicAnalytics", "off")
        .putExtra("EpicMic", "off")

    @get:Rule
    val compose = AndroidComposeTestRule(ActivityScenarioRule<MainActivity>(launch)) { rule ->
        var activity: MainActivity? = null
        rule.scenario.onActivity { activity = it }
        checkNotNull(activity)
    }

    private val saves = Saves(context)
    private var kept: Saved? = null

    @Before
    fun setUp() {
        compose.enableEpicChecks(sheet = true)
        kept = saves.load(GAME)
        compose.waitUntil(LAUNCH_MS) { has("tab-games") }
    }

    @After
    fun tearDown() {
        // The phone's own place in the game, as it was.
        kept?.let { saves.store(GAME, it) } ?: saves.clear(GAME)
    }

    @Test
    fun eachTabHasItsScreenAndHeading() {
        for ((tab, heading) in listOf("games" to "Games", "shop" to "Shop", "help" to "Help", "settings" to "Settings")) {
            compose.onNodeWithTag("tab-$tab").performClick().assertIsSelected()
            compose.onNodeWithTag("$tab-heading").assert(isHeading()).assert(hasText(heading))
            compose.checkAll("the $tab tab")
        }
    }

    @Test
    fun aGameOpensItsStoreSheetOpensAndClosesAndBackLeavesIt() {
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.IndexForKey)).performScrollToKey(GAME)
        compose.onNodeWithTag("game-$GAME").performScrollTo().performClick()
        compose.waitUntil(GAME_MS) { has("talking-circle") }
        compose.checkAll("the game")
        // Its menu (a window of its own, checked from one of its items), then More stories and levels: the store sheet
        // for its packs, over the game (which waits).
        compose.onNodeWithTag("game-menu").performClick()
        compose.onNodeWithTag("menu-start-again").tryPerformAccessibilityChecks()
        compose.onNodeWithTag("menu-packs").performClick()
        compose.waitUntil(SHEET_MS) { has("store-sheet") }
        compose.checkAll("the game's store sheet")
        compose.onNodeWithTag("store-close").performScrollTo().performClick()
        compose.waitUntil(SHEET_MS) { !has("store-sheet") }
        // Back: the list again, its place kept.
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitUntil(GAME_MS) { has("games-heading") }
    }

    private fun has(tag: String) = compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

    private companion object {
        /** A game with packs (so its menu has More stories and levels). */
        const val GAME = "frootopia"
        const val LAUNCH_MS = 30_000L
        const val GAME_MS = 30_000L
        const val SHEET_MS = 10_000L
    }
}

/** The app on a tablet turned sideways: the rail, the Games grid, the game in two panes. */
class AppSmokeTabletTest : AppSmokeTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}

/**
 * The app with the phone's text at 200%: the tabs on our own bar, the game in its compact layout, and its menu and
 * store sheet (windows of their own) as large.
 */
class AppSmokeLargeTextTest : AppSmokeTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val largeText = LargeText()
    }
}
