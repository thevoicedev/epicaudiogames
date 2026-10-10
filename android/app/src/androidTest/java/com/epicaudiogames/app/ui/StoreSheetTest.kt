package com.epicaudiogames.app.ui

import android.os.Build
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.Packs
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Store
import com.epicaudiogames.app.ThemeChoice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The store sheet as TalkBack meets it (docs/DESIGN.md › Shop and the store sheet): one pane named "More from …", whose
 * heading takes the focus; a pack's every state in words, each button named with its words first and read once; a
 * download heard only at its milestones; the store's messages; Restore purchases; and Close; in every look. A game with
 * one pack that isn't on the phone, and a Store that never talks to Play: the test sets what it knows.
 */
@RunWith(AndroidJUnit4::class)
open class StoreSheetTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private lateinit var scope: CoroutineScope
    private lateinit var store: Store
    @Volatile private var closed = false
    private val looks by lazy { Looks(compose) }

    @Before
    fun setUp() {
        // Android's accessibility checks, but for one result that's Material's, not ours: its scrim (Looks.kt).
        compose.enableEpicChecks(sheet = true)
        scope = MainScope()
        store = Store(compose.activity, listOf(GAME), Packs(compose.activity), scope)
        looks.show { StoreSheet(GAME, store, Packs(compose.activity)) { closed = true } }
    }

    @After
    fun tearDown() {
        store.close()
        scope.cancel()
    }

    @Test
    fun itsOnePaneNamedByItsHeadingWhichTakesTheFocus() {
        // Its own name, in place of Material's "Bottom Sheet": the only pane there is.
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.PaneTitle)).assertCountEquals(1)
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, "More from Cake")).assertExists()
        compose.onNode(isHeading() and hasText("More from Cake")).assertExists()
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) {
            compose.onAllNodes(isHeading() and hasText("More from Cake") and isFocused()).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun eachStateInWordsAndEachButtonNamedOnce() {
        // The price not known yet: Get, named for its pack (and not said twice: its words aren't read as well). Each
        // state is scrolled to, which runs the accessibility checks on it.
        compose.onNodeWithTag("buy-$PACK_ID").performScrollTo()
            .assert(named("Get Cake, More cake")).assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Text))
            .assertHasClickAction()
        compose.runOnIdle { store.prices[PRODUCT] = "£1.99" }
        compose.onNodeWithTag("buy-$PACK_ID").performScrollTo().assert(named("Buy for £1.99: Cake, More cake"))
        compose.runOnIdle { store.pending[PRODUCT] = true }
        compose.onNodeWithText("Payment pending").performScrollTo()
        compose.onNodeWithText("Waiting for the payment to be approved.").assertExists()
        compose.onNodeWithTag("buy-$PACK_ID").assertDoesNotExist()
        compose.runOnIdle { store.owned[PRODUCT] = true }
        compose.onNodeWithText("Bought").assertExists()
        compose.onNodeWithTag("download-$PACK_ID").performScrollTo().assert(named("Download More cake for Cake"))
        // Downloading: the bar has its value, and what TalkBack is told moves only at 0, 25, 50 and 75%.
        compose.runOnIdle { store.downloading[PACK_ID] = 0.62f }
        compose.onNodeWithContentDescription("More cake: downloading, 50%").performScrollTo()
        compose.onNode(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo(0.62f, 0f..1f)))
            .assertExists()
        compose.runOnIdle { store.downloading[PACK_ID] = 0.74f }
        compose.onNodeWithContentDescription("More cake: downloading, 50%").assertExists()
        compose.runOnIdle { store.downloading[PACK_ID] = 0.75f }
        compose.onNodeWithContentDescription("More cake: downloading, 75%").assertExists()
    }

    @Test
    fun whatTheStoreSaysIsSaidAsItComes() {
        val failed = compose.activity.getString(R.string.store_purchase_failed)
        compose.runOnIdle {
            store.failed[PACK_ID] = "Couldn't download More cake."
            store.message = failed
        }
        for (text in listOf("Couldn't download More cake.", failed)) {
            compose.onNode(hasText(text) and SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion))
                .performScrollTo().assertExists()
        }
        compose.onNodeWithTag("restore").performScrollTo().assert(hasText("Restore purchases")).assertHasClickAction()
        compose.onAllNodesWithText("Payments are handled by Google Play.").assertCountEquals(1)
    }

    @Test
    fun closeClosesIt() {
        compose.onNodeWithTag("store-close").performScrollTo().assert(hasText("Close")).performClick()
        compose.waitForIdle()
        assertTrue(closed)
    }

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    fun itsBarIconsFollowThePaletteNotThePhone() {
        // Dark icons over Light, light ones over Dark and High contrast, whichever the phone's dark mode is.
        looks.each { look ->
            val light = compose.runOnIdle { sheetWindow()?.let(::lightBars) }
            assertEquals("$look", look.theme == ThemeChoice.LIGHT, light)
        }
    }

    @Test
    fun inEveryLook() {
        // Its price known, a message and a note: the sheet as full as it gets.
        compose.runOnIdle {
            store.prices[PRODUCT] = "£1.99"
            store.message = compose.activity.getString(R.string.store_purchase_failed)
            store.note = compose.activity.getString(R.string.store_restored)
        }
        looks.each { look -> compose.checkAll("the store sheet, $look") }
    }

    /** What TalkBack calls a button: that name, and nothing else. */
    private fun named(name: String) = SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(name))

    private companion object {
        const val PACK_ID = "test-cake-more"
        const val PRODUCT = "test_cake_more"
        val GAME = GameInfo(
            "test-cake", "Cake", "", "",
            listOf(PackInfo(PACK_ID, "test-cake", "More cake", "Ten more cakes to bake.", PRODUCT, 1, 15_000_000, "0".repeat(64))),
        )
    }
}

/** The store sheet on a tablet turned sideways: at most 640 dp wide, over the middle of the screen. */
class StoreSheetTabletTest : StoreSheetTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}

/**
 * The store sheet with the phone's text at 200%: a sheet is a window of its own, which the looks' text size doesn't
 * reach, so the phone's own setting makes it large.
 */
class StoreSheetLargeTextTest : StoreSheetTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val largeText = LargeText()
    }
}
