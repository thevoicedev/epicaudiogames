package com.epicaudiogames.app

import androidx.compose.runtime.snapshots.Snapshot
import kotlin.reflect.KMutableProperty1
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The settings (docs/DESIGN.md, Settings keys): their defaults, the keys and values they're stored as, what a stored
 * value the app doesn't know reads as, and the numbers' steps.
 */
class AppSettingsTest {
    @Test
    fun aNewPhoneHasTheDefaults() {
        val s = AppSettings(MemoryPrefs())
        assertEquals(ThemeChoice.SYSTEM, s.theme)
        assertEquals(1f, s.textScale)
        assertEquals(FontChoice.ATKINSON, s.font)
        assertFalse(s.reduceMotion)
        assertTrue(s.highlightWords)
        assertTrue(s.wholeLine)
        assertTrue(s.speakerNames)
        assertTrue(s.introSound)
        assertTrue(s.listeningSounds)
        assertTrue(s.listeningHaptics)
        assertEquals(1f, s.voiceSpeed)
        assertEquals(1f, s.musicVolume)
        assertEquals(AnswerTime.NORMAL, s.answerTime)
        assertEquals(MicAuto.NOT_WITH_SCREEN_READER, s.micAuto)
        assertEquals(MicPrimed.UNASKED, s.micPrimed)
        assertEquals(0, s.onboardingVersion)
        assertFalse(s.welcomePlayed)
        assertTrue(s.analytics)
    }

    @Test
    fun nothingIsStoredUntilItIsSet() {
        val prefs = MemoryPrefs()
        AppSettings(prefs)
        assertTrue(prefs.values.isEmpty())
    }

    @Test
    fun whatIsSetIsStoredUnderItsKeyAndReadBack() {
        val prefs = MemoryPrefs()
        AppSettings(prefs).apply {
            theme = ThemeChoice.CONTRAST
            textScale = 1.3f
            font = FontChoice.SYSTEM
            reduceMotion = true
            highlightWords = false
            wholeLine = false
            speakerNames = false
            introSound = false
            listeningSounds = false
            listeningHaptics = false
            voiceSpeed = 1.75f
            musicVolume = 0.25f
            answerTime = AnswerTime.LONGEST
            micAuto = MicAuto.NEVER
            micPrimed = MicPrimed.DECLINED
            onboardingVersion = 1
            welcomePlayed = true
            analytics = false
        }
        // The same strings and types as iOS's UserDefaults.
        val stored = mapOf<String, Any>(
            "settings.theme" to "contrast",
            "settings.textScale" to 1.3f,
            "settings.font" to "system",
            "settings.reduceMotion" to true,
            "settings.highlightWords" to false,
            "settings.wholeLine" to false,
            "settings.speakerNames" to false,
            "settings.introSound" to false,
            "settings.listeningSounds" to false,
            "settings.listeningHaptics" to false,
            "settings.voiceSpeed" to 1.75f,
            "settings.musicVolume" to 0.25f,
            "settings.answerTime" to "longest",
            "settings.micAuto" to "never",
            "settings.micPrimed" to "declined",
            "settings.onboardingVersion" to 1,
            "settings.welcomePlayed" to true,
            "settings.analytics" to false,
        )
        assertEquals(stored, prefs.values)

        // The app started again: as it was left.
        val again = AppSettings(prefs)
        assertEquals(ThemeChoice.CONTRAST, again.theme)
        assertEquals(1.3f, again.textScale)
        assertEquals(FontChoice.SYSTEM, again.font)
        assertTrue(again.reduceMotion)
        assertFalse(again.highlightWords)
        assertFalse(again.wholeLine)
        assertFalse(again.speakerNames)
        assertFalse(again.introSound)
        assertFalse(again.listeningSounds)
        assertFalse(again.listeningHaptics)
        assertEquals(1.75f, again.voiceSpeed)
        assertEquals(0.25f, again.musicVolume)
        assertEquals(AnswerTime.LONGEST, again.answerTime)
        assertEquals(MicAuto.NEVER, again.micAuto)
        assertEquals(MicPrimed.DECLINED, again.micPrimed)
        assertEquals(1, again.onboardingVersion)
        assertTrue(again.welcomePlayed)
        assertFalse(again.analytics)
    }

    @Test
    fun everyChoiceRoundTrips() {
        for (choice in ThemeChoice.entries) assertEquals(choice, roundTrip(AppSettings::theme, choice))
        for (choice in FontChoice.entries) assertEquals(choice, roundTrip(AppSettings::font, choice))
        for (choice in MicAuto.entries) assertEquals(choice, roundTrip(AppSettings::micAuto, choice))
        for (choice in MicPrimed.entries) assertEquals(choice, roundTrip(AppSettings::micPrimed, choice))
        for (choice in AnswerTime.entries) assertEquals(choice, roundTrip(AppSettings::answerTime, choice))
        for (step in AppSettings.VOICE_SPEEDS) assertEquals(step, roundTrip(AppSettings::voiceSpeed, step))
        for (step in AppSettings.MUSIC_VOLUMES) assertEquals(step, roundTrip(AppSettings::musicVolume, step))
        for (step in AppSettings.TEXT_SCALES) assertEquals(step, roundTrip(AppSettings::textScale, step))
    }

    @Test
    fun theChoicesAreDesignsStrings() {
        assertEquals(listOf("system", "light", "dark", "contrast"), ThemeChoice.entries.map { it.key })
        assertEquals(listOf("atkinson", "system"), FontChoice.entries.map { it.key })
        assertEquals(listOf("notWithScreenReader", "always", "never"), MicAuto.entries.map { it.key })
        assertEquals(listOf("unasked", "allowed", "declined"), MicPrimed.entries.map { it.key })
        assertEquals(listOf("normal", "longer", "longest"), AnswerTime.entries.map { it.key })
        assertEquals(listOf(6_000L, 10_000L, 15_000L), AnswerTime.entries.map { it.millis })
    }

    @Test
    fun aStoredValueTheAppDoesntKnowReadsAsTheDefault() {
        // Unknown choices (an older or newer app's), and values of the wrong type (a damaged file).
        val s = AppSettings(
            MemoryPrefs(
                "settings.theme" to "purple",
                "settings.font" to "comic",
                "settings.micAuto" to "sometimes",
                "settings.micPrimed" to 2,
                "settings.answerTime" to "forever",
                "settings.voiceSpeed" to "fast",
                "settings.musicVolume" to true,
                "settings.textScale" to 1.3,            // a Double, not a Float
                "settings.reduceMotion" to "true",
                "settings.highlightWords" to 0,
                "settings.analytics" to "no",
                "settings.onboardingVersion" to "1",
                "settings.welcomePlayed" to 1f,
            ),
        )
        assertEquals(ThemeChoice.SYSTEM, s.theme)
        assertEquals(FontChoice.ATKINSON, s.font)
        assertEquals(MicAuto.NOT_WITH_SCREEN_READER, s.micAuto)
        assertEquals(MicPrimed.UNASKED, s.micPrimed)
        assertEquals(AnswerTime.NORMAL, s.answerTime)
        assertEquals(1f, s.voiceSpeed)
        assertEquals(1f, s.musicVolume)
        assertEquals(1f, s.textScale)
        assertFalse(s.reduceMotion)
        assertTrue(s.highlightWords)
        assertTrue(s.analytics)
        assertEquals(0, s.onboardingVersion)
        assertFalse(s.welcomePlayed)
    }

    @Test
    fun numbersSnapToTheirSteps() {
        val prefs = MemoryPrefs()
        val s = AppSettings(prefs)
        fun speed(v: Float) = s.apply { voiceSpeed = v }.voiceSpeed
        fun music(v: Float) = s.apply { musicVolume = v }.musicVolume
        fun text(v: Float) = s.apply { textScale = v }.textScale

        assertEquals(1f, speed(1.1f))
        assertEquals(1.25f, speed(1.2f))
        assertEquals(1.5f, speed(1.55f))
        assertEquals(0.75f, speed(0.1f))
        assertEquals(2f, speed(9f))
        assertEquals(2f, speed(Float.POSITIVE_INFINITY))
        assertEquals(0.75f, speed(Float.NEGATIVE_INFINITY))
        assertEquals(1f, speed(Float.NaN))                  // not a number: the default
        assertEquals(0.25f, music(0.3f))
        assertEquals(1f, music(0.9f))
        assertEquals(0f, music(-2f))
        assertEquals(0.75f, music(0.7f))
        assertEquals(1.15f, text(1.2f))
        assertEquals(1.3f, text(2f))
        assertEquals(1f, text(0.5f))
        // What's stored is the step.
        assertEquals(1f, prefs.values["settings.voiceSpeed"])
        assertEquals(0.75f, prefs.values["settings.musicVolume"])
        assertEquals(1f, prefs.values["settings.textScale"])
    }

    @Test
    fun aStoredNumberBetweenStepsReadsAsTheNearest() {
        val s = AppSettings(
            MemoryPrefs("settings.voiceSpeed" to 1.6f, "settings.musicVolume" to 0.6f, "settings.textScale" to 1.29f),
        )
        assertEquals(1.5f, s.voiceSpeed)
        assertEquals(0.5f, s.musicVolume)
        assertEquals(1.3f, s.textScale)
    }

    @Test
    fun everySettingIsComposeState() {
        // A composable that reads a setting draws again when it changes: the read is of snapshot state.
        val s = AppSettings(MemoryPrefs())
        val all = listOf(
            AppSettings::theme, AppSettings::textScale, AppSettings::font, AppSettings::reduceMotion,
            AppSettings::highlightWords, AppSettings::wholeLine, AppSettings::speakerNames, AppSettings::introSound,
            AppSettings::listeningSounds, AppSettings::listeningHaptics, AppSettings::voiceSpeed,
            AppSettings::musicVolume, AppSettings::answerTime, AppSettings::micAuto, AppSettings::micPrimed,
            AppSettings::onboardingVersion, AppSettings::welcomePlayed, AppSettings::analytics,
        )
        assertEquals(18, all.size)
        for (setting in all) {
            val reads = mutableListOf<Any>()
            Snapshot.observe(readObserver = { reads += it }) { setting.get(s) }
            assertEquals(setting.name, 1, reads.size)
        }
    }

    /** [value] set, then read by the app started again. */
    private fun <T> roundTrip(setting: KMutableProperty1<AppSettings, T>, value: T): T {
        val prefs = MemoryPrefs()
        setting.set(AppSettings(prefs), value)
        return setting.get(AppSettings(prefs))
    }
}
