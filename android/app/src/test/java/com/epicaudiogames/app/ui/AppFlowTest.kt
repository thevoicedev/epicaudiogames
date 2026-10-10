package com.epicaudiogames.app.ui

import com.epicaudiogames.app.TestWords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The way into the app (ui/AppFlow.kt; docs/DESIGN.md › Structure, › Intro, › Onboarding): what shows before the tabs,
 * onboarding's pages and steps, where it ends, and the intro's times. iOS: the same rules in AppModel.swift.
 */
class AppFlowTest {
    @Test
    fun theIntroShowsOnTheProcesssFirstLaunchWithItsSoundOn() {
        assertTrue(AppStart.of(introSound = true, firstLaunch = true, onboardingVersion = 1).intro)
        // Once per process: the app left and opened again while it lives has none.
        assertFalse(AppStart.of(introSound = true, firstLaunch = false, onboardingVersion = 1).intro)
        // "Play the intro sound" off skips the intro screen too, not just its sound.
        assertFalse(AppStart.of(introSound = false, firstLaunch = true, onboardingVersion = 1).intro)
    }

    @Test
    fun onboardingShowsUntilItsBeenFinishedOrSkippedOnce() {
        assertTrue(AppStart.of(introSound = true, firstLaunch = true, onboardingVersion = 0).onboarding)
        assertFalse(AppStart.of(introSound = true, firstLaunch = true, ONBOARDING_VERSION).onboarding)
        // Without the intro, onboarding is the first thing on the first run, and the tabs after that.
        assertEquals(AppStart(intro = false, onboarding = true), AppStart.of(false, firstLaunch = true, 0))
        assertEquals(AppStart(intro = false, onboarding = false), AppStart.of(false, firstLaunch = false, 1))
        assertEquals(1, ONBOARDING_VERSION)
    }

    @Test
    fun theScreenReadersPageOnlyWithOneOn() {
        val without = listOf(OnboardingPage.WELCOME, OnboardingPage.MIC, OnboardingPage.COMFORT, OnboardingPage.READY)
        assertEquals(without, OnboardingPage.pages(screenReader = false))
        assertEquals(OnboardingPage.entries, OnboardingPage.pages(screenReader = true))
        // TalkBack turned off on that page doesn't take the page from under the player.
        assertEquals(OnboardingPage.entries, OnboardingPage.pages(false, showing = OnboardingPage.SCREEN_READER))
    }

    @Test
    fun eachStepSaysWhereItIsAndWhereNextAndBackGo() {
        val first = OnboardingStep.of(OnboardingPage.WELCOME, screenReader = false)
        assertEquals("Step 1 of 4", first.words(TestWords))
        assertNull(first.previous)
        assertEquals(OnboardingPage.MIC, first.next)
        assertFalse(first.last)
        // Without a screen reader, the comfort page is followed by the last.
        val comfort = OnboardingStep.of(OnboardingPage.COMFORT, screenReader = false)
        assertEquals("Step 3 of 4", comfort.words(TestWords))
        assertEquals(OnboardingPage.READY, comfort.next)
        // With one, by the screen reader's page, and there are five.
        val withTalkBack = OnboardingStep.of(OnboardingPage.COMFORT, screenReader = true)
        assertEquals("Step 3 of 5", withTalkBack.words(TestWords))
        assertEquals(OnboardingPage.SCREEN_READER, withTalkBack.next)
        val ready = OnboardingStep.of(OnboardingPage.READY, screenReader = true)
        assertEquals("Step 5 of 5", ready.words(TestWords))
        assertTrue(ready.last)
        assertNull(ready.next)
        assertEquals(OnboardingPage.SCREEN_READER, ready.previous)
    }

    @Test
    fun walkingThroughVisitsEveryPageOnceInOrder() {
        for (screenReader in listOf(false, true)) {
            val seen = mutableListOf<OnboardingPage>()
            var page: OnboardingPage? = OnboardingPage.WELCOME
            while (page != null) {
                seen += page
                page = OnboardingStep.of(page, screenReader).next
            }
            assertEquals(OnboardingPage.pages(screenReader), seen)
            // And back again, from the last.
            val back = generateSequence(seen.last()) { OnboardingStep.of(it, screenReader).previous }.toList()
            assertEquals(seen.reversed(), back)
        }
    }

    @Test
    fun theOnboardingPagesHaveDesignsIdentifiers() {
        assertEquals(
            listOf(
                "onboarding-welcome", "onboarding-mic", "onboarding-comfort", "onboarding-screen-reader",
                "onboarding-ready",
            ),
            OnboardingPage.entries.map { it.tag },
        )
        // As docs/DESIGN.md's table of test identifiers names them (the iPhone app's UI tests use the same).
        val design = File("../../docs/DESIGN.md").readText()
        val identifiers = "`onboarding-welcome`, `-mic`, `-comfort`, `-screen-reader`, `-ready`"
        assertTrue(design.contains(identifiers))
    }

    @Test
    fun onboardingEndsOnGamesOrBackWhereItWasOpened() {
        // The first run: Games, finished or skipped.
        assertEquals(Tab.GAMES, tabAfterOnboarding(completed = true, openedFrom = null))
        assertEquals(Tab.GAMES, tabAfterOnboarding(completed = false, openedFrom = null))
        // Opened again from Settings or Help: Start playing goes to Games, Skip back.
        assertEquals(Tab.GAMES, tabAfterOnboarding(completed = true, openedFrom = Tab.SETTINGS))
        assertEquals(Tab.SETTINGS, tabAfterOnboarding(completed = false, openedFrom = Tab.SETTINGS))
        assertEquals(Tab.HELP, tabAfterOnboarding(completed = false, openedFrom = Tab.HELP))
    }

    @Test
    fun theIntrosTimesAreDesigns() {
        assertEquals(700L, IntroTimes.SCREEN_READER_DELAY)
        assertEquals(300L, IntroTimes.AFTER_STING)
        assertEquals(2_500L, IntroTimes.WITHOUT_STING)
        assertEquals(300, IntroTimes.FADE_IN)
        assertEquals(400L, LISTEN_DELAY_MS)
    }
}
