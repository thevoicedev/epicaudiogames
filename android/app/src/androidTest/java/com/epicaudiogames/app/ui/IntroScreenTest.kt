package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The intro as TalkBack and a keyboard meet it (docs/DESIGN.md › Intro): one element, "Epic Audio Games", whose action
 * is Skip intro; a tap, Escape and Space skip it too; navy in every look, the wordmark whole at twice the text size.
 * (Its sting and timing are AppModel's: AppAudioTest plays it.)
 */
@RunWith(AndroidJUnit4::class)
open class IntroScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val shortcuts = Shortcuts()
    @Volatile private var skips = 0

    private val looks by lazy { Looks(compose) }

    @Before
    fun setUp() {
        compose.enableEpicChecks()
        looks.show {
            CompositionLocalProvider(LocalShortcuts provides shortcuts) { IntroScreen(onSkip = { skips++ }) }
        }
    }

    @Test
    fun inEveryLook() {
        looks.each { look ->
            // Navy in every theme: the same element, with nothing cut off.
            compose.onNodeWithTag("intro").assertExists()
            compose.checkAll("the intro, $look")
        }
    }

    @Test
    fun itsOneElementNamedEpicAudioGamesWhoseActionSkipsIt() {
        compose.onNodeWithTag("intro")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Epic Audio Games")))
            .assert(SemanticsMatcher("its action is \"Skip intro\"") {
                it.config.getOrNull(SemanticsActions.OnClick)?.label == "Skip intro"
            })
        // The wordmark isn't read again on its own.
        compose.onAllNodes(hasText("Epic Audio Games")).assertCountEquals(0)
        compose.onNodeWithTag("intro").performSemanticsAction(SemanticsActions.OnClick)
        compose.runOnIdle { assertEquals(1, skips) }
    }

    @Test
    fun aTapEscapeAndSpaceSkipIt() {
        compose.onNodeWithTag("intro").performClick()
        compose.runOnIdle { assertEquals(1, skips) }
        compose.runOnIdle { shortcuts.handle(Shortcut.Escape) }
        compose.runOnIdle { shortcuts.handle(Shortcut.OneButton) }
        compose.runOnIdle { assertEquals(3, skips) }
        // Not a tab's shortcut: there are no tabs yet.
        compose.runOnIdle { shortcuts.handle(Shortcut.ToTab(Tab.SHOP)) }
        compose.runOnIdle { assertEquals(3, skips) }
    }
}

/** The intro on a tablet turned sideways: the emblem in the middle, where the splash had it. */
class IntroScreenTabletTest : IntroScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
