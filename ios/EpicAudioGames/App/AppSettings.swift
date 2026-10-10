// AppSettings.kt: the player's settings, kept on the phone (UserDefaults here, SharedPreferences there).

import Foundation
import Observation

/**
 * The player's settings (docs/DESIGN.md's table, the same keys and values as Android's AppSettings.kt), each observed:
 * read once from [defaults], and stored again whenever it's set. A value stored that isn't one of the setting's
 * (another type, a choice this app doesn't know) reads as its default; numbers snap to the nearest of their steps.
 *
 * UserDefaults.standard looks in the launch arguments first (its argument domain), so `-settings.theme contrast` gives
 * a setting for that launch without storing it (the UI tests, the screenshots). Launch arguments come as strings: a
 * flag can also be "YES" or "NO" ("true", "false", "1", "0"), and a number "1.25". Android reads only typed values.
 *
 * `settings.account.*` is kept for the sign-in to come: nothing here uses it.
 */
@Observable
final class AppSettings {
    // Sound and voice. The voice speed is the whole turn's (voice, music, pauses); earcons and the sting stay at 1x.
    var voiceSpeed: Double {
        get { voiceSpeedValue }
        set { voiceSpeedValue = save(Self.snap(newValue, to: Self.voiceSpeeds, default: 1), .voiceSpeed) }
    }
    /// Off also skips the intro screen.
    var introSound: Bool {
        get { introSoundValue }
        set { introSoundValue = save(newValue, .introSound) }
    }
    var listeningSounds: Bool {
        get { listeningSoundsValue }
        set { listeningSoundsValue = save(newValue, .listeningSounds) }
    }
    var listeningHaptics: Bool {
        get { listeningHapticsValue }
        set { listeningHapticsValue = save(newValue, .listeningHaptics) }
    }
    var musicVolume: Double {
        get { musicVolumeValue }
        set { musicVolumeValue = save(Self.snap(newValue, to: Self.musicVolumes, default: 1), .musicVolume) }
    }
    var answerTime: AnswerTime {
        get { answerTimeValue }
        set { answerTimeValue = save(newValue, .answerTime) }
    }

    // Microphone.
    var micAuto: MicAuto {
        get { micAutoValue }
        set { micAutoValue = save(newValue, .micAuto) }
    }
    var micPrimed: MicPrimed {
        get { micPrimedValue }
        set { micPrimedValue = save(newValue, .micPrimed) }
    }

    // Appearance. Reduce motion is in effect when the phone's or this is on.
    var theme: ThemeChoice {
        get { themeValue }
        set { themeValue = save(newValue, .theme) }
    }
    var textScale: Double {
        get { textScaleValue }
        set { textScaleValue = save(Self.snap(newValue, to: Self.textScales, default: 1), .textScale) }
    }
    var font: FontChoice {
        get { fontValue }
        set { fontValue = save(newValue, .font) }
    }
    var reduceMotion: Bool {
        get { reduceMotionValue }
        set { reduceMotionValue = save(newValue, .reduceMotion) }
    }

    // Transcript. Speaker names are only hidden from sight: VoiceOver still says them.
    var highlightWords: Bool {
        get { highlightWordsValue }
        set { highlightWordsValue = save(newValue, .highlightWords) }
    }
    var wholeLine: Bool {
        get { wholeLineValue }
        set { wholeLineValue = save(newValue, .wholeLine) }
    }
    var speakerNames: Bool {
        get { speakerNamesValue }
        set { speakerNamesValue = save(newValue, .speakerNames) }
    }

    // Privacy.
    var analytics: Bool {
        get { analyticsValue }
        set { analyticsValue = save(newValue, .analytics) }
    }

    // The first run: onboarding is 1 once finished or skipped; the welcome plays by itself only once.
    var onboardingVersion: Int {
        get { onboardingVersionValue }
        set { onboardingVersionValue = save(newValue, .onboardingVersion) }
    }
    var welcomePlayed: Bool {
        get { welcomePlayedValue }
        set { welcomePlayedValue = save(newValue, .welcomePlayed) }
    }

    /// Voice speed's steps (Slower / Faster), as "1.25 times".
    static let voiceSpeeds: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    /// Music volume's steps: off, 25, 50, 75 and 100%.
    static let musicVolumes: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// Text size's steps: Standard, Large and Larger, on top of the phone's own text size (Dynamic Type).
    static let textScales: [Double] = [1, 1.15, 1.3]

    /// docs/DESIGN.md's keys: the same strings as Android's (AppSettings.THEME and the rest).
    enum Key: String, CaseIterable {
        case theme = "settings.theme"
        case textScale = "settings.textScale"
        case font = "settings.font"
        case reduceMotion = "settings.reduceMotion"
        case highlightWords = "settings.highlightWords"
        case wholeLine = "settings.wholeLine"
        case speakerNames = "settings.speakerNames"
        case introSound = "settings.introSound"
        case listeningSounds = "settings.listeningSounds"
        case listeningHaptics = "settings.listeningHaptics"
        case voiceSpeed = "settings.voiceSpeed"
        case musicVolume = "settings.musicVolume"
        case answerTime = "settings.answerTime"
        case micAuto = "settings.micAuto"
        case micPrimed = "settings.micPrimed"
        case onboardingVersion = "settings.onboardingVersion"
        case welcomePlayed = "settings.welcomePlayed"
        case analytics = "settings.analytics"
    }

    /// Where the settings are kept: UserDefaults.standard, or (tests) a suite of their own.
    @ObservationIgnored private let defaults: UserDefaults

    // What the settings above get and set. @Observable watches stored properties, each on its own; every setting is
    // computed over one of these, so that setting it can snap it and store it too.
    private var voiceSpeedValue: Double
    private var introSoundValue: Bool
    private var listeningSoundsValue: Bool
    private var listeningHapticsValue: Bool
    private var musicVolumeValue: Double
    private var answerTimeValue: AnswerTime
    private var micAutoValue: MicAuto
    private var micPrimedValue: MicPrimed
    private var themeValue: ThemeChoice
    private var textScaleValue: Double
    private var fontValue: FontChoice
    private var reduceMotionValue: Bool
    private var highlightWordsValue: Bool
    private var wholeLineValue: Bool
    private var speakerNamesValue: Bool
    private var analyticsValue: Bool
    private var onboardingVersionValue: Int
    private var welcomePlayedValue: Bool

    /// The settings as [defaults] has them, and each one's default where it has none (nothing is stored until it's set).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceSpeedValue = Self.snap(Self.number(defaults, .voiceSpeed), to: Self.voiceSpeeds, default: 1)
        introSoundValue = Self.flag(defaults, .introSound) ?? true
        listeningSoundsValue = Self.flag(defaults, .listeningSounds) ?? true
        listeningHapticsValue = Self.flag(defaults, .listeningHaptics) ?? true
        musicVolumeValue = Self.snap(Self.number(defaults, .musicVolume), to: Self.musicVolumes, default: 1)
        answerTimeValue = Self.choice(defaults, .answerTime) ?? .normal
        micAutoValue = Self.choice(defaults, .micAuto) ?? .notWithScreenReader
        micPrimedValue = Self.choice(defaults, .micPrimed) ?? .unasked
        themeValue = Self.choice(defaults, .theme) ?? .system
        textScaleValue = Self.snap(Self.number(defaults, .textScale), to: Self.textScales, default: 1)
        fontValue = Self.choice(defaults, .font) ?? .atkinson
        reduceMotionValue = Self.flag(defaults, .reduceMotion) ?? false
        highlightWordsValue = Self.flag(defaults, .highlightWords) ?? true
        wholeLineValue = Self.flag(defaults, .wholeLine) ?? true
        speakerNamesValue = Self.flag(defaults, .speakerNames) ?? true
        analyticsValue = Self.flag(defaults, .analytics) ?? true
        onboardingVersionValue = Self.integer(defaults, .onboardingVersion) ?? 0
        welcomePlayedValue = Self.flag(defaults, .welcomePlayed) ?? false
    }

    // ----- Storing -----

    /// [value], stored under [key].
    private func save(_ value: Bool, _ key: Key) -> Bool {
        defaults.set(value, forKey: key.rawValue)
        return value
    }

    private func save(_ value: Int, _ key: Key) -> Int {
        defaults.set(value, forKey: key.rawValue)
        return value
    }

    private func save(_ value: Double, _ key: Key) -> Double {
        defaults.set(value, forKey: key.rawValue)
        return value
    }

    /// A choice is stored as its string, as docs/DESIGN.md writes it ("notWithScreenReader").
    private func save<C: RawRepresentable>(_ value: C, _ key: Key) -> C where C.RawValue == String {
        defaults.set(value.rawValue, forKey: key.rawValue)
        return value
    }

    // ----- Reading -----

    /// A flag stored under [key]: true or false, or (a launch argument) "YES", "true" or "1", "NO", "false" or "0".
    private static func flag(_ defaults: UserDefaults, _ key: Key) -> Bool? {
        guard let value = defaults.object(forKey: key.rawValue) else { return nil }
        if isFlag(value) { return value as? Bool }
        guard let text = value as? String else { return nil }
        switch text.lowercased() {
        case "yes", "true", "1": return true
        case "no", "false", "0": return false
        default: return nil
        }
    }

    /// A number stored under [key], or (a launch argument) one written out, as "1.25". A flag isn't one.
    private static func number(_ defaults: UserDefaults, _ key: Key) -> Double? {
        guard let value = defaults.object(forKey: key.rawValue), !isFlag(value) else { return nil }
        if let text = value as? String { return Double(text) }
        return (value as? NSNumber)?.doubleValue
    }

    /// A whole number stored under [key], or (a launch argument) one written out. A flag isn't one.
    private static func integer(_ defaults: UserDefaults, _ key: Key) -> Int? {
        guard let value = defaults.object(forKey: key.rawValue), !isFlag(value) else { return nil }
        if let text = value as? String { return Int(text) }
        return value as? Int
    }

    /// A choice stored under [key], by its string; another string (an older or newer app's choice) is none.
    private static func choice<C: RawRepresentable>(_ defaults: UserDefaults, _ key: Key) -> C?
    where C.RawValue == String {
        (defaults.object(forKey: key.rawValue) as? String).flatMap { C(rawValue: $0) }
    }

    /// Whether [value] is a flag: UserDefaults gives flags as NSNumber too, and true would pass for the number 1.
    private static func isFlag(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    /// The step nearest [value] (beyond the ends, the end); [fallback] when there's no number (none, or NaN).
    private static func snap(_ value: Double?, to steps: [Double], default fallback: Double) -> Double {
        guard let value, !value.isNaN, let first = steps.first, let last = steps.last else { return fallback }
        let v = min(max(value, first), last)
        return steps.min { abs($0 - v) < abs($1 - v) } ?? fallback
    }
}

/// Settings › Appearance › Theme: Match my phone (light or dark as the phone is), Light, Dark or High contrast.
enum ThemeChoice: String, CaseIterable {
    case system, light, dark, contrast
}

/// Settings › Appearance › Font: Atkinson Hyperlegible Next, or the phone's own font (SF) at the same sizes.
enum FontChoice: String, CaseIterable {
    case atkinson, system
}

/// Settings › Microphone › Open the microphone by itself (see MicPolicy, in A11y.swift).
enum MicAuto: String, CaseIterable {
    case notWithScreenReader, always, never
}

/**
 * What the player said on onboarding's "Answer out loud" page. A game asks for the mic as it opens unless it was
 * declined there; the Talk button always asks.
 */
enum MicPrimed: String, CaseIterable {
    case unasked, allowed, declined
}

/// Settings › Sound and voice › Time to answer: how long the game waits for an answer before it's a silence.
enum AnswerTime: String, CaseIterable {
    case normal, longer, longest

    /// 6, 10 or 15 seconds: the Endpointer's no-speech time (Android's AnswerTime.millis).
    var duration: Duration {
        switch self {
        case .normal: .seconds(6)
        case .longer: .seconds(10)
        case .longest: .seconds(15)
        }
    }

    /**
     * How long the words must stop before the answer is over: the Endpointer's 1.2 seconds, or 2 with Longer and
     * Longest, for a player who pauses mid-answer (GameController.kt asks Android's recogniser for 2 s then too).
     */
    var settle: Duration {
        switch self {
        case .normal: .milliseconds(1200)
        case .longer, .longest: .seconds(2)
        }
    }
}
