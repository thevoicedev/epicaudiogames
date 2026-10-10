// AppSettingsTest.kt: the settings' defaults, how they're stored, what a value the app doesn't know reads as, and the
// numbers' steps.

import Foundation
import Observation
import Testing
@testable import EpicAudioGames

/// Counts changes. withObservationTracking's onChange is @Sendable; it's called on the main actor, as a setting is set.
private final class Changes: @unchecked Sendable {
    var count = 0
}

/**
 * The settings (docs/DESIGN.md, Settings keys): their defaults, the keys and values they're stored as, what a stored
 * value the app doesn't know reads as, launch arguments, and the numbers' steps. Each test has a UserDefaults suite of
 * its own, so the app's settings are left alone.
 */
@MainActor
struct AppSettingsTests {
    let name: String
    let defaults: UserDefaults

    init() throws {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        self.name = name
        defaults = try #require(UserDefaults(suiteName: name))
    }

    /// The test's UserDefaults removed again (each test does it as it ends).
    private func clear() {
        defaults.removePersistentDomain(forName: name)
    }

    /// What the suite has stored, by key.
    private func stored() -> [String: Any] {
        defaults.persistentDomain(forName: name) ?? [:]
    }

    /// A stored value with its type ("Bool true", "Double 1.75", "Int 1", "String contrast"): UserDefaults gives flags
    /// and numbers alike as NSNumber.
    private func typed(_ value: Any) -> String {
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return "Bool \((value as? Bool) == true)" }
        if let number = value as? NSNumber {
            return CFNumberIsFloatType(number as CFNumber) ? "Double \(number.doubleValue)" : "Int \(number.intValue)"
        }
        if let text = value as? String { return "String \(text)" }
        return "\(type(of: value)) \(value)"
    }

    @Test func aNewPhoneHasTheDefaults() {
        defer { clear() }
        let s = AppSettings(defaults: defaults)
        #expect(s.theme == .system)
        #expect(s.textScale == 1)
        #expect(s.font == .atkinson)
        #expect(!s.reduceMotion)
        #expect(s.highlightWords)
        #expect(s.wholeLine)
        #expect(s.speakerNames)
        #expect(s.introSound)
        #expect(s.listeningSounds)
        #expect(s.listeningHaptics)
        #expect(s.voiceSpeed == 1)
        #expect(s.musicVolume == 1)
        #expect(s.answerTime == .normal)
        #expect(s.micAuto == .notWithScreenReader)
        #expect(s.micPrimed == .unasked)
        #expect(s.onboardingVersion == 0)
        #expect(!s.welcomePlayed)
        #expect(s.analytics)
    }

    @Test func nothingIsStoredUntilItIsSet() {
        defer { clear() }
        _ = AppSettings(defaults: defaults)
        #expect(stored().isEmpty)
    }

    @Test func whatIsSetIsStoredUnderItsKeyAndReadBack() {
        defer { clear() }
        let s = AppSettings(defaults: defaults)
        s.theme = .contrast
        s.textScale = 1.3
        s.font = .system
        s.reduceMotion = true
        s.highlightWords = false
        s.wholeLine = false
        s.speakerNames = false
        s.introSound = false
        s.listeningSounds = false
        s.listeningHaptics = false
        s.voiceSpeed = 1.75
        s.musicVolume = 0.25
        s.answerTime = .longest
        s.micAuto = .never
        s.micPrimed = .declined
        s.onboardingVersion = 1
        s.welcomePlayed = true
        s.analytics = false
        // The same strings and types as Android's SharedPreferences.
        let expected = [
            "settings.theme": "String contrast",
            "settings.textScale": "Double 1.3",
            "settings.font": "String system",
            "settings.reduceMotion": "Bool true",
            "settings.highlightWords": "Bool false",
            "settings.wholeLine": "Bool false",
            "settings.speakerNames": "Bool false",
            "settings.introSound": "Bool false",
            "settings.listeningSounds": "Bool false",
            "settings.listeningHaptics": "Bool false",
            "settings.voiceSpeed": "Double 1.75",
            "settings.musicVolume": "Double 0.25",
            "settings.answerTime": "String longest",
            "settings.micAuto": "String never",
            "settings.micPrimed": "String declined",
            "settings.onboardingVersion": "Int 1",
            "settings.welcomePlayed": "Bool true",
            "settings.analytics": "Bool false",
        ]
        #expect(stored().mapValues { typed($0) } == expected)
        #expect(Set(AppSettings.Key.allCases.map { $0.rawValue }) == Set(expected.keys))

        // The app started again: as it was left.
        let again = AppSettings(defaults: defaults)
        #expect(again.theme == .contrast)
        #expect(again.textScale == 1.3)
        #expect(again.font == .system)
        #expect(again.reduceMotion)
        #expect(!again.highlightWords)
        #expect(!again.wholeLine)
        #expect(!again.speakerNames)
        #expect(!again.introSound)
        #expect(!again.listeningSounds)
        #expect(!again.listeningHaptics)
        #expect(again.voiceSpeed == 1.75)
        #expect(again.musicVolume == 0.25)
        #expect(again.answerTime == .longest)
        #expect(again.micAuto == .never)
        #expect(again.micPrimed == .declined)
        #expect(again.onboardingVersion == 1)
        #expect(again.welcomePlayed)
        #expect(!again.analytics)
    }

    @Test func everyChoiceRoundTrips() {
        defer { clear() }
        // Each set, then read by the app started again.
        for choice in ThemeChoice.allCases {
            AppSettings(defaults: defaults).theme = choice
            #expect(AppSettings(defaults: defaults).theme == choice)
        }
        for choice in FontChoice.allCases {
            AppSettings(defaults: defaults).font = choice
            #expect(AppSettings(defaults: defaults).font == choice)
        }
        for choice in MicAuto.allCases {
            AppSettings(defaults: defaults).micAuto = choice
            #expect(AppSettings(defaults: defaults).micAuto == choice)
        }
        for choice in MicPrimed.allCases {
            AppSettings(defaults: defaults).micPrimed = choice
            #expect(AppSettings(defaults: defaults).micPrimed == choice)
        }
        for choice in AnswerTime.allCases {
            AppSettings(defaults: defaults).answerTime = choice
            #expect(AppSettings(defaults: defaults).answerTime == choice)
        }
        for step in AppSettings.voiceSpeeds {
            AppSettings(defaults: defaults).voiceSpeed = step
            #expect(AppSettings(defaults: defaults).voiceSpeed == step)
        }
        for step in AppSettings.musicVolumes {
            AppSettings(defaults: defaults).musicVolume = step
            #expect(AppSettings(defaults: defaults).musicVolume == step)
        }
        for step in AppSettings.textScales {
            AppSettings(defaults: defaults).textScale = step
            #expect(AppSettings(defaults: defaults).textScale == step)
        }
    }

    @Test func theKeysAndChoicesAreDesignsStrings() {
        #expect(AppSettings.Key.allCases.map { $0.rawValue } == [
            "settings.theme", "settings.textScale", "settings.font", "settings.reduceMotion", "settings.highlightWords",
            "settings.wholeLine", "settings.speakerNames", "settings.introSound", "settings.listeningSounds",
            "settings.listeningHaptics", "settings.voiceSpeed", "settings.musicVolume", "settings.answerTime",
            "settings.micAuto", "settings.micPrimed", "settings.onboardingVersion", "settings.welcomePlayed",
            "settings.analytics",
        ])
        #expect(ThemeChoice.allCases.map { $0.rawValue } == ["system", "light", "dark", "contrast"])
        #expect(FontChoice.allCases.map { $0.rawValue } == ["atkinson", "system"])
        #expect(MicAuto.allCases.map { $0.rawValue } == ["notWithScreenReader", "always", "never"])
        #expect(MicPrimed.allCases.map { $0.rawValue } == ["unasked", "allowed", "declined"])
        #expect(AnswerTime.allCases.map { $0.rawValue } == ["normal", "longer", "longest"])
        #expect(AnswerTime.allCases.map { $0.duration } == [Duration.seconds(6), .seconds(10), .seconds(15)])
        #expect(AppSettings.voiceSpeeds == [0.75, 1, 1.25, 1.5, 1.75, 2])
        #expect(AppSettings.musicVolumes == [0, 0.25, 0.5, 0.75, 1])
        #expect(AppSettings.textScales == [1, 1.15, 1.3])
    }

    @Test func aStoredValueTheAppDoesntKnowReadsAsTheDefault() {
        defer { clear() }
        // Unknown choices (an older or newer app's), and values of the wrong type (a damaged file).
        let damaged: [String: Any] = [
            "settings.theme": "purple",
            "settings.font": "comic",
            "settings.micAuto": "sometimes",
            "settings.micPrimed": 2,
            "settings.answerTime": "forever",
            "settings.voiceSpeed": "fast",
            "settings.musicVolume": true,           // a flag isn't a number
            "settings.textScale": Data([1, 3]),
            "settings.reduceMotion": "maybe",
            "settings.highlightWords": 0,           // nor is a number a flag
            "settings.wholeLine": [true],
            "settings.speakerNames": Date(),
            "settings.introSound": "",
            "settings.listeningSounds": 1.0,
            "settings.listeningHaptics": ["on": true],
            "settings.analytics": "no thanks",
            "settings.onboardingVersion": 1.5,
            "settings.welcomePlayed": Float(1),
        ]
        for (key, value) in damaged { defaults.set(value, forKey: key) }
        let s = AppSettings(defaults: defaults)
        #expect(s.theme == .system)
        #expect(s.font == .atkinson)
        #expect(s.micAuto == .notWithScreenReader)
        #expect(s.micPrimed == .unasked)
        #expect(s.answerTime == .normal)
        #expect(s.voiceSpeed == 1)
        #expect(s.musicVolume == 1)
        #expect(s.textScale == 1)
        #expect(!s.reduceMotion)
        #expect(s.highlightWords)
        #expect(s.wholeLine)
        #expect(s.speakerNames)
        #expect(s.introSound)
        #expect(s.listeningSounds)
        #expect(s.listeningHaptics)
        #expect(s.analytics)
        #expect(s.onboardingVersion == 0)
        #expect(!s.welcomePlayed)
    }

    /// A launch argument (`-settings.reduceMotion YES`) comes from UserDefaults' argument domain as a string, as these
    /// do: flags and numbers are read from strings too.
    @Test func launchArgumentsAreReadFromTheirStrings() {
        defer { clear() }
        let given = [
            "settings.theme": "contrast",
            "settings.textScale": "1.3",
            "settings.font": "system",
            "settings.reduceMotion": "YES",
            "settings.highlightWords": "NO",
            "settings.wholeLine": "false",
            "settings.speakerNames": "0",
            "settings.introSound": "no",
            "settings.listeningSounds": "False",
            "settings.listeningHaptics": "No",
            "settings.voiceSpeed": "1.25",
            "settings.musicVolume": "0.6",
            "settings.answerTime": "longer",
            "settings.micAuto": "always",
            "settings.micPrimed": "allowed",
            "settings.onboardingVersion": "1",
            "settings.welcomePlayed": "true",
            "settings.analytics": "NO",
        ]
        for (key, value) in given { defaults.set(value, forKey: key) }
        let s = AppSettings(defaults: defaults)
        #expect(s.theme == .contrast)
        #expect(s.textScale == 1.3)
        #expect(s.font == .system)
        #expect(s.reduceMotion)
        #expect(!s.highlightWords)
        #expect(!s.wholeLine)
        #expect(!s.speakerNames)
        #expect(!s.introSound)
        #expect(!s.listeningSounds)
        #expect(!s.listeningHaptics)
        #expect(s.voiceSpeed == 1.25)
        #expect(s.musicVolume == 0.5)           // snapped, as a stored number is
        #expect(s.answerTime == .longer)
        #expect(s.micAuto == .always)
        #expect(s.micPrimed == .allowed)
        #expect(s.onboardingVersion == 1)
        #expect(s.welcomePlayed)
        #expect(!s.analytics)
        // Each way of writing a flag.
        for (text, flag) in [("YES", true), ("yes", true), ("true", true), ("TRUE", true), ("1", true),
                             ("NO", false), ("no", false), ("false", false), ("0", false)] {
            defaults.set(text, forKey: "settings.reduceMotion")
            #expect(AppSettings(defaults: defaults).reduceMotion == flag, "\(text)")
        }
    }

    @Test func numbersSnapToTheirSteps() {
        defer { clear() }
        let s = AppSettings(defaults: defaults)
        func speed(_ v: Double) -> Double {
            s.voiceSpeed = v
            return s.voiceSpeed
        }
        func music(_ v: Double) -> Double {
            s.musicVolume = v
            return s.musicVolume
        }
        func text(_ v: Double) -> Double {
            s.textScale = v
            return s.textScale
        }
        #expect(speed(1.1) == 1)
        #expect(speed(1.2) == 1.25)
        #expect(speed(1.55) == 1.5)
        #expect(speed(0.1) == 0.75)
        #expect(speed(9) == 2)
        #expect(speed(Double.infinity) == 2)
        #expect(speed(-Double.infinity) == 0.75)
        #expect(speed(Double.nan) == 1)         // not a number: the default
        #expect(music(0.3) == 0.25)
        #expect(music(0.9) == 1)
        #expect(music(-2) == 0)
        #expect(music(0.7) == 0.75)
        #expect(text(1.2) == 1.15)
        #expect(text(2) == 1.3)
        #expect(text(0.5) == 1)
        // What's stored is the step.
        #expect(stored()["settings.voiceSpeed"] as? Double == 1)
        #expect(stored()["settings.musicVolume"] as? Double == 0.75)
        #expect(stored()["settings.textScale"] as? Double == 1)
    }

    @Test func aStoredNumberBetweenStepsReadsAsTheNearest() {
        defer { clear() }
        defaults.set(1.6, forKey: "settings.voiceSpeed")
        defaults.set(0.6, forKey: "settings.musicVolume")
        defaults.set(1.29, forKey: "settings.textScale")
        let s = AppSettings(defaults: defaults)
        #expect(s.voiceSpeed == 1.5)
        #expect(s.musicVolume == 0.5)
        #expect(s.textScale == 1.3)
    }

    /// A view that reads a setting is drawn again when it changes, and only then: each setting is observed on its own.
    @Test func eachSettingIsObservedOnItsOwn() throws {
        // Each setting read, and set from its default to something else.
        let all: [(name: String, read: (AppSettings) -> Void, change: (AppSettings) -> Void)] = [
            ("theme", { _ = $0.theme }, { $0.theme = .dark }),
            ("textScale", { _ = $0.textScale }, { $0.textScale = 1.15 }),
            ("font", { _ = $0.font }, { $0.font = .system }),
            ("reduceMotion", { _ = $0.reduceMotion }, { $0.reduceMotion = true }),
            ("highlightWords", { _ = $0.highlightWords }, { $0.highlightWords = false }),
            ("wholeLine", { _ = $0.wholeLine }, { $0.wholeLine = false }),
            ("speakerNames", { _ = $0.speakerNames }, { $0.speakerNames = false }),
            ("introSound", { _ = $0.introSound }, { $0.introSound = false }),
            ("listeningSounds", { _ = $0.listeningSounds }, { $0.listeningSounds = false }),
            ("listeningHaptics", { _ = $0.listeningHaptics }, { $0.listeningHaptics = false }),
            ("voiceSpeed", { _ = $0.voiceSpeed }, { $0.voiceSpeed = 2 }),
            ("musicVolume", { _ = $0.musicVolume }, { $0.musicVolume = 0 }),
            ("answerTime", { _ = $0.answerTime }, { $0.answerTime = .longer }),
            ("micAuto", { _ = $0.micAuto }, { $0.micAuto = .always }),
            ("micPrimed", { _ = $0.micPrimed }, { $0.micPrimed = .allowed }),
            ("onboardingVersion", { _ = $0.onboardingVersion }, { $0.onboardingVersion = 1 }),
            ("welcomePlayed", { _ = $0.welcomePlayed }, { $0.welcomePlayed = true }),
            ("analytics", { _ = $0.analytics }, { $0.analytics = false }),
        ]
        #expect(all.count == AppSettings.Key.allCases.count)
        for (i, setting) in all.enumerated() {
            // Settings of their own, each at its default (setting a value it already has needn't redraw anything).
            let suite = "\(name)-\(i)"
            let fresh = try #require(UserDefaults(suiteName: suite))
            defer { fresh.removePersistentDomain(forName: suite) }
            let s = AppSettings(defaults: fresh)
            let changes = Changes()
            withObservationTracking {
                setting.read(s)
            } onChange: {
                changes.count += 1
            }
            // Another setting changing doesn't redraw it; its own does.
            all[(i + 1) % all.count].change(s)
            #expect(changes.count == 0, "\(setting.name)")
            setting.change(s)
            #expect(changes.count == 1, "\(setting.name)")
        }
    }
}
