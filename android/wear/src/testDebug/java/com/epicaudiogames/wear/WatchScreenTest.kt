package com.epicaudiogames.wear

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.epicaudiogames.wearlink.WearCommand
import com.epicaudiogames.wearlink.WearState
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The watch's one screen (WatchScreen.kt) in each of the phone's states, as TalkBack finds it: the title a heading,
 * the state in words, the big button named as on the phone (dimmed when it can't do anything), Pause while there's
 * something to pause, the end's and no game's lines, and a press that couldn't reach the phone said as it appears. Run
 * under Robolectric on a large round watch (454 px); [WatchScreenSmallTest] on a small one (384 px). With
 * -PwearShots=<folder>, each state's picture is saved there too ("<size>-<state>.png", square: the watch's screen is
 * the circle inside). The states are the debug build's demo ones (WatchDemo.kt), worded as the phone sends them.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w227dp-h227dp-round-watch-xhdpi")
open class WatchScreenTest {
    @get:Rule
    val compose = createComposeRule()

    /** The watch's size, for the pictures' names. */
    protected open val size = "large"

    private val pressed = mutableListOf<WearCommand>()

    private fun show(state: WearState, trouble: Boolean = false, ambient: Boolean = false) {
        compose.setContent { WatchScreen(state, trouble, ambient) { pressed += it } }
    }

    private fun demo(name: String) = checkNotNull(WatchDemo.state(name)) { "no demo state $name" }

    /** The list scrolled to the item tagged [tag] (a small watch's may be below). */
    private fun scrollTo(tag: String) {
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasTestTag(tag))
    }

    @Test
    fun speakingItsTitleStateAndButtons() {
        show(demo("speaking"))
        save("speaking")
        compose.onNodeWithTag("watch-title").assertTextEquals("Noodle Rush").assert(isHeading())
        compose.onNodeWithTag("watch-state").assertTextEquals("Speaking")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsEnabled().assertHasClickAction().assert(hasText("Skip"))
            .performClick()
        scrollTo("watch-pause")
        compose.onNodeWithTag("watch-pause").assertIsEnabled().assert(hasText("Pause")).performClick()
        assertEquals(listOf(WearCommand.PRIMARY, WearCommand.PAUSE), pressed)
    }

    @Test
    fun listeningSaysSoAndStops() {
        show(demo("listening"))
        save("listening")
        compose.onNodeWithTag("watch-state").assertTextEquals("Listening…")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsEnabled().assert(hasText("Stop listening"))
    }

    @Test
    fun yourTurnTalks() {
        show(demo("turn"))
        save("turn")
        compose.onNodeWithTag("watch-state").assertTextEquals("Your turn")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsEnabled().assert(hasText("Talk"))
    }

    @Test
    fun pausedCarriesOnWithNoPause() {
        show(demo("paused"))
        save("paused")
        compose.onNodeWithTag("watch-state").assertTextEquals("Paused")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsEnabled().assert(hasText("Carry on"))
        compose.onNodeWithTag("watch-pause").assertDoesNotExist()
    }

    @Test
    fun aMicrophoneTheWatchCantOpenIsDimmedAndSaysWhy() {
        show(demo("refused"))
        save("refused")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsNotEnabled().assert(hasText("Talk (the microphone is off)"))
            .performClick()
        assertEquals(emptyList<WearCommand>(), pressed)
    }

    @Test
    fun beforeTheQuestionTheButtonIsDimmed() {
        show(demo("wait"))
        save("wait")
        compose.onNodeWithTag("watch-state").assertTextEquals("Wait for the question")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsNotEnabled()
    }

    @Test
    fun atAnEndWhatsNextIsOnThePhone() {
        show(demo("end"))
        save("end")
        compose.onNodeWithTag("watch-state").assertTextEquals("Chapter complete")
        scrollTo("watch-end-hint")
        compose.onNodeWithTag("watch-end-hint").assertTextEquals("Choose what's next on your phone.")
        compose.onNodeWithTag("watch-primary").assertDoesNotExist()
        compose.onNodeWithTag("watch-pause").assertDoesNotExist()
    }

    @Test
    fun noGameSaysToOpenOne() {
        show(demo("none"))
        save("none")
        compose.onNodeWithTag("watch-no-game").assertTextEquals("Open a game on your phone")
        compose.onNodeWithTag("watch-title").assertDoesNotExist()
        compose.onNodeWithTag("watch-primary").assertDoesNotExist()
    }

    @Test
    fun aPressThatCouldntReachThePhoneIsSaidAsItAppears() {
        show(demo("turn"), trouble = true)
        save("trouble")
        scrollTo("watch-trouble")
        compose.onNodeWithTag("watch-trouble")
            .assert(hasText("Can't reach your phone. Keep it close, then try again."))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
    }

    @Test
    fun ambientDrawsTheSameWords() {
        show(demo("listening"), ambient = true)
        save("ambient-listening")
        compose.onNodeWithTag("watch-state").assertTextEquals("Listening…")
        scrollTo("watch-primary")
        compose.onNodeWithTag("watch-primary").assertIsEnabled().assert(hasText("Stop listening"))
    }

    /**
     * The screen's picture, when the run asks for them (wear.shots): drawn from its view, as Compose's own capture
     * waits for a frame Robolectric doesn't draw.
     */
    private fun save(state: String) {
        val dir = System.getProperty("wear.shots").orEmpty()
        if (dir.isEmpty()) return
        compose.waitForIdle()
        val view = (compose.onRoot().fetchSemanticsNode().root as ViewRootForTest).view
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))
        File(dir).mkdirs()
        File(dir, "$size-$state.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}

/** The same on a small round watch (384 px), where the list scrolls sooner. */
@Config(sdk = [34], qualifiers = "w192dp-h192dp-round-watch-xhdpi")
class WatchScreenSmallTest : WatchScreenTest() {
    override val size = "small"
}
