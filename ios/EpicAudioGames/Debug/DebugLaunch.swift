// No Kotlin counterpart: launch arguments (Debug builds) that drive the app, for screenshots and checks.

#if DEBUG
import EpicAppCore
import Foundation

/**
 * Plays the app without touching it, from its launch arguments (they arrive as UserDefaults):
 * - `-EpicReset YES`: every game's save is cleared, so no card on the list is "In progress", and the settings stored
 *   are forgotten, so a test that changed one (a theme, a switch) doesn't leave it for the next (the UI tests start
 *   so); a setting given as a launch argument still holds for that launch (`-settings.theme contrast`, AppSettings);
 * - `-EpicFresh YES`: the game's save is cleared first;
 * - `-EpicOpen <game id>`: opens the game;
 * - `-EpicSay "yes|no|fight"`: answers each question in turn with these, once the game waits; a last answer
 *   ending in "*" ("yes*") is given again and again, until the game ends;
 * - `-EpicSayDelay <seconds>`: each of those answers waits this long after its question is asked (0: at once);
 * - `-EpicSkip YES`: skips each turn's voice as soon as it plays;
 * - `-EpicPauseAt <seconds>`: pauses the game that long after it opens;
 * - `-EpicStore <game id>`: opens that game's store sheet;
 * - `-EpicLab YES`: opens the Audio Lab (RootView);
 * - `-EpicMic off`: the games don't listen (as on a phone with no recogniser: no mic, no permission asked);
 * - `-EpicHear "~|yes|?"`: the games hear these instead of the mic (ScriptedListener), the mic counting as allowed;
 * - `-EpicPacksURL <url>`: the pack server, in place of the build's;
 *
 * and the way in, the tabs and the look (docs/DESIGN.md's; the UI tests start with `-EpicNoIntro YES
 * -EpicSkipOnboarding YES -EpicAnalytics off`, the screenshots with the same):
 * - `-EpicNoIntro YES`: no intro this launch; `-EpicIntro YES`: the intro, even so (and even with Settings › Play the
 *   intro sound off); `-EpicHoldIntro YES`: the intro stays until it's skipped, with no sound (the audit's moment);
 * - `-EpicSkipOnboarding YES`: no onboarding this launch (nothing stored); `-EpicOnboarding YES`: onboarding, from its
 *   first page, even after it was finished (and even with -EpicSkipOnboarding);
 * - `-EpicVoiceOver YES`: onboarding goes as it does with VoiceOver on (its VoiceOver page; the welcome isn't read by
 *   itself), which a UI test can't turn on;
 * - `-EpicTab <games|shop|help|settings>`: the tab the app starts on; `-EpicHelp <topic id>`: the Help tab on that
 *   topic ("voice"; an id that isn't one: its list);
 * - `-EpicTheme <system|light|dark|contrast>`, `-EpicTextSize <1.0|1.15|1.3>` and `-EpicSpeed <0.75 … 2>` (the voice
 *   speed): those settings, stored as if picked in Settings (the next -EpicReset forgets them); `-settings.<key>
 *   <value>` gives any setting for the launch alone (AppSettings);
 * - `-EpicAnalytics off`, or a server's address: read by UsageData.app (Analytics/Analytics.swift). Off, nothing is
 *   recorded or sent this launch, and the setting itself is left as it is (Settings and the welcome show Share usage
 *   data as the player has it); an address, usage data goes there (`-EpicAnalytics http://localhost:3000`: the web
 *   server on the Mac, for the simulator). Android's EpicAnalytics extra;
 * - `-EpicContrast increased`: the palettes as with the phone's Increase Contrast on (EpicTheme), which a UI test can't
 *   turn on.
 *
 * The app as the unit tests' host (XCTest runs them inside it) has no intro and no onboarding, so nothing it plays
 * changes the audio session under the tests' own audio; and it sends no usage data, in any build (UsageData.app).
 *
 * `xcrun simctl launch booted com.epicaudiogames.app -EpicOpen noodle-rush -EpicSkip YES -EpicSay "yes|yes"`.
 */
enum DebugLaunch {
    /// How the games listen, if the launch says (-EpicMic off, -EpicHear).
    static var hearing: AppModel.Hearing? {
        let defaults = UserDefaults.standard
        if let script = defaults.string(forKey: "EpicHear") {
            return .script(script.split(separator: "|", omittingEmptySubsequences: false).map(String.init))
        }
        if defaults.string(forKey: "EpicMic") == "off" { return AppModel.Hearing.none }
        return nil
    }

    /// The pack server, if the launch names one (-EpicPacksURL).
    static var packsURL: String? { UserDefaults.standard.string(forKey: "EpicPacksURL") }

    /// -EpicReset: the settings stored are forgotten before AppSettings reads them (AppModel's init). Only what's
    /// stored goes: the launch arguments' settings are another domain, and still hold.
    static func forgetSettingsIfReset() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "EpicReset") else { return }
        for key in AppSettings.Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// -EpicTheme, -EpicTextSize and -EpicSpeed: the settings this launch starts with (AppModel's init, before anything
    /// reads them), stored as if picked in Settings. (-EpicAnalytics isn't one: UsageData.app reads it.)
    static func apply(to settings: AppSettings) {
        let defaults = UserDefaults.standard
        if let theme = defaults.string(forKey: "EpicTheme").flatMap({ ThemeChoice(rawValue: $0) }) {
            settings.theme = theme
        }
        if let size = defaults.string(forKey: "EpicTextSize").flatMap({ Double($0) }) { settings.textScale = size }
        if let speed = defaults.string(forKey: "EpicSpeed").flatMap({ Double($0) }) { settings.voiceSpeed = speed }
    }

    /**
     * What shows before the tabs this launch: [start] (AppStart, from the settings) with -EpicNoIntro, -EpicIntro,
     * -EpicSkipOnboarding and -EpicOnboarding; nothing, for the unit tests' host.
     */
    static func start(_ start: AppStart) -> AppStart {
        let defaults = UserDefaults.standard
        var intro = start.intro
        var onboarding = start.onboarding
        if hostsUnitTests {
            intro = false
            onboarding = false
        }
        if defaults.bool(forKey: "EpicNoIntro") { intro = false }
        if defaults.bool(forKey: "EpicIntro") { intro = true }
        if defaults.bool(forKey: "EpicSkipOnboarding") { onboarding = false }
        if defaults.bool(forKey: "EpicOnboarding") { onboarding = true }
        return AppStart(intro: intro, onboarding: onboarding)
    }

    /// -EpicTab and -EpicHelp: the tab the app starts on, and the Help topic open there (AppModel's init).
    static func opens(_ model: AppModel) {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "EpicTab").flatMap({ AppTab(rawValue: $0) }) { model.select(tab) }
        if let topic = defaults.string(forKey: "EpicHelp") {
            model.select(.help)
            if model.helpPages.contains(where: { $0.id == topic }) { model.showTopic(topic) }
        }
    }

    /// -EpicHoldIntro YES: the intro stays until it's skipped (AppModel.startIntro).
    static var holdsIntro: Bool { UserDefaults.standard.bool(forKey: "EpicHoldIntro") }

    /// -EpicVoiceOver YES: onboarding as with VoiceOver on (RootView).
    static var screenReader: Bool { UserDefaults.standard.bool(forKey: "EpicVoiceOver") }

    /// -EpicContrast increased: the phone's Increase Contrast, as EpicTheme reads it.
    static var moreContrast: Bool { UserDefaults.standard.string(forKey: "EpicContrast") == "increased" }

    /// The app is the unit tests' host: XCTest has put its configuration in the app's environment, to run them in it.
    static var hostsUnitTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    static func run(_ model: AppModel) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "EpicReset") {
            for game in model.games { model.saves.clear(game.id) }
            model.home()
        }
        // A store sheet or a game waits for the intro and onboarding to be over, as a player's would.
        while model.intro || model.onboarding {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
        if let id = defaults.string(forKey: "EpicStore"), let game = model.games.first(where: { $0.id == id }) {
            model.showStore(game)
        }
        guard let id = defaults.string(forKey: "EpicOpen"), let info = model.games.first(where: { $0.id == id })
        else { return }
        if defaults.bool(forKey: "EpicFresh") { model.saves.clear(id) }
        model.open(info)
        let answers = (defaults.string(forKey: "EpicSay") ?? "").split(separator: "|").map(String.init)
        let skip = defaults.bool(forKey: "EpicSkip")
        let pauseAt = defaults.double(forKey: "EpicPauseAt")
        let sayDelay = defaults.double(forKey: "EpicSayDelay")
        let opened = Date()
        var next = 0
        var paused = false
        // When the game began waiting for this answer (the question asked, its voice over).
        var waitingSince: Date?
        while !Task.isCancelled && Date().timeIntervalSince(opened) < 600 {
            try? await Task.sleep(for: .milliseconds(250))
            guard let game = model.game else { continue }
            if pauseAt > 0 && !paused && Date().timeIntervalSince(opened) >= pauseAt {
                paused = true
                game.pause()
            }
            if game.paused { continue }
            if skip && game.speaking { game.skip() }
            let waiting = !game.speaking && game.ask != nil
            waitingSince = waiting ? (waitingSince ?? Date()) : nil
            let waited = waitingSince.map { Date().timeIntervalSince($0) } ?? 0
            if waiting && next < answers.count && waited >= sayDelay {
                let answer = answers[next]
                if answer.hasSuffix("*") && next == answers.count - 1 {
                    game.answer(String(answer.dropLast()))
                } else {
                    game.answer(answer)
                    next += 1
                }
                waitingSince = nil
            }
            if game.end != nil && answers.last?.hasSuffix("*") == true { next = answers.count }
            if next >= answers.count && !game.speaking && (pauseAt <= 0 || paused) { return }
        }
    }
}
#endif
