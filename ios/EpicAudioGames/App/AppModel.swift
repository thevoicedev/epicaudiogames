// MainActivity.kt's AppModel: the way in (the intro, onboarding), the tabs, and the game being played over them (one
// at a time), with the help sheet over it.

import AVFoundation
import EpicAppCore
import Foundation
import Observation
import UIKit
import os

/// The way in (the intro, onboarding), the tabs (Games, Shop, Help, Settings), and the game being played instead of
/// them (one at a time), with the help sheet over it.
@Observable
final class AppModel {
    let games: [GameInfo]
    /// The intro is showing (IntroView): set as the model is made (AppStart), on the process's first launch with
    /// Settings › Play the intro sound on.
    private(set) var intro = false
    /// Onboarding is showing (OnboardingView): the first run's, or opened again.
    private(set) var onboarding = false
    /// The tab onboarding was opened again from ("Show the welcome again"); nil on the first run.
    private(set) var onboardingFrom: AppTab?
    /// The Games heading takes VoiceOver's focus as it shows: the intro or onboarding has just ended.
    private(set) var focusGames = false
    /// The Help tab's open topic, kept while other tabs (or a game) show.
    private(set) var helpTopic: String?
    /// The Help tab's topic was opened from elsewhere (Settings › How to play): its heading takes the focus once.
    private(set) var focusHelpTopic = false
    /// The help sheet is open over the game, on [helpSheetTopic] (nil: its list of topics).
    private(set) var helpSheet = false
    private(set) var helpSheetTopic: String?
    /// The tab showing (Games as the app starts); a game is shown instead of the tabs, full screen.
    private(set) var tab = AppTab.games
    /// The game whose packs the store sheet shows, if it's open.
    private(set) var storeFor: GameInfo?
    private(set) var game: GameController?
    /// Bumped on the way back to the list, so it shows which games can be carried on.
    private(set) var visits = 0
    /// The game whose map is loading (a big map takes a moment: it loads away from the screen's thread).
    private(set) var opening: GameInfo?
    /// The games left part-way ("In progress"), read again each time the list shows (Android reads them as it
    /// draws the list).
    private(set) var continuing: Set<String> = []
    /// Something to tell the player on the list: a game that couldn't be opened, or went wrong and stopped (L1).
    var notice: String?
    /// Where the list is scrolled to (the card at its top): kept while a game is played, and as the list is drawn
    /// again.
    var homeScroll: String?
    let store: Store
    /// The player's settings, read before the first frame (the theme, the intro).
    let settings: AppSettings
    /**
     * The app's own sounds (AppAudio.swift): the intro's sting, the welcome and help read aloud, the success sound, and
     * Settings' samples. Its manifest has the help pages. MainActivity.kt's AppModel.appAudio.
     */
    let appAudio: AppAudio
    /// The help topics, this app's, in order (the manifest's; none in a build without it).
    var helpPages: [HelpPage] { appAudio.manifest?.help ?? [] }

    @ObservationIgnored let saves: any SaveStore
    /// The app's Content folder (each game's audio and cover), nil when the build has none.
    @ObservationIgnored let content: URL?
    /// Each game's map (or Nuclear War's clips), with the packs installed when it was loaded (the key names them).
    @ObservationIgnored let loader: GameLoader?
    /// The packs on this phone: Application Support/packs/<id>/ (Packs.kt's files/packs).
    @ObservationIgnored let packs: PackStore
    /// How the games listen.
    @ObservationIgnored let hearing: Hearing
    /// The open game's id and the packs it was loaded with, each at its version on the phone.
    @ObservationIgnored private var loaded: String?
    /// Whether the app is on screen (not in the background): a game that loads while it isn't waits for it.
    @ObservationIgnored private var shown = true
    @ObservationIgnored private var waitingToShow: [CheckedContinuation<Void, Never>] = []
    /// The open game's audio and listener, and the audio session they play in (active while a game is open).
    @ObservationIgnored private var audio: (any TurnPlaying)?
    @ObservationIgnored private var listener: (any Listening)?
    @ObservationIgnored private var session: AudioSessionController?
    /// Bumped by each close: a session deactivation waiting for a fading bed is let go if another follows.
    @ObservationIgnored private var closes = 0
    /// The open game on the lock screen, and the headphones' button acting on it.
    @ObservationIgnored let nowPlaying = NowPlaying()
    /**
     * The Apple Watch app (Watch/WatchBridge.swift; docs/WATCH.md): the open game's title, state and one button go to
     * the watch, and its two buttons come back as Magic Tap and the pause. The app's own model has the process's
     * session (WatchSession.app: none on an iPad, nor for the unit tests' host); a test can give its own link.
     * Android's is WearBridge.kt.
     */
    @ObservationIgnored private(set) var watch: WatchBridge?
    /// When the Shop tab last read the purchases, so showing it again soon doesn't ask the App Store again.
    @ObservationIgnored private var shopReadAt: ContinuousClock.Instant?
    /**
     * Usage data (docs/DESIGN.md › Usage data; Analytics/): what the player does in the app, the games
     * (GameController's onEvent) and the shop (Store's), as events of web/analytics/events.json, sent to our server
     * under a random ID while Settings › Privacy › Share usage data is on; nothing is sent on the first run until
     * onboarding, which says so, is over. The release app's; a Debug build's only with a server given as it's launched
     * (-EpicAnalytics), and never from the unit tests' host. The process's one (UsageData.app): its session and queue
     * outlive this model. A test can give its own. MainActivity.kt's AppModel.analytics.
     */
    @ObservationIgnored let analytics: any Analytics
    /// The app's own usage data, as the app comes and goes (nil with a test's own): [analytics].
    private var usage: UsageData? { analytics as? UsageData }
    /// The intro's sting was asked for (once, however often the intro's view appears), and the intro was skipped.
    @ObservationIgnored private var introStarted = false
    @ObservationIgnored private var introSkipped = false

    /**
     * The process has made the app's model once: its intro, if it had one, is over. Another model in the same process
     * (the unit tests' own) has none. Android's AppModel.launched (the activity made again while the process lives).
     */
    static var launched = false

    /// How the games listen: the device's speech recogniser (once the player allows it), none (typing and chips,
    /// as on a phone with no recogniser), or (Debug) a script of answers.
    enum Hearing {
        case speech
        case none
        #if DEBUG
        case script([String])
        #endif
    }

    /**
     * [silent]: the games play by the clock, with no audio (tests). [startStore]: the store listens for purchases
     * from launch, as Android's does. [settings]: the app's own (UserDefaults.standard) unless given. [analytics]: the
     * process's usage data (UsageData.app) unless given. [watchLink]: the process's watch session (WatchSession.app)
     * unless given.
     */
    init(bundle: Bundle = .main, saves: (any SaveStore)? = nil, packs: PackStore? = nil, hearing: Hearing? = nil,
         silent: Bool = false, startStore: Bool = true, settings: AppSettings? = nil,
         analytics: (any Analytics)? = nil, watchLink: (any WatchLinking)? = nil) {
        let gamesFolder = bundle.url(forResource: "Games", withExtension: nil)
        games = gamesFolder.flatMap { try? Catalog.load($0.appendingPathComponent("catalog.json")) } ?? []
        loader = gamesFolder.map { GameLoader(games: $0) }
        content = silent ? nil : bundle.url(forResource: "Content", withExtension: nil)
        #if DEBUG
        // -EpicReset (the UI tests): no setting an earlier test changed is left stored.
        if settings == nil { DebugLaunch.forgetSettingsIfReset() }
        #endif
        self.settings = settings ?? AppSettings()
        #if DEBUG
        // -EpicTheme, -EpicTextSize, -EpicSpeed: the settings this launch starts with.
        if settings == nil { DebugLaunch.apply(to: self.settings) }
        #endif
        // Settings › Privacy › Share usage data as the player has it; on the first run, nothing sent before the
        // welcome.
        self.analytics = analytics ?? UsageData.app(
            sharing: self.settings.analytics, waitForWelcome: self.settings.onboardingVersion == 0)
        appAudio = AppAudio(settings: self.settings, content: content)
        self.saves = saves ?? (try? FileSaveStore.standard()) ?? MemorySaveStore()
        let packs = packs ?? (try? PackStore.standard())
            ?? PackStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("packs"))
        self.packs = packs
        #if DEBUG
        self.hearing = hearing ?? DebugLaunch.hearing ?? .speech
        let packsURL = DebugLaunch.packsURL ?? Self.packsURL(bundle)
        #else
        self.hearing = hearing ?? .speech
        let packsURL = Self.packsURL(bundle)
        #endif
        store = Store(games: games, packs: packs, packsURL: packsURL)
        continuing = readContinuing()
        store.onInstalled = { [weak self] _ in self?.installed() }
        store.inUse = { [weak self] id in self?.game?.info.id == id || self?.opening?.id == id }
        // The shop's purchases, restores and downloads are usage data too.
        store.onEvent = { [analytics = self.analytics] name, props in analytics.track(name, props) }
        // With a game open, the app's sounds play in its session, the short ones on its cue node.
        appAudio.gameOpen = { [weak self] in self?.game != nil }
        appAudio.gameCues = { [weak self] in self?.audio as? any CuePlaying }
        if startStore { store.start() }
        watchEnds()
        watchSound()
        watchUsage()
        // The Apple Watch app follows the game from here (none open yet), and its buttons act on it.
        if let link = watchLink ?? WatchSession.app() {
            let bridge = WatchBridge(link: link) { [weak self] in self?.game }
            watch = bridge
            bridge.start()
        }
        // What shows before the tabs (docs/DESIGN.md › Structure; AppFlow.swift): the intro on the process's first
        // launch with Settings › Play the intro sound on, then onboarding until it's finished or skipped.
        var start = AppStart.of(
            introSound: self.settings.introSound, firstLaunch: !Self.launched,
            onboardingVersion: self.settings.onboardingVersion)
        Self.launched = true
        #if DEBUG
        // -EpicNoIntro, -EpicSkipOnboarding and the rest; nothing for the unit tests' host.
        if settings == nil { start = DebugLaunch.start(start) }
        #endif
        intro = start.intro
        onboarding = start.onboarding
        #if DEBUG
        // -EpicTab, -EpicHelp: the tab the app starts on, and the Help topic open there.
        if settings == nil { DebugLaunch.opens(self) }
        #endif
    }

    private static let log = Logger(subsystem: "com.epicaudiogames.app", category: "app")

    /// Info.plist's EpicPacksURL (the xcconfig's EPIC_PACKS_URL): Android's BuildConfig.PACKS_URL.
    private static func packsURL(_ bundle: Bundle) -> String {
        (bundle.object(forInfoDictionaryKey: "EpicPacksURL") as? String).map(Kt.trim) ?? ""
    }

    /**
     * Opens a game from the list, or [again] with a pack just installed: that game stays on screen, under the
     * spinner, until the new one is ready.
     */
    func open(_ info: GameInfo, again: Bool = false) {
        guard opening == nil, let loader else { return }
        // The game's audio alone from here: the sting, or a page being read, stops, and lets the session go for the
        // game's.
        appAudio.stopAll()
        if !again { close() }
        opening = info
        let installed = packs.installed(info)
        Task {
            let loaded: LoadedGame
            do {
                loaded = try await loader.load(info, installed: installed)
            } catch {
                opening = nil
                close()
                // What went wrong goes to the log: the player is told plainly.
                Self.log.error("couldn't open \(info.id, privacy: .public): \(String(describing: error), privacy: .public)")
                notice = "\(info.title) couldn't be opened."
                return
            }
            // A game that finished loading after the app was left starts when the app is back.
            await untilShown()
            // Nuclear War is written in code, its clips loaded like a map; the other games are maps.
            opening = nil
            close()
            self.loaded = Self.key(info, installed)
            let audio = makeAudio(info, installed)
            let listener = makeListener()
            let settings = self.settings
            let analytics = self.analytics
            let controller = GameController(
                info: info,
                game: loaded.makePlay(),
                fresh: { loaded.makePlay() },
                // The game's TurnPlayer plays the listening sounds too, on a node of their own.
                dependencies: GameDependencies(
                    saves: saves, audio: audio, listener: listener, cues: audio as? any CuePlaying),
                onLeave: { [weak self] left in self?.left(left) },
                // The mic opens by itself as Settings say, by default not with VoiceOver on (MicPolicy in A11y.swift):
                // both read afresh at each question, as either can change mid-game. MainActivity.kt passes TalkBack's.
                listensByItself: {
                    MicPolicy.listensByItself(policy: settings.micAuto, screenReaderOn: A11y.voiceOver)
                },
                // The listening sounds and their ticks as Settings › Sound and voice say, read as each plays.
                listeningSounds: { settings.listeningSounds },
                // What happens in it is usage data.
                onEvent: { name, props in analytics.track(name, props) }
            )
            controller.onListen = { if settings.listeningHaptics { Haptics.micOpened() } }
            controller.onListenEnd = { if settings.listeningHaptics { Haptics.micClosed() } }
            self.audio = audio
            self.listener = listener
            game = controller
            activateSession()
            // The mic goes on before the first turn plays (if it's allowed), so the game can listen with the phone
            // locked: iOS won't start it in the background.
            askForTheMic(controller)
            controller.open()
            nowPlaying.show(controller, cover: Covers.image(info.id))
        }
    }

    func home() {
        close()
        visits += 1
        // How the game went (its game_leave, as it closed) goes now.
        usage?.flush()
    }

    /// A game going back to the list by itself (its end, a quit, an error), if it's still the one open.
    private func left(_ controller: GameController) {
        guard game === controller else { return }
        if let failure = controller.failure { notice = failure }
        home()
    }

    /**
     * Shows a tab: picked in the tab bar, or with ⌘ and its number (Settings › How to play picks Help). Leaving the
     * Shop, what the store said there goes.
     */
    func select(_ tab: AppTab) {
        if tab == self.tab { return }
        if self.tab == .shop { store.sheet(open: false) }
        // Leaving Help, a page being read stops (the topic stays open for the way back).
        if self.tab == .help { stopHelpClip() }
        self.tab = tab
        event(Events.tabView(tab))
        if tab == .shop { event(Events.shopView(.tab)) }
    }

    /**
     * The Shop tab is showing: it reads the purchases again (a pack bought on another device downloads, a payment
     * approved shows), at most once a minute however often it's shown (docs/DESIGN.md › Shop).
     */
    func shopShown() {
        let now = ContinuousClock.now
        if let at = shopReadAt, now - at < Self.shopReadEvery { return }
        shopReadAt = now
        store.sheet(open: true)
    }

    /// The Shop tab reads the purchases again at most this often.
    private static let shopReadEvery: Duration = .seconds(60)

    /**
     * The store sheet for a game's packs (nil: closed), opened [from] a game's card, its menu or a locked end. Opening
     * it pauses the game and reads the purchases again, as Android's does.
     */
    func showStore(_ info: GameInfo?, from source: ShopSource = .card) {
        if info != nil && opening != nil { return }
        storeFor = info
        store.sheet(open: info != nil)
        if info != nil {
            event(Events.shopView(source))
            if let game, game.end == nil { game.pause() }
        } else {
            packInstalled()
        }
    }

    /**
     * Settings › Sound and voice › Play a sample: a line in the games' host's voice, at the speed chosen. With
     * VoiceOver on it waits a moment, so VoiceOver's own word for the tap comes first (as Help's Listen does).
     */
    func playSample() {
        afterScreenReader { [weak self] in self?.appAudio.previewVoiceSpeed() }
    }

    /// Settings › Listening sounds or Vibrate when listening starts, turned on: the sound and tick as the mic opens.
    func previewCue() {
        afterScreenReader { [weak self] in self?.appAudio.previewCue() }
    }

    /// Settings › Play the intro sound, turned on: the sting, as the app will start with it.
    func previewIntro() {
        afterScreenReader { [weak self] in self?.appAudio.previewIntro() }
    }

    /// Settings › Music volume, a step picked: a few seconds of a game's music at that volume (Off: silence).
    func previewMusic() {
        afterScreenReader { [weak self] in self?.appAudio.previewMusic() }
    }

    /// Runs [then] now, or with VoiceOver on a moment later, once it has said what the tap did (docs/DESIGN.md › Help:
    /// Listen's 400 ms, A11y.listenDelay). MainActivity.kt's afterScreenReader.
    private func afterScreenReader(_ then: @escaping @MainActor @Sendable () -> Void) {
        guard A11y.voiceOver else {
            then()
            return
        }
        Task {
            try? await Task.sleep(for: A11y.listenDelay)
            then()
        }
    }

    /**
     * A pack was installed (Store): the success sound for a player watching it arrive, on the Shop or in the store
     * sheet (docs/DESIGN.md › Shop); one installing out of sight (a retry, a restore as the app comes back) is quiet.
     * Then a game waiting at an end for it opens again ([packInstalled]). MainActivity.kt's installed.
     */
    private func installed() {
        if shown && ((tab == .shop && game == nil) || storeFor != nil) { appAudio.playSuccess() }
        packInstalled()
    }

    // ----- The intro (docs/DESIGN.md › Intro) -----

    /**
     * The intro is on screen: its sting starts now, or with VoiceOver on a moment later, once VoiceOver has read the
     * intro's name ([IntroTimes]). The intro ends a moment after the sting does, or with no sting (none in the build,
     * another app's audio playing) after a while. Once, however often it's asked (the intro's view made again): the
     * sting's end comes here, not to a view that may have gone. MainActivity.kt's startIntro.
     */
    func startIntro() {
        guard intro, !introStarted else { return }
        introStarted = true
        #if DEBUG
        // -EpicHoldIntro: it stays until it's skipped, with no sound (the audit's and the screenshots' moment).
        if DebugLaunch.holdsIntro { return }
        #endif
        let appeared = ContinuousClock.now
        Task {
            // The manifest (which sting) may still be being read as the app starts: waited for away from the screen,
            // so the intro never stops drawing for it.
            _ = await appAudio.loadManifest()
            if A11y.voiceOver {
                try? await Task.sleep(until: appeared + IntroTimes.screenReaderDelay, clock: .continuous)
            }
            guard intro else { return }                         // skipped meanwhile: no sting at all
            if !appAudio.playIntro(onDone: { [weak self] in self?.stingEnded() }) {
                try? await Task.sleep(until: appeared + IntroTimes.withoutSting, clock: .continuous)
                endIntro(skipped: false)
            }
        }
    }

    /// The sting has played to its end (the intro ends a moment later), or faded out as the intro was skipped.
    private func stingEnded() {
        if introSkipped {
            endIntro(skipped: true)
            return
        }
        Task {
            try? await Task.sleep(for: IntroTimes.afterSting)
            endIntro(skipped: false)
        }
    }

    /// A tap on the intro, its VoiceOver action, Magic Tap, VoiceOver's escape, Escape or Space: the sting fades out
    /// quickly, and it ends.
    func skipIntro() {
        guard intro, !introSkipped else { return }
        introSkipped = true
        if appAudio.introPlaying {
            appAudio.skipIntro()
        } else {
            endIntro(skipped: true)
        }
    }

    /// Onboarding next, on the first run; or Games, VoiceOver on its heading.
    private func endIntro(skipped: Bool) {
        guard intro else { return }
        intro = false
        event(Events.introFinished(skipped: skipped))
        if !onboarding { focusGames = true }
    }

    // ----- Onboarding (docs/DESIGN.md › Onboarding) -----

    /**
     * "Show the welcome again", in Help or Settings: onboarding again, from its first page (the welcome isn't read by
     * itself this time); skipped, it comes back to this tab.
     */
    func showWelcome() {
        appAudio.stopClip()
        onboardingFrom = tab
        onboarding = true
    }

    /**
     * Onboarding has ended, [completed] (Start playing) or skipped: it isn't shown by itself again
     * (settings.onboardingVersion), and the player goes to Games with VoiceOver on its heading, or, skipping onboarding
     * opened again, back to the tab it came from (AppFlow.swift's tabAfterOnboarding).
     */
    func onboardingDone(completed: Bool) {
        guard onboarding else { return }
        settings.onboardingVersion = AppStart.onboardingVersion
        let to = tabAfterOnboarding(completed: completed, openedFrom: onboardingFrom)
        onboarding = false
        onboardingFrom = nil
        event(Events.onboardingFinished(completed: completed))
        select(to)
        if to == .games { focusGames = true }
    }

    /// The Games heading has taken VoiceOver's focus ([focusGames]).
    func gamesFocused() {
        focusGames = false
    }

    /// What the player said to iOS's microphone question, asked by onboarding (for the usage data).
    func onboardingMicAnswered(granted: Bool) {
        event(Events.micPermission(granted: granted, where: .onboarding))
    }

    // ----- Help (docs/DESIGN.md › Help) -----

    /// The Help tab's topic opened ([id]), or closed (nil): a page being read stops. Which one is never sent.
    func showTopic(_ id: String?) {
        if id == helpTopic { return }
        stopHelpClip()
        helpTopic = id
        if id != nil { event(Events.helpViewed(.tab)) }
    }

    /// Settings › How to play: the Help tab, on playing with your voice (as a game's How to play opens), its heading
    /// taking VoiceOver's focus.
    func howToPlay() {
        select(.help)
        showTopic(Self.howToPlayTopic)
        focusHelpTopic = true
    }

    /// The Help topic opened from elsewhere has taken the focus ([focusHelpTopic]).
    func helpTopicFocused() {
        focusHelpTopic = false
    }

    /**
     * A game's How to play (its menu, or the pause): the help sheet, on playing with your voice, over the game, which
     * waits for it, paused (at an end there's nothing to pause).
     */
    func openHelpSheet() {
        if let game, game.end == nil, !game.paused { game.pause() }
        helpSheetTopic = Self.howToPlayTopic
        helpSheet = true
        event(Events.helpViewed(.game))
    }

    /// In the help sheet, a topic opened ([id]) or the list again (nil): a page being read stops.
    func showSheetTopic(_ id: String?) {
        stopHelpClip()
        helpSheetTopic = id
        if id != nil { event(Events.helpViewed(.game)) }
    }

    /// The help sheet has closed: what it was reading stops; the game stays paused, for Carry on.
    func closeHelpSheet() {
        stopHelpClip()
        helpSheet = false
        helpSheetTopic = nil
    }

    /// A help page being read aloud stops (not the welcome, nor a sample).
    private func stopHelpClip() {
        if case .some(.help) = appAudio.clipPlaying { appAudio.stopClip() }
    }

    /// The help topic How to play opens: "Playing with your voice" (tools/app_text.toml's ids are fixed).
    private static let howToPlayTopic = "voice"

    /**
     * Settings › Privacy › Delete my usage data: the server is asked to delete everything this device sent under its
     * random ID, then the app forgets that ID (and what's waiting to be sent); still sharing, the next event makes a
     * new one. With usage data off, the ID is forgotten already: nothing can be found to delete. MainActivity.kt's
     * deleteUsageData.
     */
    func deleteUsageData() async -> UsageDeletion {
        guard let usage else { return .nothingSent }
        return await usage.delete()
    }

    /// What the player said to the microphone's question, asked from Settings (for the usage data).
    func micAnswered(granted: Bool) {
        event(Events.micPermission(granted: granted, where: .settings))
    }

    /// Usage data: something happened ([analytics]).
    private func event(_ e: Event) {
        analytics.track(e)
    }

    /**
     * Settings › Privacy › Share usage data and onboarding, watched (MainActivity.kt's snapshotFlows): turned off (in
     * Settings, or onboarding's Turn off), nothing more goes and what's on the device is forgotten; onboarding over,
     * what waited for it goes.
     */
    private func watchUsage() {
        withObservationTracking {
            _ = settings.analytics
            _ = settings.onboardingVersion
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.usageChanged()
                self?.watchUsage()
            }
        }
    }

    private func usageChanged() {
        guard let usage else { return }
        usage.sharing = settings.analytics
        usage.waitForWelcome = settings.onboardingVersion == 0
    }

    /**
     * A pack was installed, the game reached an end, or the store sheet closed: a game waiting at an end that its own
     * pack, now installed, unlocks opens again with it (L14). A chapter's end comes back with "Next chapter"; the
     * Werewolf's last ends start again with the new stories, as "Play again" does. Other games and other ends are left
     * alone, and nothing happens under the store sheet.
     */
    func packInstalled() {
        guard let g = game, let end = g.end, opening == nil, storeFor == nil,
              let pack = g.info.packs.first(where: { $0.id == end.locked }), packs.isInstalled(pack),
              Self.key(g.info, packs.installed(g.info)) != loaded
        else { return }
        open(g.info, again: true)
    }

    /// The open game's end, watched: one its pack (bought while it played) unlocks opens again with it.
    private func watchEnds() {
        withObservationTracking {
            _ = game?.end
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.packInstalled()
                self?.watchEnds()
            }
        }
    }

    /// Settings' voice speed and music volume, watched: they reach what's playing at once, the open game's turn and a
    /// page being read (MainActivity.kt's snapshotFlows).
    private func watchSound() {
        withObservationTracking {
            _ = settings.voiceSpeed
            _ = settings.musicVolume
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.soundChanged()
                self?.watchSound()
            }
        }
    }

    private func soundChanged() {
        if let player = audio as? TurnPlayer {
            player.speed = settings.voiceSpeed
            player.musicVolume = settings.musicVolume
        }
        (audio as? SilentTurnPlayer)?.speed = settings.voiceSpeed
        appAudio.speedChanged()
    }

    /// A game's id and its installed packs, each at the version on the phone: "frootopia+frootopia-stories@1".
    private static func key(_ info: GameInfo, _ installed: [InstalledPack]) -> String {
        info.id + installed.map { "+\($0.pack.id)@\($0.pack.version)" }.joined()
    }

    /**
     * The app on screen (active) or not (in the background, the phone locked): a game loading waits for it; coming
     * back reads the purchases again, and whether the mic was allowed in Settings meanwhile (then the game listens if
     * it waits, as Android's ON_RESUME does), and turns the mic on again if it couldn't start in the background.
     *
     * Going to the background doesn't pause the game (UIBackgroundModes audio): it speaks and listens on, the phone
     * locked, through the headphones. Calls, Siri, alarms and headphones taken out still pause it (sessionEvent).
     *
     * For the usage data it's the app opened or put away (app_open, app_background; a moment's alert, which leaves the
     * app inactive, is neither). Put away, what's waiting is sent then, in a moment of background time asked of iOS:
     * suspended mid-request, it would only go once the app is back.
     */
    func onScreen(_ on: Bool) {
        shown = on
        if on {
            usage?.foreground()
        } else if let usage {
            let time = BackgroundTime("usage data")
            usage.background { Task { @MainActor in time.end() } }
        }
        guard on else { return }
        let waiting = waitingToShow
        waitingToShow = []
        waiting.forEach { $0.resume() }
        if let game, case .speech = hearing {
            // fixed: this set micAllowed itself, so the game's own check (not allowed yet) never called allowMic().
            if !MicPermission.granted {
                game.micAllowed = false
            } else {
                (listener as? SpeechListener)?.startMic()
                if !game.micAllowed { game.allowMic() }
            }
        }
        Task { await store.restore(cellular: false) }
    }

    private func untilShown() async {
        guard !shown else { return }
        await withCheckedContinuation { waitingToShow.append($0) }
    }

    private func close() {
        let player = audio as? TurnPlayer
        let engine = player?.engine
        // A bed fading out after the last turn's end plays its fade, as Android's fading players do.
        let tail = player?.tail
        let closed = game != nil
        let mic = (listener as? SpeechListener)?.engine
        if closed {
            nowPlaying.clear()
            // A page read over the game (its help) plays in the game's session: it stops, its engine with it, and the
            // help sheet goes with the game.
            appAudio.stopClip()
            helpSheet = false
            helpSheetTopic = nil
        }
        game?.close()           // the listener's release turns the mic off
        game = nil
        loaded = nil
        audio = nil
        listener = nil
        if closed { store.gameClosed() }
        continuing = readContinuing()
        guard let session else { return }
        closes += 1
        let close = closes
        let engines = [engine, mic].compactMap { $0 }
        guard let tail else {
            session.deactivate(stopping: engines)
            return
        }
        Task {
            try? await Task.sleep(for: tail)
            guard closes == close, game == nil, opening == nil else { return }
            session.deactivate(stopping: engines)
        }
    }

    // ----- Listening -----

    private func makeListener() -> any Listening {
        switch hearing {
        case .speech:
            // The player's time to answer (Settings › Sound and voice), read at each listen.
            let settings = self.settings
            return SpeechListener(answerTime: { settings.answerTime })
        case .none:
            return UnavailableListener()
        #if DEBUG
        case .script(let answers):
            return ScriptedListener(answers)
        #endif
        }
    }

    /**
     * GameScreen.kt's permission request as the game opens: the mic is allowed once the player says so, and then the
     * game listens (if it's waiting for an answer by then). Allowed, the mic goes on, for the whole game. Not asked if
     * the player said Not now (or refused) when onboarding asked (settings.micPrimed; docs/DESIGN.md › Onboarding): the
     * mic button and the circle still ask.
     */
    private func askForTheMic(_ controller: GameController) {
        #if DEBUG
        if case .script = hearing {
            controller.micAllowed = true
            return
        }
        #endif
        let granted = MicPermission.granted
        controller.micAllowed = granted
        let speech = listener as? SpeechListener
        if granted { speech?.startMic() }
        guard !granted, controller.micWorks, settings.micPrimed != .declined else { return }
        // Whether iOS will ask (a dialog shows): only then is its answer the player's, for the usage data.
        let asks = MicPermission.canAsk
        Task {
            let allowed = await MicPermission.request()
            if asks { controller.micAnswered(granted: allowed) }
            // fixed: listen() here ignored a pause and the text box; allowMic() waits for them, as Android's does.
            guard allowed else { return }
            if game === controller { speech?.startMic() }
            controller.allowMic()
        }
    }

    // ----- Audio -----

    /// What plays a game's turns: its clips from its installed packs, then from the app's content, at the voice speed
    /// and the music volume (Settings). A build without content (CI) plays its turns silently, by the clock.
    func makeAudio(_ info: GameInfo, _ installed: [InstalledPack]) -> any TurnPlaying {
        guard let content else {
            let silent = SilentTurnPlayer()
            silent.speed = settings.voiceSpeed
            return silent
        }
        let player = TurnPlayer(
            resolver: ContentResolver(gameId: info.id, content: content, packs: installed.map(\.folder)))
        player.speed = settings.voiceSpeed
        player.musicVolume = settings.musicVolume
        return player
    }

    /// The game's audio session, set up as a game opens (Android's audio focus, taken as ExoPlayer plays).
    private func activateSession() {
        let session = self.session ?? AudioSessionController { [weak self] event in self?.sessionEvent(event) }
        self.session = session
        do {
            try session.activate()
        } catch {
            AudioSessionController.log.error("can't activate the audio session: \(error, privacy: .public)")
        }
    }

    /**
     * A call, Siri, an alarm, headphones taken out, or the audio system restarting: the game waits for a tap (L2), and
     * a page being read over it (its help) stops. The mic, on for the whole game, is turned on again whenever it
     * stopped (an interruption over, its input changed), so that the game can listen again with the phone still locked.
     */
    func sessionEvent(_ event: AudioSessionController.Event) {
        guard let game else { return }
        let speech = listener as? SpeechListener
        switch event {
        case .interruptionBegan:
            speech?.audioSessionChanged()
            game.pause()
            appAudio.stopClip()
        case .interruptionEnded:
            speech?.restartMic()
        case .routeChanged(let reason):
            speech?.audioSessionChanged()
            if reason == .oldDeviceUnavailable {
                game.pause()
                appAudio.stopClip()
            }
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                // Headphones in: their mic; out: the iPhone's.
                AudioSessionController.preferHeadsetMic()
            }
        case .engineConfigurationChanged(let engine):
            // An engine stopped itself: the turn's would never finish, the mic's would hear nothing more, and a page
            // read over the game (its help, on an engine of its own) would never finish either.
            appAudio.engineChanged(engine)
            let turns = (audio as? TurnPlayer)?.engine.map(ObjectIdentifier.init)
            let mic = speech?.engine.map(ObjectIdentifier.init)
            if (game.speaking && engine == turns) || (game.listening && engine == mic) {
                speech?.audioSessionChanged()
                game.pause()
            }
            if engine == mic { speech?.restartMic() }
        case .mediaServicesReset:
            appAudio.stopClip()
            (audio as? TurnPlayer)?.resetEngine()
            activateSession()
            speech?.resetMic()
            game.pause()
        }
    }

    private func readContinuing() -> Set<String> {
        Set(games.map(\.id).filter { saves.inProgress($0) })
    }
}

/**
 * A moment of background time asked of iOS, for work that suspending the app would cut short (the usage data sent as
 * the app goes; a pack checked and unpacked, Store.install): given back once the work is done ([end]), or as soon as
 * iOS says time's up (iOS ends an app that still holds it then).
 */
final class BackgroundTime {
    private var task = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        task = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
