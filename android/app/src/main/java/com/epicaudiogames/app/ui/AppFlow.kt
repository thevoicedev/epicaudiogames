package com.epicaudiogames.app.ui

import com.epicaudiogames.app.R
import com.epicaudiogames.app.Words

/**
 * The way into the app as it starts (docs/DESIGN.md › Structure): the system's splash, then the intro (the sting, once
 * per process, with Settings › Play the intro sound on), then onboarding (until it's been finished or skipped once),
 * then the tabs. Plain Kotlin, as AppModel decides it, tested on the JVM (AppFlowTest). iOS: AppModel.swift.
 */
data class AppStart(val intro: Boolean, val onboarding: Boolean) {
    companion object {
        /**
         * What shows before the tabs: the intro on the process's first launch ([firstLaunch]) when the intro sound is
         * on (off, there's no intro screen at all), and onboarding while [onboardingVersion] is older than this app's.
         */
        fun of(introSound: Boolean, firstLaunch: Boolean, onboardingVersion: Int) = AppStart(
            intro = introSound && firstLaunch,
            onboarding = onboardingVersion < ONBOARDING_VERSION,
        )
    }
}

/** settings.onboardingVersion once onboarding is finished or skipped: a new one, with new pages, would be 2. */
const val ONBOARDING_VERSION = 1

/**
 * Where the player goes as onboarding ends: Start playing goes to Games, and so does Skip the first time; Skip in the
 * onboarding opened again ("Show the welcome again", from Help or Settings) goes back to that tab ([openedFrom]).
 */
fun tabAfterOnboarding(completed: Boolean, openedFrom: Tab?): Tab =
    if (completed || openedFrom == null) Tab.GAMES else openedFrom

/** Onboarding's pages (docs/DESIGN.md › Onboarding), in order; [tag] is the page's test identifier. */
enum class OnboardingPage(val tag: String) {
    /** The welcome, read aloud, and the line about usage data with its Turn off. */
    WELCOME("onboarding-welcome"),
    /** "Answer out loud": why the microphone, before Android asks for it. */
    MIC("onboarding-mic"),
    /** "Make it comfortable": the theme and the text size. */
    COMFORT("onboarding-comfort"),
    /** "Playing with TalkBack": only with a screen reader on. */
    SCREEN_READER("onboarding-screen-reader"),
    /** "You're ready", and Start playing. */
    READY("onboarding-ready"),
    ;

    companion object {
        /**
         * The pages a player goes through: the screen reader's with one on, or while it's the page [showing] (a
         * screen reader turned off there doesn't take the page from under the player); the others always.
         */
        fun pages(screenReader: Boolean, showing: OnboardingPage? = null): List<OnboardingPage> =
            entries.filter { it != SCREEN_READER || screenReader || showing == SCREEN_READER }
    }
}

/**
 * Where onboarding is: [page], among the [pages] the player goes through. Its place in words ("Step 2 of 4"), and where
 * Next and Back go; the last page has Start playing instead of Next, the first no Back.
 */
data class OnboardingStep(val page: OnboardingPage, val pages: List<OnboardingPage>) {
    private val index = pages.indexOf(page).also { require(it >= 0) { "$page isn't one of $pages" } }

    /** 1 for the first page. */
    val number: Int get() = index + 1
    val count: Int get() = pages.size
    /** Its place in [words]: "Step 2 of 4". */
    fun words(words: Words): String = words.text(R.string.onboarding_step, number, count)
    val next: OnboardingPage? get() = pages.getOrNull(index + 1)
    val previous: OnboardingPage? get() = pages.getOrNull(index - 1)
    val last: Boolean get() = next == null

    companion object {
        /** [page], among the pages for a screen reader on or off. */
        fun of(page: OnboardingPage, screenReader: Boolean) =
            OnboardingStep(page, OnboardingPage.pages(screenReader, showing = page))
    }
}

/** The intro's times (docs/DESIGN.md › Intro), in milliseconds. */
object IntroTimes {
    /** With a screen reader on, the sting waits this long, so the intro's name is read first. */
    const val SCREEN_READER_DELAY = 700L
    /** The intro ends this long after the sting. */
    const val AFTER_STING = 300L
    /** With no sting (none in the build, another app's music playing), the intro lasts this long. */
    const val WITHOUT_STING = 2_500L
    /** The wordmark (and the circle round the emblem) fade in over this long; at once with Reduce Motion. */
    const val FADE_IN = 300
}
