// MainActivity.kt's AppModel: the list's In progress read again as it shows, packInstalled reopening a game (L14), the
// store sheet, the tabs and the Shop, the background, the way in (the intro, onboarding) and Help, and the usage data.

import EpicAppCore
import Foundation
import MediaPlayer
import Testing
@testable import EpicAudioGames

/// The app's model with the app's own games, saves in memory, packs in a scratch folder, and silent audio.
@MainActor
@Suite(.serialized)
struct AppModelTests {
    let saves = MemorySaveStore()
    let scratch: URL
    let packs: PackStore

    init() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests-\(UUID().uuidString)")
        packs = PackStore(root: scratch.appendingPathComponent("packs"))
    }

    private func model() -> AppModel {
        AppModel(saves: saves, packs: packs, hearing: AppModel.Hearing.none, silent: true, startStore: false)
    }

    private func info(_ model: AppModel, _ id: String) throws -> GameInfo {
        try #require(model.games.first { $0.id == id })
    }

    /// The placeholder pack folder (ios/scripts/placeholder_content.py), installed as the store would.
    private func installFrootopiaPack() throws -> Bool {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/placeholder-packs/frootopia-stories")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("pack.json").path) else { return false }
        try FileManager.default.createDirectory(at: packs.root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: packs.root.appendingPathComponent("frootopia-stories"))
        return true
    }

    private func until(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Android reads each game's save as the list is drawn: a game that reached its end elsewhere (here: the save
    /// written behind the list's back) shows Play as soon as the list shows again, even under the loading overlay.
    @Test func theListReadsWhatCanBeCarriedOnEachTimeItShows() async throws {
        saves.store("noodle-rush", Saved(node: "nr-start", vars: [:], ended: false))
        let model = model()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(model.continuing == ["noodle-rush"])
        saves.store("noodle-rush", Saved(node: "nr-start", vars: [:], ended: true))
        model.open(try info(model, "pirate-quest"))
        #expect(model.opening != nil)
        #expect(model.continuing.isEmpty)
        #expect(await until { model.game != nil })
        model.home()
        #expect(model.game == nil)
    }

    /// With no recogniser, the mic doesn't work and nothing is asked; whether it's allowed is as the phone says
    /// (GameScreen.kt sets micAllowed from the permission either way).
    @Test func withNoRecogniserTheMicIsOff() async throws {
        let model = model()
        defer { try? FileManager.default.removeItem(at: scratch) }
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game != nil })
        let game = try #require(model.game)
        #expect(!game.micWorks)
        #expect(game.micAllowed == MicPermission.granted)
        model.home()
    }

    #if DEBUG
    /**
     * The game opens the mic by itself as Settings › Microphone says: never, or always (with VoiceOver on too). The
     * model gives the game MicPolicy's answer (MainActivity.kt's AppModel does the same with TalkBack).
     */
    @Test func theMicOpensByItselfAsTheSettingSays() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        for policy in [MicAuto.never, .always] {
            let suite = "AppModelTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            settings.micAuto = policy
            // A script with nothing in it: the mic counts as allowed, and hears nothing.
            let model = AppModel(saves: saves, packs: packs, hearing: .script([]), silent: true, startStore: false,
                                 settings: settings)
            model.open(try info(model, "noodle-rush"))
            #expect(await until { model.game?.speaking == true })
            let game = try #require(model.game)
            #expect(game.micAllowed)
            game.skip()
            #expect(game.listening == (policy == .always), "\(policy)")
            model.home()
        }
    }
    #endif

    /// L14: Frootopia waiting at the chapter end its pack unlocks opens there again once the pack is in, NEXT CHAPTER
    /// showing: bought before that end (while it played) or at it (once the store sheet closes). From the list too.
    /// fixed: only the pack's own game, at an end the pack unlocks, is opened again; other games and ends aren't.
    @Test func aGameWaitingAtTheEndItsPackUnlocksOpensThereWithIt() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        saves.store("frootopia", Saved(node: "fr-53", vars: [:], ended: false))
        let model = model()
        let frootopia = try info(model, "frootopia")
        let pack = try #require(frootopia.packs.first)

        // Bought while it played: nothing happens until it reaches the end the pack unlocks.
        model.open(frootopia)
        #expect(await until { model.game?.ask != nil })
        let playing = try #require(model.game)
        guard try installFrootopiaPack() else {         // no placeholder packs on this machine
            model.home()
            return
        }
        #expect(packs.isInstalled(pack))
        model.packInstalled()
        #expect(model.game === playing)
        try await reachTheLockedEnd(playing)
        #expect(await until { model.game != nil && model.game !== playing && model.game?.end != nil })
        let reopened = try #require(model.game)
        #expect(reopened.end?.kind == "chapter")
        #expect(reopened.canGoOn, "no NEXT CHAPTER")
        // It has the pack now: nothing more to do.
        model.packInstalled()
        #expect(model.game === reopened)

        // Bought at that end, from its store sheet: opened again once the sheet closes.
        model.home()
        try FileManager.default.removeItem(at: packs.root.appendingPathComponent(pack.id))
        saves.store("frootopia", Saved(node: "fr-53", vars: [:], ended: false))
        model.open(frootopia)
        #expect(await until { model.game?.ask != nil })
        let again = try #require(model.game)
        try await reachTheLockedEnd(again)
        #expect(again.end?.locked == pack.id)
        model.showStore(frootopia)
        #expect(!again.paused, "paused at its end")
        _ = try installFrootopiaPack()
        model.packInstalled()
        #expect(model.game === again, "opened again under the store sheet")
        model.showStore(nil)
        #expect(await until { model.game != nil && model.game !== again && model.game?.end != nil })
        #expect(model.game?.canGoOn == true)

        // From the list: at that end, NEXT CHAPTER showing.
        model.home()
        model.open(frootopia)
        #expect(await until { model.game?.end != nil })
        #expect(model.game?.canGoOn == true)
        model.home()
    }

    /// The store sheet pauses a game playing (it waits for a tap once the sheet closes); a game at its end isn't.
    @Test func theStoreSheetPausesTheGame() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        let frootopia = try info(model, "frootopia")
        model.open(frootopia)
        #expect(await until { model.game != nil })
        let game = try #require(model.game)
        model.showStore(frootopia)
        #expect(game.paused)
        #expect(!game.speaking)
        model.showStore(nil)
        #expect(model.storeFor == nil)
        #expect(model.game === game)
        model.home()
    }

    /// The tabs: Games as the app starts, then the one picked; leaving the Shop, what the store said there goes (and
    /// only then). MainActivity.kt's AppModel.select.
    @Test func aTabPickedShowsAndLeavingTheShopClearsWhatItSaid() {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        #expect(model.tab == .games)
        model.select(.shop)
        #expect(model.tab == .shop)
        model.store.message = "The purchase didn't go through."
        model.select(.settings)
        #expect(model.tab == .settings)
        #expect(model.store.message == nil, "the Shop's message stayed")
        model.store.note = "Your purchases are restored."
        model.select(.help)
        #expect(model.store.note == "Your purchases are restored.", "left a tab that isn't the Shop")
        model.select(.help)
        #expect(model.tab == .help)
    }

    /// The Shop tab reads the purchases again as it shows (what the store said before goes), at most once a minute
    /// however often it's shown (docs/DESIGN.md › Shop).
    @Test func theShopReadsThePurchasesAtMostOnceAMinute() {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.store.message = "Said before."
        model.shopShown()
        #expect(model.store.message == nil, "not read again")
        model.store.message = "Said since."
        model.shopShown()
        #expect(model.store.message == "Said since.", "read again within the minute")
    }

    /// While a game loads, no store sheet opens over it.
    @Test func noStoreSheetWhileAGameLoads() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.open(try info(model, "frootopia"))
        #expect(model.opening != nil)
        model.showStore(try info(model, "the-werewolf"))
        #expect(model.storeFor == nil)
        #expect(await until { model.game != nil })
        model.home()
    }

    /// A game that finishes loading while the app is in the background waits for it to come back.
    @Test func aGameLoadedInTheBackgroundStartsWhenTheAppIsBack() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.onScreen(false)
        model.open(try info(model, "noodle-rush"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.game == nil)
        #expect(model.opening != nil)
        model.onScreen(true)
        #expect(await until { model.game?.speaking == true })
        model.home()
    }

    /// Going to the background (the phone locked, another app) doesn't pause the game: it speaks on, and comes back
    /// playing. The lock screen shows it while it's open.
    @Test func theGamePlaysOnInTheBackground() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game?.speaking == true })
        let game = try #require(model.game)
        #expect(model.nowPlaying.game === game)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Noodle Rush")
        model.onScreen(false)
        #expect(!game.paused, "the background paused the game")
        try await Task.sleep(for: .milliseconds(500))
        #expect(game.speaking)
        #expect(!game.paused)
        model.onScreen(true)
        #expect(!game.paused)
        #expect(game.speaking)
        model.home()
        #expect(model.nowPlaying.game == nil)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }

    /// What still pauses: a call (or Siri, an alarm), headphones taken out, the media services restarting. New
    /// headphones, and an interruption ending, don't.
    @Test func callsAndHeadphonesOutPauseTheGame() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game?.speaking == true })
        let game = try #require(model.game)
        model.sessionEvent(.routeChanged(.newDeviceAvailable))
        #expect(!game.paused, "headphones in paused the game")
        model.sessionEvent(.interruptionBegan)
        #expect(game.paused)
        model.sessionEvent(.interruptionEnded(shouldResume: true))
        #expect(game.paused, "it carries on by itself")
        game.carryOn()
        #expect(!game.paused)
        model.sessionEvent(.routeChanged(.oldDeviceUnavailable))
        #expect(game.paused, "headphones out didn't pause the game")
        game.carryOn()
        model.sessionEvent(.mediaServicesReset)
        #expect(game.paused)
        model.home()
    }

    // ----- The way in (docs/DESIGN.md › Structure, › Intro, › Onboarding) and Help -----

    /**
     * The process's first model has the intro (Play the intro sound on), then onboarding (never finished), then Games,
     * VoiceOver on its heading; another in the same process has no intro, and onboarding once finished isn't shown
     * again. MainActivity.kt's AppModel (AppFlowTest has the rules).
     */
    @Test func theWayInIsTheIntroThenOnboardingThenGames() throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let (settings, forget) = try ownSettings(onboarded: false)
        defer { forget() }
        AppModel.launched = false
        defer { AppModel.launched = true }
        let model = model(settings)
        #expect(model.intro)
        #expect(model.onboarding)
        model.skipIntro()
        #expect(!model.intro)
        #expect(model.onboarding)
        #expect(!model.focusGames, "the Games heading took the focus under onboarding")
        model.onboardingDone(completed: true)
        #expect(!model.onboarding)
        #expect(model.tab == .games)
        #expect(model.focusGames)
        #expect(settings.onboardingVersion == AppStart.onboardingVersion)
        model.gamesFocused()
        #expect(!model.focusGames)
        let again = self.model(settings)
        #expect(!again.intro)
        #expect(!again.onboarding)
    }

    /// With no sting (no content, here), the intro ends by itself a while after it shows, Games taking the focus
    /// (onboarding was finished before); asked again, it isn't started twice.
    @Test func theIntroEndsByItselfWithoutASting() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let (settings, forget) = try ownSettings(onboarded: true)
        defer { forget() }
        AppModel.launched = false
        defer { AppModel.launched = true }
        let model = model(settings)
        #expect(model.intro)
        #expect(!model.onboarding)
        model.startIntro()
        model.startIntro()
        try await Task.sleep(for: .seconds(1))
        #expect(model.intro, "it ended before its time")
        #expect(await until(.seconds(6)) { !model.intro })
        #expect(model.focusGames)
    }

    /// "Show the welcome again" (Settings, Help): onboarding over that tab; skipped, back to it; finished, Games.
    @Test func theWelcomeShownAgainGoesBackWhereItWasOpened() throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let (settings, forget) = try ownSettings(onboarded: true)
        defer { forget() }
        let model = model(settings)
        #expect(!model.onboarding)
        model.select(.settings)
        model.showWelcome()
        #expect(model.onboarding)
        #expect(model.onboardingFrom == .settings)
        model.onboardingDone(completed: false)
        #expect(!model.onboarding)
        #expect(model.onboardingFrom == nil)
        #expect(model.tab == .settings)
        #expect(!model.focusGames)
        model.select(.help)
        model.showWelcome()
        model.onboardingDone(completed: true)
        #expect(model.tab == .games)
        #expect(model.focusGames)
    }

    /// Settings › How to play: the Help tab on playing with your voice, its heading to take the focus once; a topic
    /// closed is the list again.
    @Test func howToPlayInSettingsOpensHelpOnPlayingWithYourVoice() {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.howToPlay()
        #expect(model.tab == .help)
        #expect(model.helpTopic == "voice")
        #expect(model.focusHelpTopic)
        model.helpTopicFocused()
        #expect(!model.focusHelpTopic)
        model.showTopic("typing")
        #expect(model.helpTopic == "typing")
        model.showTopic(nil)
        #expect(model.helpTopic == nil)
    }

    /// A game's How to play: the help sheet on playing with your voice, over the game, which waits for it paused;
    /// closed, the game stays paused (for Carry on); leaving the game, the sheet goes with it. MainActivity.kt's
    /// openHelpSheet.
    @Test func howToPlayInAGameIsTheHelpSheetOverItPaused() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game?.speaking == true })
        let game = try #require(model.game)
        model.openHelpSheet()
        #expect(model.helpSheet)
        #expect(model.helpSheetTopic == "voice")
        #expect(game.paused)
        model.showSheetTopic(nil)
        #expect(model.helpSheetTopic == nil)
        model.showSheetTopic("typing")
        #expect(model.helpSheetTopic == "typing")
        model.closeHelpSheet()
        #expect(!model.helpSheet)
        #expect(model.helpSheetTopic == nil)
        #expect(game.paused, "closing the help sheet carried on")
        model.openHelpSheet()
        #expect(game.paused)
        model.home()
        #expect(!model.helpSheet)
    }

    // ----- Usage data (docs/DESIGN.md › Usage data) -----

    /**
     * What the app's model tells the usage data (MainActivity.kt's AppModel): the intro and onboarding, the tabs and
     * the Shop (by where it was opened from), help (never which topic), the microphone's answers, and the game's own
     * events through it; every one an event the whitelist takes. A test's own usage data: the app's (UsageData) sends
     * nothing from the unit tests' host, and has nothing to delete.
     */
    @Test func theModelsEventsAreUsageData() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let (settings, forget) = try ownSettings(onboarded: false)
        defer { forget() }
        AppModel.launched = false
        defer { AppModel.launched = true }
        let usage = RecordedUsage()
        let model = AppModel(
            saves: saves, packs: packs, hearing: AppModel.Hearing.none, silent: true, startStore: false,
            settings: settings, analytics: usage)
        #expect(model.analytics is RecordedUsage)
        model.skipIntro()
        model.onboardingMicAnswered(granted: false)
        model.onboardingDone(completed: false)
        model.select(.shop)
        model.select(.help)
        model.showTopic("typing")
        model.showTopic(nil)
        model.micAnswered(granted: true)
        model.select(.games)
        model.showStore(try info(model, "frootopia"), from: .card)
        model.showStore(nil)
        #expect(usage.take() == [
            Events.introFinished(skipped: true),
            Events.micPermission(granted: false, where: .onboarding),
            Events.onboardingFinished(completed: false),
            Events.tabView(.shop), Events.shopView(.tab),
            Events.tabView(.help),
            Events.helpViewed(.tab),
            Events.micPermission(granted: true, where: .settings),
            Events.tabView(.games),
            Events.shopView(.card),
        ])
        // A game: its own events, and what the game's menu and help sheet open.
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game?.speaking == true })
        model.openHelpSheet()
        model.closeHelpSheet()
        model.showStore(try info(model, "noodle-rush"), from: .menu)
        model.showStore(nil)
        model.home()
        let game = usage.take()
        #expect(game.map(\.name) == ["game_open", "help_viewed", "shop_view", "game_leave"])
        #expect(game.first == Events.gameOpen("noodle-rush", resumed: false))
        #expect(game[1] == Events.helpViewed(.game))
        #expect(game[2] == Events.shopView(.menu))
        #expect(await model.deleteUsageData() == .nothingSent)
    }

    /// A model with these settings (the way in is decided by them), its saves and packs the suite's.
    private func model(_ settings: AppSettings) -> AppModel {
        AppModel(saves: saves, packs: packs, hearing: AppModel.Hearing.none, silent: true, startStore: false,
                 settings: settings)
    }

    /// Settings of their own (a UserDefaults suite), onboarding finished or not; [forget] lets the suite go.
    private func ownSettings(onboarded: Bool) throws -> (settings: AppSettings, forget: () -> Void) {
        let suite = "AppModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        if onboarded { settings.onboardingVersion = AppStart.onboardingVersion }
        return (settings, { defaults.removePersistentDomain(forName: suite) })
    }

    /// Answers fr-53 "no": Quick Ending (fr-55), the chapter end Frootopia's pack unlocks.
    private func reachTheLockedEnd(_ game: GameController) async throws {
        game.answer("no")
        game.skip()
        #expect(await until { game.end != nil })
        #expect(game.end?.kind == "chapter")
    }
}

/// Usage data a test reads back: each event as the app told it, each checked against the whitelist as it's taken.
final class RecordedUsage: Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []

    func track(_ name: String, _ props: [String: any Sendable]) {
        lock.lock()
        defer { lock.unlock() }
        events.append(Event(name: name, props: props))
    }

    /// The events since the last take.
    func take() -> [Event] {
        lock.lock()
        let taken = events
        events = []
        lock.unlock()
        for e in taken { #expect(Events.problem(e.name, e.props) == nil, "\(e)") }
        return taken
    }
}
