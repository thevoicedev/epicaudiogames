package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.AppClip
import com.epicaudiogames.app.AppManifest
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.MemoryPrefs
import com.epicaudiogames.app.MicPrimed
import com.epicaudiogames.app.Permissions
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.ui.theme.EpicTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

/**
 * Onboarding as TalkBack meets it (docs/DESIGN.md › Onboarding): its pages in order with their step in words and their
 * heading taking the focus; the screen reader's page only with one on; the welcome read by itself once, and only
 * without a screen reader; usage data said plainly, with Turn off; Not now for the microphone; the comfort page's
 * choices taking effect; and Skip and Start playing; every page in every look. Settings kept in memory; the reading
 * is a stand-in.
 */
@RunWith(AndroidJUnit4::class)
open class OnboardingTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val manifest = AppManifest.load(InstrumentationRegistry.getInstrumentation().targetContext.assets)
    private val settings = AppSettings(MemoryPrefs())
    private val audio = FakePageAudio()
    @Volatile private var done: Boolean? = null

    @Before
    fun setUp() {
        compose.enableEpicChecks()
    }

    @Test
    fun fourPagesInOrderEachHeadingTakingTheFocus() {
        show()
        expectPage("onboarding-welcome", "Step 1 of 4", "Welcome")
        compose.onNodeWithTag("onboarding-back").assertDoesNotExist()
        next()
        expectPage("onboarding-mic", "Step 2 of 4", "Answer out loud")
        next()
        expectPage("onboarding-comfort", "Step 3 of 4", "Make it comfortable")
        next()
        expectPage("onboarding-ready", "Step 4 of 4", "You're ready")
        // The last page: Start playing, and no Next or Skip.
        compose.onNodeWithTag("onboarding-next").assertDoesNotExist()
        compose.onNodeWithTag("onboarding-skip").assertDoesNotExist()
        compose.onNodeWithTag("onboarding-start").assert(hasText("Start playing"))
        compose.onNodeWithTag("onboarding-back").assert(hasText("Back")).performClick()
        expectPage("onboarding-comfort", "Step 3 of 4", "Make it comfortable")
    }

    @Test
    fun withTalkBackOnItsOwnPageAndTheWelcomeWaitsToBeAsked() {
        show(screenReader = true)
        expectPage("onboarding-welcome", "Step 1 of 5", "Welcome")
        // Not read by itself over TalkBack: Listen is there.
        compose.runOnIdle {
            assertTrue(audio.played.isEmpty())
            assertFalse(settings.welcomePlayed)
        }
        compose.onNodeWithTag("onboarding-listen").assert(hasText("Listen"))
        repeat(3) { next() }
        expectPage("onboarding-screen-reader", "Step 4 of 5", "Playing with TalkBack")
        // The help topic's own words.
        compose.onNodeWithText(manifest!!.topic("screen-reader")!!.text.first()).performScrollTo()
        next()
        expectPage("onboarding-ready", "Step 5 of 5", "You're ready")
    }

    @Test
    fun theWelcomeIsReadByItselfOnceWithoutAScreenReader() {
        show()
        compose.runOnIdle {
            assertEquals(listOf<AppClip>(AppClip.Welcome), audio.played)
            assertTrue(settings.welcomePlayed)
        }
        compose.onNodeWithTag("onboarding-listen").assert(hasText("Pause"))
        // Leaving the page stops it; coming back, it isn't read again by itself.
        next()
        compose.runOnIdle { assertNull(audio.clipPlaying) }
        compose.onNodeWithTag("onboarding-back").performClick()
        expectPage("onboarding-welcome", "Step 1 of 4", "Welcome")
        compose.runOnIdle { assertEquals(1, audio.played.size) }
    }

    @Test
    fun usageDataIsSaidPlainlyAndTurnsOff() {
        show()
        compose.onNodeWithText("We collect usage data under a random ID", substring = true).performScrollTo()
        compose.onNodeWithTag("analytics-off").performScrollTo()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Turn off usage data")))
            .performClick()
        compose.runOnIdle { assertFalse(settings.analytics) }
        compose.onNode(said("Usage data is off")).assertExists()
        // The same button turns it on again, so the focus stays where it was.
        compose.onNodeWithTag("analytics-on").performScrollTo().performClick()
        compose.runOnIdle { assertTrue(settings.analytics) }
    }

    @Test
    fun notNowLeavesTheMicForLater() {
        // With the mic allowed already, the page only says so.
        assumeFalse(Permissions.micGranted(compose.activity))
        show()
        next()
        compose.onNodeWithTag("onboarding-mic-allow").performScrollTo().assert(hasText("Allow microphone"))
        compose.onNodeWithTag("onboarding-mic-not-now").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(MicPrimed.DECLINED, settings.micPrimed) }
        compose.onNode(said("No problem")).assertExists()
        compose.onNodeWithTag("onboarding-mic-allow").assertDoesNotExist()
    }

    @Test
    fun theComfortPagesChoicesTakeEffect() {
        show()
        repeat(2) { next() }
        compose.onNodeWithTag("setting-theme-contrast").performScrollTo().performClick()
        compose.onNodeWithTag("setting-textScale-1.3").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(ThemeChoice.CONTRAST, settings.theme)
            assertEquals(1.3f, settings.textScale)
        }
    }

    @Test
    fun skipEndsItSkipped() {
        show()
        compose.onNodeWithTag("onboarding-skip").assert(hasText("Skip")).performClick()
        compose.runOnIdle { assertEquals(false, done) }
    }

    @Test
    fun startPlayingEndsItCompleted() {
        show()
        repeat(3) { next() }
        compose.onNodeWithTag("onboarding-start").performClick()
        compose.runOnIdle { assertEquals(true, done) }
    }

    @Test
    fun openedAgainBackOnTheFirstPageClosesIt() {
        show(reopened = true)
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.runOnIdle { assertEquals(false, done) }
    }

    @Test
    fun everyPageInEveryLook() {
        val looks = Looks(compose, settings)
        // With TalkBack taken as on, so its own page is there too.
        looks.show(screenReader = true) {
            Onboarding(settings, manifest, audio, reopened = false, onMicAnswer = {}, onDone = { done = it })
        }
        looks.each { look ->
            // Back to the first page (Back is under the page, which scrolls, not in it).
            while (has("onboarding-back")) compose.onNodeWithTag("onboarding-back").performClick()
            var page = 1
            val tops = mutableListOf<Float>()
            while (true) {
                // Where the heading is, as the page shows: the same on every page (the last keeps Skip's room).
                tops += compose.onNodeWithTag("onboarding-heading").fetchSemanticsNode().boundsInRoot.top
                compose.checkAll("onboarding page $page, $look")
                if (!has("onboarding-next")) break
                compose.onNodeWithTag("onboarding-next").performClick()
                page++
            }
            assertEquals(5, page)
            assertTrue("$look: the headings' tops $tops", tops.all { abs(it - tops.first()) < 1f })
        }
    }

    private fun has(tag: String) =
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.TestTag, tag)).fetchSemanticsNodes().isNotEmpty()

    /** Onboarding, its settings in memory, TalkBack taken as on or off. */
    private fun show(screenReader: Boolean = false, reopened: Boolean = false) {
        compose.setContent {
            EpicTheme(settings, screenReader = screenReader) {
                Onboarding(settings, manifest, audio, reopened, onMicAnswer = {}, onDone = { done = it })
            }
        }
        compose.waitForIdle()
    }

    private fun next() {
        compose.onNodeWithTag("onboarding-next").assert(hasText("Next")).performClick()
        compose.waitForIdle()
    }

    /** Words TalkBack says as they appear (a live region), starting with [text]. */
    private fun said(text: String) =
        hasText(text, substring = true) and SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion)

    /** The page [tag] shows, its heading one element with its step, which takes the focus a moment later. */
    private fun expectPage(tag: String, step: String, title: String) {
        compose.onNodeWithTag(tag).assertExists()
        val heading = isHeading() and hasText(step) and hasText(title)
        compose.onNode(heading).assertExists()
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) { compose.onAllNodes(heading and isFocused()).fetchSemanticsNodes().isNotEmpty() }
    }
}

/** Onboarding on a tablet turned sideways: each page at most 640 dp wide, centred. */
class OnboardingTabletTest : OnboardingTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
