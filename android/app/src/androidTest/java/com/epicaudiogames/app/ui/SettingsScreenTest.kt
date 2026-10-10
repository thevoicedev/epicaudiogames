package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.epicaudiogames.app.AnswerTime
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.MemoryPrefs
import com.epicaudiogames.app.MicAuto
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.analytics.UsageDeletion
import com.epicaudiogames.app.ui.theme.EpicTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings as TalkBack meets it (docs/DESIGN.md › Settings): its heading and every section's, each control a whole row
 * (a switch, a radio button in its group) that sets its setting as it's changed, the voice speed said as it changes,
 * the intro's sound and the listening sound played as they're turned on and the music at each volume picked, Delete my
 * usage data asking first and saying how it went, Licences and back, and no word broken at twice the text size; the
 * page and Licences in every look. Settings kept in memory, so the phone's aren't touched.
 */
@RunWith(AndroidJUnit4::class)
open class SettingsScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val settings = AppSettings(MemoryPrefs())
    @Volatile private var samples = 0
    @Volatile private var howToPlay = 0
    @Volatile private var previews = 0
    @Volatile private var intros = 0
    @Volatile private var musicSamples = 0
    /** What Delete my usage data gets back, and how many times it's been asked. */
    @Volatile private var deletion = UsageDeletion.NOTHING_SENT
    @Volatile private var deletions = 0

    @Before
    fun setUp() {
        compose.enableEpicChecks()
    }

    @Test
    fun theHeadingAndEverySection() {
        show()
        compose.onNodeWithTag("settings-heading").assert(isHeading()).assert(hasText("Settings"))
        for (section in listOf("Sound and voice", "Microphone", "Appearance", "Transcript", "Privacy", "Help and about")) {
            compose.onNode(isHeading() and hasText(section)).performScrollTo().assertExists()
        }
    }

    @Test
    fun eachControlSetsItsSetting() {
        show()
        // A switch: the whole row, read with its hint.
        compose.onNodeWithTag("setting-introSound").performScrollTo()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            .assertIsOn().performClick().assertIsOff()
        compose.runOnIdle { assertFalse(settings.introSound) }
        // A choice: a radio button among its group's.
        compose.onNodeWithTag("setting-micAuto-never").performScrollTo()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton))
            .assertIsNotSelected().performClick().assertIsSelected()
        compose.runOnIdle { assertEquals(MicAuto.NEVER, settings.micAuto) }
        compose.onNodeWithTag("setting-answerTime-longest").performScrollTo().performClick()
        compose.onNodeWithTag("setting-musicVolume-50").performScrollTo().performClick()
        compose.onNodeWithTag("setting-theme-contrast").performScrollTo().performClick().assertIsSelected()
        compose.runOnIdle {
            assertEquals(AnswerTime.LONGEST, settings.answerTime)
            assertEquals(0.5f, settings.musicVolume)
            assertEquals(ThemeChoice.CONTRAST, settings.theme)
        }
        // The voice speed: a step faster, its value in words, said as it changes; and a sample of it.
        compose.onNodeWithText("Faster").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1.25f, settings.voiceSpeed) }
        compose.onNode(hasText("1.25 times") and SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion)).assertExists()
        compose.onNodeWithTag("setting-voiceSample").performScrollTo().performClick()
        compose.onNodeWithTag("setting-howToPlay").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, samples)
            assertEquals(1, howToPlay)
        }
    }

    @Test
    fun theListeningSoundAndTickPlayAsTheyreTurnedOn() {
        show()
        // Off: nothing to hear. On again: the sound (and the tick) as the mic would open in a game.
        compose.onNodeWithTag("setting-listeningSounds").performScrollTo().performClick().assertIsOff()
        compose.runOnIdle { assertEquals(0, previews) }
        compose.onNodeWithTag("setting-listeningSounds").performClick().assertIsOn()
        compose.runOnIdle {
            assertEquals(1, previews)
            assertTrue(settings.listeningSounds)
        }
        compose.onNodeWithTag("setting-listeningHaptics").performScrollTo().performClick().assertIsOff()
        compose.onNodeWithTag("setting-listeningHaptics").performClick().assertIsOn()
        compose.runOnIdle {
            assertEquals(2, previews)
            assertTrue(settings.listeningHaptics)
        }
    }

    @Test
    fun theIntroSoundAndTheMusicAtEachVolumePlayAsTheyreChosen() {
        show()
        // Off: nothing to hear. On again: the sound the app will start with.
        compose.onNodeWithTag("setting-introSound").performScrollTo().performClick().assertIsOff()
        compose.runOnIdle { assertEquals(0, intros) }
        compose.onNodeWithTag("setting-introSound").performClick().assertIsOn()
        compose.runOnIdle {
            assertEquals(1, intros)
            assertTrue(settings.introSound)
        }
        // Each step picked plays the music at it (the app's hook reads the setting, so it's set first); the step
        // already picked plays it again, and Off asks too, for the sample to stop.
        for ((step, volume) in listOf("25" to 0.25f, "25" to 0.25f, "0" to 0f)) {
            compose.onNodeWithTag("setting-musicVolume-$step").performScrollTo().performClick().assertIsSelected()
            compose.runOnIdle { assertEquals(volume, settings.musicVolume) }
        }
        compose.runOnIdle {
            assertEquals(3, musicSamples)
            assertEquals(0, previews)
        }
    }

    @Test
    fun privacySaysWhatsSharedAndDeletingAsksFirst() {
        show()
        compose.onNodeWithTag("setting-analytics").performScrollTo()
            .assert(hasText("Share usage data"))
            .assert(hasText("Never your name, email or voice", substring = true))
            .assertIsOn()
        // Asked first; cancelled, nothing is asked of the server.
        compose.onNodeWithTag("setting-deleteUsageData").performScrollTo().performClick()
        compose.onNodeWithText("Delete your usage data?").assertExists()
        compose.onNodeWithTag("delete-cancel").performClick()
        compose.runOnIdle { assertEquals(0, deletions) }
        // Each answer is said under the button (TalkBack says it too).
        for ((answer, words) in listOf(
            UsageDeletion.DELETED to "Your usage data is deleted.",
            UsageDeletion.FAILED to "Couldn't reach our server. Please try again.",
            UsageDeletion.NOTHING_SENT to "the app hasn't sent any usage data under its random ID",
        )) {
            deletion = answer
            delete()
            said(words)
        }
        // Off, the random ID was forgotten as it was turned off: why there's nothing to find.
        compose.onNodeWithTag("setting-analytics").performScrollTo().performClick().assertIsOff()
        compose.runOnIdle { assertFalse(settings.analytics) }
        delete()
        said("forgot its random ID when usage data was turned off")
        compose.runOnIdle { assertEquals(4, deletions) }
        compose.onNodeWithTag("setting-privacy").performScrollTo().assertHasClickAction()
    }

    /** Delete my usage data, confirmed. */
    private fun delete() {
        compose.onNodeWithTag("setting-deleteUsageData").performScrollTo().performClick()
        compose.onNodeWithTag("delete-confirm").performClick()
        compose.waitForIdle()
    }

    /** What Delete my usage data said, as live text under it. */
    private fun said(words: String) {
        compose.onNodeWithTag("setting-deleteUsageData-result").performScrollTo()
            .assert(hasText(words, substring = true))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion))
    }

    @Test
    fun theMicrophonesStateAndTheWayToTurnItOn() {
        show()
        compose.onNodeWithTag("setting-mic").performScrollTo()
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion))
        val allowed = compose.onNodeWithTag("setting-mic").fetchSemanticsNode().config
            .getOrNull(SemanticsProperties.Text)?.any { it.text == "The microphone is allowed" } == true
        if (!allowed) {
            // Allow microphone while Android still asks, else the phone's settings: one of them.
            val ways = listOf("setting-micAllow", "setting-micSettings").count {
                compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.TestTag, it)).fetchSemanticsNodes().isNotEmpty()
            }
            assertEquals(1, ways)
        }
    }

    @Test
    fun licencesShowsTheFontsLicenceAndBackReturns() {
        show()
        compose.onNodeWithTag("setting-licences").performScrollTo().performClick()
        compose.onNodeWithTag("licences-heading").assert(isHeading())
        compose.waitUntil(5_000) {
            compose.onAllNodes(isHeading() and hasText("PREAMBLE")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("licences-back").performClick()
        compose.onNodeWithTag("setting-licences").assertExists()
    }

    @Test
    fun atTwiceTheTextSizeNoWordIsBroken() {
        show(fontScale = 2f)
        // The voice speed's value gets a line of its own, rather than being squeezed between its buttons.
        assertEquals(1, compose.onNodeWithText("Normal speed", useUnmergedTree = true).lineCount())
        compose.onNodeWithText("Slower").assertHasClickAction()
        compose.onNodeWithText("Faster").assertHasClickAction()
    }

    @Test
    fun inEveryLook() {
        val looks = Looks(compose, settings)
        looks.show { Settings() }
        looks.each { look -> compose.checkAll("Settings, $look") }
    }

    @Test
    fun licencesInEveryLook() {
        val looks = Looks(compose, settings)
        looks.show { Settings() }
        compose.onNodeWithTag("setting-licences").performScrollTo().performClick()
        compose.waitUntil(5_000) {
            compose.onAllNodes(isHeading() and hasText("PREAMBLE")).fetchSemanticsNodes().isNotEmpty()
        }
        looks.each { look -> compose.checkAll("Licences, $look") }
    }

    /** The Settings tab, on these [settings], each thing it asks for counted. */
    @Composable
    private fun Settings() {
        SettingsScreen(
            settings,
            onPlaySample = { samples++ },
            onHowToPlay = { howToPlay++ },
            onShowWelcome = {},
            onDeleteUsageData = {
                deletions++
                deletion
            },
            onMicAnswer = {},
            onPreviewCue = { previews++ },
            onPreviewIntro = { intros++ },
            onPreviewMusic = { musicSamples++ },
        )
    }

    private fun show(fontScale: Float = 1f) {
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale)) {
                EpicTheme(settings) { Settings() }
            }
        }
        compose.waitForIdle()
    }

    /** How many lines a piece of text takes as it's drawn. */
    private fun SemanticsNodeInteraction.lineCount(): Int {
        val layouts = mutableListOf<TextLayoutResult>()
        performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().lineCount
    }
}

/** Settings on a tablet turned sideways: one column, at most 640 dp wide, centred. */
class SettingsScreenTabletTest : SettingsScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}

/**
 * Settings with the phone's text at 200%: Delete my usage data's question is a dialog, a window of its own, which the
 * looks' text size doesn't reach, so the phone's own setting makes it large (and the page with it).
 */
class SettingsScreenLargeTextTest : SettingsScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val largeText = LargeText()
    }
}
