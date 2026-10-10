package com.epicaudiogames.app

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import kotlin.math.abs
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

/**
 * The player's settings (docs/DESIGN.md's table, the same keys as iOS's App/AppSettings.swift), each Compose state:
 * read once from [prefs], and stored again whenever it's set. A value stored that isn't one of the setting's (another
 * type, a choice this app doesn't know) reads as its default; numbers snap to the nearest of their steps.
 *
 * `settings.account.*` is kept for the sign-in to come: nothing here uses it.
 */
class AppSettings(private val prefs: Prefs) {
    // Sound and voice. The voice speed is the whole turn's (voice, music, pauses); earcons and the sting stay at 1x.
    var voiceSpeed by number(VOICE_SPEED, 1f, VOICE_SPEEDS)
    var introSound by flag(INTRO_SOUND, true)            // off also skips the intro screen
    var listeningSounds by flag(LISTENING_SOUNDS, true)
    var listeningHaptics by flag(LISTENING_HAPTICS, true)
    var musicVolume by number(MUSIC_VOLUME, 1f, MUSIC_VOLUMES)
    var answerTime by choice(ANSWER_TIME, AnswerTime.NORMAL)

    // Microphone.
    var micAuto by choice(MIC_AUTO, MicAuto.NOT_WITH_SCREEN_READER)
    var micPrimed by choice(MIC_PRIMED, MicPrimed.UNASKED)

    // Appearance. Reduce motion is in effect when the phone's or this is on.
    var theme by choice(THEME, ThemeChoice.SYSTEM)
    var textScale by number(TEXT_SCALE, 1f, TEXT_SCALES)
    var font by choice(FONT, FontChoice.ATKINSON)
    var reduceMotion by flag(REDUCE_MOTION, false)

    // Transcript. Speaker names are only hidden from sight: the screen reader still says them.
    var highlightWords by flag(HIGHLIGHT_WORDS, true)
    var wholeLine by flag(WHOLE_LINE, true)
    var speakerNames by flag(SPEAKER_NAMES, true)

    // Privacy.
    var analytics by flag(ANALYTICS, true)

    // The first run: onboarding is 1 once finished or skipped; the welcome plays by itself only once.
    var onboardingVersion by integer(ONBOARDING_VERSION, 0)
    var welcomePlayed by flag(WELCOME_PLAYED, false)

    private fun flag(key: String, default: Boolean) =
        Setting(prefs.boolean(key) ?: default, { it }) { prefs.put(key, it) }

    private fun integer(key: String, default: Int) =
        Setting(prefs.int(key) ?: default, { it }) { prefs.put(key, it) }

    private fun number(key: String, default: Float, steps: List<Float>) =
        Setting(prefs.float(key) ?: default, { snap(it, steps, default) }) { prefs.put(key, it) }

    private inline fun <reified E> choice(key: String, default: E): Setting<E> where E : Enum<E>, E : SettingChoice {
        val stored = prefs.string(key)
        return Setting(enumValues<E>().firstOrNull { it.key == stored } ?: default, { it }) { prefs.put(key, it.key) }
    }

    /** A setting: Compose state holding its value ([clean]ed: snapped to its steps), stored again as it's set. */
    private class Setting<T>(
        initial: T,
        private val clean: (T) -> T,
        private val store: (T) -> Unit,
    ) : ReadWriteProperty<AppSettings, T> {
        private val state = mutableStateOf(clean(initial))

        override fun getValue(thisRef: AppSettings, property: KProperty<*>): T = state.value

        override fun setValue(thisRef: AppSettings, property: KProperty<*>, value: T) {
            val v = clean(value)
            state.value = v
            store(v)
        }
    }

    companion object {
        const val THEME = "settings.theme"
        const val TEXT_SCALE = "settings.textScale"
        const val FONT = "settings.font"
        const val REDUCE_MOTION = "settings.reduceMotion"
        const val HIGHLIGHT_WORDS = "settings.highlightWords"
        const val WHOLE_LINE = "settings.wholeLine"
        const val SPEAKER_NAMES = "settings.speakerNames"
        const val INTRO_SOUND = "settings.introSound"
        const val LISTENING_SOUNDS = "settings.listeningSounds"
        const val LISTENING_HAPTICS = "settings.listeningHaptics"
        const val VOICE_SPEED = "settings.voiceSpeed"
        const val MUSIC_VOLUME = "settings.musicVolume"
        const val ANSWER_TIME = "settings.answerTime"
        const val MIC_AUTO = "settings.micAuto"
        const val MIC_PRIMED = "settings.micPrimed"
        const val ONBOARDING_VERSION = "settings.onboardingVersion"
        const val WELCOME_PLAYED = "settings.welcomePlayed"
        const val ANALYTICS = "settings.analytics"

        /** Voice speed's steps (Slower / Faster), as "1.25 times". */
        val VOICE_SPEEDS = listOf(0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f)
        /** Music volume's steps: off, 25, 50, 75 and 100%. */
        val MUSIC_VOLUMES = listOf(0f, 0.25f, 0.5f, 0.75f, 1f)
        /** Text size's steps: Standard, Large and Larger, on top of the phone's own font scale. */
        val TEXT_SCALES = listOf(1f, 1.15f, 1.3f)

        /** The step nearest [value] (beyond the ends, the end); [default] when it isn't a number. */
        private fun snap(value: Float, steps: List<Float>, default: Float): Float {
            if (value.isNaN()) return default
            val v = value.coerceIn(steps.first(), steps.last())
            return steps.minBy { abs(it - v) }
        }
    }
}

/** A setting's choices (the enums below), each stored as its [key]: docs/DESIGN.md's string for it. */
interface SettingChoice {
    val key: String
}

/** Settings › Appearance › Theme. Match my phone (light or dark as the phone is), Light, Dark or High contrast. */
enum class ThemeChoice(override val key: String) : SettingChoice {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark"),
    CONTRAST("contrast"),
}

/** Settings › Appearance › Font: Atkinson Hyperlegible Next, or the phone's own font at the same sizes. */
enum class FontChoice(override val key: String) : SettingChoice {
    ATKINSON("atkinson"),
    SYSTEM("system"),
}

/** Settings › Microphone › Open the microphone by itself (see [listensByItself]). */
enum class MicAuto(override val key: String) : SettingChoice {
    NOT_WITH_SCREEN_READER("notWithScreenReader"),
    ALWAYS("always"),
    NEVER("never"),
}

/**
 * What the player said on onboarding's "Answer out loud" page. A game asks for the mic as it opens unless it was
 * declined there; the mic button always asks.
 */
enum class MicPrimed(override val key: String) : SettingChoice {
    UNASKED("unasked"),
    ALLOWED("allowed"),
    DECLINED("declined"),
}

/** Settings › Sound and voice › Time to answer: how long the game waits for an answer before it's a silence. */
enum class AnswerTime(override val key: String, val millis: Long) : SettingChoice {
    NORMAL("normal", 6_000),
    LONGER("longer", 10_000),
    LONGEST("longest", 15_000),
}

/**
 * Where the settings are kept: [SharedPrefs] on the phone, [MemoryPrefs] in tests. A value that isn't there, or is of
 * another type, reads as null.
 */
interface Prefs {
    fun string(key: String): String?
    fun boolean(key: String): Boolean?
    fun float(key: String): Float?
    fun int(key: String): Int?
    fun put(key: String, value: String)
    fun put(key: String, value: Boolean)
    fun put(key: String, value: Float)
    fun put(key: String, value: Int)
}

/**
 * The settings on the phone: SharedPreferences "settings". Read at once (not a flow), so the theme and the intro are
 * known before the first frame, as Saves (Library.kt) keeps the games' places; written in the background. Backed up
 * with the saves, and nothing else (res/xml/backup_rules.xml says why): a new phone gets the player's theme, text
 * size and voice back, and Share usage data stays off if it was turned off. The usage data's random ID isn't here:
 * it's in no_backup (analytics/InstallId.kt).
 */
class SharedPrefs(context: Context) : Prefs {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    override fun string(key: String) = read(key) { prefs.getString(key, null) }
    override fun boolean(key: String) = read(key) { prefs.getBoolean(key, false) }
    override fun float(key: String) = read(key) { prefs.getFloat(key, 0f) }
    override fun int(key: String) = read(key) { prefs.getInt(key, 0) }
    override fun put(key: String, value: String) = prefs.edit().putString(key, value).apply()
    override fun put(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    override fun put(key: String, value: Float) = prefs.edit().putFloat(key, value).apply()
    override fun put(key: String, value: Int) = prefs.edit().putInt(key, value).apply()

    /**
     * Every setting stored forgotten, so each reads as its default (a debug build's EpicReset, before the app's model
     * reads them: a run that changed one doesn't leave it for the next).
     */
    fun clear() = prefs.edit().clear().apply()

    /** The value under [key], if it's there and of the type asked for (SharedPreferences throws if it isn't). */
    private inline fun <T> read(key: String, get: () -> T): T? =
        if (prefs.contains(key)) runCatching(get).getOrNull() else null
}

/** Settings kept in memory, for tests: [values] is what's stored, of any type (as a damaged file could have). */
class MemoryPrefs(vararg stored: Pair<String, Any>) : Prefs {
    val values = mutableMapOf(*stored)

    override fun string(key: String) = values[key] as? String
    override fun boolean(key: String) = values[key] as? Boolean
    override fun float(key: String) = values[key] as? Float
    override fun int(key: String) = values[key] as? Int
    override fun put(key: String, value: String) { values[key] = value }
    override fun put(key: String, value: Boolean) { values[key] = value }
    override fun put(key: String, value: Float) { values[key] = value }
    override fun put(key: String, value: Int) { values[key] = value }
}
