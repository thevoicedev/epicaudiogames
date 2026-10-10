package com.epicaudiogames.app.ui

import android.os.Build
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
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
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.AppClip
import com.epicaudiogames.app.AppManifest
import com.epicaudiogames.app.HelpHighlight
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.currentWord
import com.epicaudiogames.app.ui.theme.EpicTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Help as TalkBack and a keyboard meet it (docs/DESIGN.md › Help): this app's topics from the build's own app.json, in
 * order; a topic's page with its heading (which takes the focus), Listen (Pause and "Playing" while it reads, a moment
 * late with TalkBack on, and not there without the clip), the word being read marked, and its links; Back to the list;
 * and the help sheet a game opens; each in every look. The reading itself is a stand-in (FakePageAudio): AppAudioTest
 * plays the real one.
 */
@RunWith(AndroidJUnit4::class)
open class HelpScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val pages = AppManifest.load(InstrumentationRegistry.getInstrumentation().targetContext.assets)!!.help
    private var audio = FakePageAudio()
    private var topic by mutableStateOf<String?>(null)
    @Volatile private var welcomes = 0
    @Volatile private var closed = false

    @Before
    fun setUp() {
        // Android's accessibility checks, but for Material's sheet scrim (Looks.kt): the help sheet has Close, and Back
        // closes it too.
        compose.enableEpicChecks(sheet = true)
    }

    @Test
    fun theListHasThisAppsTopicsInOrder() {
        show()
        compose.onNodeWithTag("help-heading").assert(isHeading()).assert(hasText("Help"))
        // Android's own pages (the iPhone's are left out), every one a button with its title and its line.
        assertEquals("Using TalkBack", pages.single { it.id == "screen-reader" }.title)
        assertEquals("getting-started", pages.first().id)
        for (page in pages) {
            compose.onNodeWithTag("help-topic-${page.id}").performScrollTo()
                .assert(hasText(page.title)).assert(hasText(page.summary)).assertHasClickAction()
        }
        compose.onNodeWithTag("help-welcome").performScrollTo().assert(hasText("Show the welcome again")).performClick()
        compose.runOnIdle { assertEquals(1, welcomes) }
        compose.onNodeWithTag("help-email").performScrollTo()
            .assert(hasText("Email james@hugo.fm")).assertHasClickAction()
    }

    @Test
    fun aTopicHasItsHeadingListenWordsAndLinksAndBackReturns() {
        show()
        compose.onNodeWithTag("help-topic-contact").performScrollTo().performClick()
        compose.runOnIdle { assertEquals("contact", topic) }
        compose.onNodeWithTag("help-page-heading").assert(isHeading()).assert(hasText("Contact and privacy"))
        focusMovesTo(isHeading() and hasText("Contact and privacy"))
        compose.onNodeWithTag("help-listen").assert(hasText("Listen")).assertHasClickAction()
        for (paragraph in pages.single { it.id == "contact" }.text) onPage(paragraph).performScrollTo()
        compose.onNodeWithTag("help-link-0").performScrollTo()
            .assert(hasText("Email james@hugo.fm")).assertHasClickAction()
        // Back: the list again, with every topic.
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.runOnIdle { assertNull(topic) }
        compose.onNodeWithTag("help-heading").assertExists()
        compose.onNodeWithTag("help-topic-contact").assertExists()
    }

    @Test
    fun listenReadsThePageAndTheWordBeingReadIsMarked() {
        show(open = "voice")
        compose.onNodeWithTag("help-listen").performClick()
        compose.runOnIdle { assertEquals(listOf<AppClip>(AppClip.Help("voice")), audio.played) }
        compose.onNodeWithTag("help-listen").assert(hasText("Pause"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Playing"))
        // The voice ten characters into the second paragraph: that word, and only that word, is marked.
        val paragraph = pages.single { it.id == "voice" }.text[1]
        compose.runOnIdle { audio.highlight = HelpHighlight(1, 10) }
        compose.waitForIdle()
        val shown = onPage(paragraph).fetchSemanticsNode().config[SemanticsProperties.Text].single()
        val marked = shown.spanStyles.filter { it.item.background.alpha > 0f }
        assertEquals(1, marked.size)
        assertEquals(currentWord(paragraph, 10).word, shown.text.substring(marked[0].start, marked[0].end))
        // Pause: it stops, and it's Listen again.
        compose.onNodeWithTag("help-listen").performClick()
        compose.runOnIdle { assertNull(audio.clipPlaying) }
        compose.onNodeWithTag("help-listen").assert(hasText("Listen"))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.StateDescription))
    }

    @Test
    fun withTalkBackOnListenWaitsForTalkBacksOwnFeedback() {
        show(open = "voice", screenReader = true)
        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("help-listen").performClick()
        compose.mainClock.advanceTimeBy(LISTEN_DELAY_MS / 2)
        // Already Pause (TalkBack hears that at once), but the voice waits.
        compose.onNodeWithTag("help-listen").assert(hasText("Pause"))
        compose.runOnUiThread { assertTrue(audio.played.isEmpty()) }
        compose.mainClock.advanceTimeBy(LISTEN_DELAY_MS)
        compose.waitUntil(5_000) { compose.runOnUiThread { audio.played.isNotEmpty() } }
        compose.runOnUiThread { assertEquals(listOf<AppClip>(AppClip.Help("voice")), audio.played) }
        compose.mainClock.autoAdvance = true
    }

    @Test
    fun aTopicStillOpenAsTheTabComesBackLeavesTheFocusAlone() {
        // As a tab picked keeps the focus on the tab (docs/DESIGN.md › Everywhere › Focus).
        show(open = "voice")
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
        compose.onNode(isHeading() and isFocused()).assertDoesNotExist()
    }

    @Test
    fun aTopicOpenedFromSettingsTakesTheFocusOnce() {
        var focusings by mutableIntStateOf(0)
        topic = "voice"
        compose.setContent {
            EpicTheme {
                HelpScreen(
                    pages, audio, topic, { topic = it }, onShowWelcome = {},
                    focusTopic = focusings == 0, onTopicFocused = { focusings++ },
                )
            }
        }
        focusMovesTo(isHeading() and hasText("Playing with your voice"))
        compose.runOnIdle { assertEquals(1, focusings) }
    }

    @Test
    fun withoutTheClipInTheBuildThereIsNoListen() {
        audio = FakePageAudio(clips = false)
        show(open = "voice")
        compose.onNodeWithTag("help-page-heading").assertExists()
        compose.onNodeWithTag("help-listen").assertDoesNotExist()
    }

    @Test
    fun inAGameItsASheetOnPlayingWithYourVoice() {
        var sheetTopic by mutableStateOf<String?>("voice")
        compose.setContent { EpicTheme { HelpSheet(pages, audio, sheetTopic, { sheetTopic = it }) { closed = true } } }
        compose.waitForIdle()
        compose.onNode(paneTitled("Playing with your voice")).assertExists()
        focusMovesTo(isHeading() and hasText("Playing with your voice"))
        // All help topics: the list, in the sheet; a topic from it.
        compose.onNodeWithTag("help-all-topics").assert(hasText("All help topics")).performClick()
        compose.onNode(paneTitled("Help")).assertExists()
        compose.onNodeWithTag("help-welcome").assertDoesNotExist()
        compose.onNodeWithTag("help-topic-typing").performScrollTo().performClick()
        compose.onNodeWithTag("help-page-heading").assert(hasText("Typing and choosing answers"))
        compose.onNodeWithTag("help-close").assert(hasText("Close")).performClick()
        compose.waitUntil(5_000) { closed }
    }

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    fun theSheetsBarIconsFollowThePaletteNotThePhone() {
        // Dark icons over Light, light ones over Dark and High contrast, whichever the phone's dark mode is.
        val looks = Looks(compose)
        looks.show { HelpSheet(pages, audio, "voice", {}) {} }
        looks.each { look ->
            val light = compose.runOnIdle { sheetWindow()?.let(::lightBars) }
            assertEquals("$look", look.theme == ThemeChoice.LIGHT, light)
        }
    }

    @Test
    fun theSheetsButtonsKeepTheirWordsWhole() {
        // Close has its room first; All help topics wraps in what's left. (A sheet is a window of its own, which the
        // looks' text size doesn't reach: HelpScreenLargeTextTest has the phone's own 200%.)
        compose.setContent { EpicTheme { HelpSheet(pages, audio, "voice", {}) {} } }
        compose.waitForIdle()
        compose.onNodeWithText("Close", useUnmergedTree = true).assertWordsWhole()
        compose.onNodeWithText("All help topics", useUnmergedTree = true).assertWordsWhole()
    }

    @Test
    fun besideAPageTheListSaysWhichTopicShows() {
        show(open = "voice")
        if (twoPanesHere()) {
            // An expanded window (a tablet-sized emulator: wm size 2560x1600, wm density 320): side by side.
            compose.onNodeWithTag("help-topic-voice").assertIsSelected()
            compose.onNodeWithTag("help-topic-typing").assertIsNotSelected()
        } else {
            // A phone's window has one pane: the page in the list's place, the rows saying nothing of selection.
            compose.onNodeWithTag("help-topic-voice").assertDoesNotExist()
            compose.runOnIdle { topic = null }
            compose.onNodeWithTag("help-topic-voice")
                .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Selected))
        }
    }

    @Test
    fun theListAndAPageInEveryLook() {
        val looks = Looks(compose)
        looks.show { HelpScreen(pages, audio, topic, { topic = it }, onShowWelcome = {}) }
        looks.each { look ->
            compose.runOnIdle { topic = null }
            compose.checkAll("the Help list, $look")
            // A page being read, its word marked.
            compose.runOnIdle {
                topic = "voice"
                audio.play(AppClip.Help("voice"))
                audio.highlight = HelpHighlight(0, 12)
            }
            compose.checkAll("a Help page, $look")
            compose.runOnIdle { audio.stopClip() }
        }
    }

    @Test
    fun theSheetInEveryLook() {
        val looks = Looks(compose)
        var sheetTopic by mutableStateOf<String?>("voice")
        looks.show { HelpSheet(pages, audio, sheetTopic, { sheetTopic = it }) {} }
        looks.each { look ->
            compose.runOnIdle { sheetTopic = "voice" }
            compose.checkAll("the help sheet's page, $look")
            compose.runOnIdle { sheetTopic = null }
            compose.checkAll("the help sheet's list, $look")
        }
    }

    /** The Help tab, on [open]'s page (null: the list), with TalkBack taken as on or off. */
    private fun show(open: String? = null, screenReader: Boolean = false) {
        topic = open
        compose.setContent {
            EpicTheme(screenReader = screenReader) {
                HelpScreen(pages, audio, topic, { topic = it }, onShowWelcome = { welcomes++ })
            }
        }
        compose.waitForIdle()
    }

    /**
     * A paragraph of the page showing. (Beside the list, Material's pane scaffold also keeps a copy of the page, out
     * of sight and with no size, which TalkBack never sees.)
     */
    private fun onPage(paragraph: String) =
        compose.onNode(hasText(paragraph) and hasAnyAncestor(hasTestTag("help-page")))

    /** Whether this device's window is wide enough for the list and a page side by side. */
    private fun twoPanesHere(): Boolean {
        val metrics = compose.activity.resources.displayMetrics
        return metrics.widthPixels / metrics.density >= 840
    }

    /** The focus (and with it TalkBack's) moves to what [matcher] finds, a moment after it appears. */
    private fun focusMovesTo(matcher: SemanticsMatcher) {
        compose.mainClock.advanceTimeBy(400)
        compose.waitUntil(5_000) { compose.onAllNodes(matcher and isFocused()).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun paneTitled(title: String) = SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, title)
}

/** Help on a tablet turned sideways: the list and the page side by side. */
class HelpScreenTabletTest : HelpScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}

/**
 * Help with the phone's text at 200%: the help sheet is a window of its own, which the looks' text size doesn't reach,
 * so the phone's own setting makes it large (and the tab's page with it).
 */
class HelpScreenLargeTextTest : HelpScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val largeText = LargeText()
    }
}
