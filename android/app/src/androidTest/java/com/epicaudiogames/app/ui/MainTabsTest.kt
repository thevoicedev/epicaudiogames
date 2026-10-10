package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.epicaudiogames.app.ui.theme.EpicTheme
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The tabs as TalkBack and a keyboard meet them (docs/DESIGN.md › Structure, › Tab bar): four tabs, each a Tab that
 * says whether it's selected, its screen's level-1 heading, Back to Games, Ctrl with a tab's number, and every label
 * whole, on one line, at 200% text (where the bar is our own); in every look. On the phone-sized emulator it's the
 * bottom bar; MainTabsTabletTest has the rail.
 */
@RunWith(AndroidJUnit4::class)
open class MainTabsTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private var selected by mutableStateOf(Tab.GAMES)
    private val shortcuts = Shortcuts()

    @Before
    fun setUp() {
        compose.enableEpicChecks()
    }

    @Test
    fun theFourTabsSayWhichIsSelected() {
        show()
        for (tab in Tab.entries) {
            compose.onNodeWithTag("tab-${tab.key}")
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
                .assert(hasText(compose.activity.getString(tab.title)))
        }
        compose.onNodeWithTag("tab-games").assertIsSelected()
        compose.onNodeWithTag("tab-shop").assertIsNotSelected().performClick()
        compose.onNodeWithTag("tab-shop").assertIsSelected()
        compose.onNodeWithTag("tab-games").assertIsNotSelected()
        // Each tab's screen starts with its level-1 heading.
        compose.onNodeWithTag("shop-heading").assert(isHeading())
    }

    @Test
    fun backOnAnotherTabGoesToGames() {
        show()
        compose.onNodeWithTag("tab-settings").performClick()
        compose.runOnIdle { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.runOnIdle { assertEquals(Tab.GAMES, selected) }
        compose.onNodeWithTag("tab-games").assertIsSelected()
    }

    @Test
    fun ctrlAndATabsNumberPicksIt() {
        show()
        compose.runOnIdle { shortcuts.handle(Shortcut.ToTab(Tab.HELP)) }
        compose.onNodeWithTag("tab-help").assertIsSelected()
        compose.onNodeWithTag("help-heading").assert(isHeading())
    }

    @Test
    fun atTwiceTheTextSizeEveryLabelIsWholeOnOneLine() {
        show(fontScale = 2f)
        for (tab in Tab.entries) {
            compose.onNodeWithTag("tab-${tab.key}").assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
            val title = compose.activity.getString(tab.title)
            assertEquals(title, 1, compose.onNodeWithText(title, useUnmergedTree = true).lineCount())
        }
        compose.onNodeWithTag("tab-settings").performClick()
        compose.onNodeWithTag("tab-settings").assertIsSelected()
    }

    @Test
    fun inEveryLook() {
        val looks = Looks(compose)
        looks.show { Tabs() }
        looks.each { look ->
            for (tab in Tab.entries) {
                compose.onNodeWithTag("tab-${tab.key}").performClick().assertIsSelected()
                compose.checkAll("the tabs on ${tab.key}, $look")
            }
        }
    }

    /** The tabs, each tab's screen just its heading ("Shop tab"), at [fontScale]. */
    private fun show(fontScale: Float = 1f) {
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale)) {
                EpicTheme { Tabs() }
            }
        }
        compose.waitForIdle()
    }

    /** The tabs, each tab's screen just its heading ("Shop tab"), with the app's shortcuts. */
    @Composable
    private fun Tabs() {
        CompositionLocalProvider(LocalShortcuts provides shortcuts) {
            MainTabs(selected, { selected = it }) { tab ->
                ScreenHeader("${stringResource(tab.title)} tab", Modifier.testTag("${tab.key}-heading"))
            }
        }
    }

    /** How many lines a piece of text takes as it's drawn. */
    private fun SemanticsNodeInteraction.lineCount(): Int {
        val layouts = mutableListOf<TextLayoutResult>()
        performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().lineCount
    }
}

/** The tabs on a tablet turned sideways: the rail, with the same tabs in the same order. */
class MainTabsTabletTest : MainTabsTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
