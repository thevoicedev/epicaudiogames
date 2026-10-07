// MainActivity.kt's AppModel: the game list, and the game being played (one at a time).

import AVFoundation
import EpicAppCore
import Foundation
import Observation
import os

/// The game list, and the game being played (one at a time).
@Observable
final class AppModel {
    let games: [GameInfo]
    /// The game whose packs the store sheet shows, if it's open.
    private(set) var storeFor: GameInfo?
    private(set) var game: GameController?
    /// Bumped on the way back to the list, so it shows which games can be carried on.
    private(set) var visits = 0
    /// The game whose map is loading (a big map takes a moment: it loads away from the screen's thread).
    private(set) var opening: GameInfo?
    /// The games left part-way (their CONTINUE), read again each time the list shows (Android reads them as it
    /// draws the list).
    private(set) var continuing: Set<String> = []
    /// Something to tell the player on the list: a game that couldn't be opened, or went wrong and stopped (L1).
    var notice: String?
    /// Where the list is scrolled to (the card at its top): kept while a game is played, and as the list is drawn
    /// again.
    var homeScroll: String?
    let store: Store

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
     * from launch, as Android's does.
     */
    init(bundle: Bundle = .main, saves: (any SaveStore)? = nil, packs: PackStore? = nil, hearing: Hearing? = nil,
         silent: Bool = false, startStore: Bool = true) {
        let gamesFolder = bundle.url(forResource: "Games", withExtension: nil)
        games = gamesFolder.flatMap { try? Catalog.load($0.appendingPathComponent("catalog.json")) } ?? []
        loader = gamesFolder.map { GameLoader(games: $0) }
        content = silent ? nil : bundle.url(forResource: "Content", withExtension: nil)
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
        store.onInstalled = { [weak self] _ in self?.packInstalled() }
        store.inUse = { [weak self] id in self?.game?.info.id == id || self?.opening?.id == id }
        if startStore { store.start() }
        watchEnds()
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
            let controller = GameController(
                info: info,
                game: loaded.makePlay(),
                fresh: { loaded.makePlay() },
                dependencies: GameDependencies(saves: saves, audio: audio, listener: listener),
                onLeave: { [weak self] left in self?.left(left) }
            )
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
    }

    /// A game going back to the list by itself (its end, a quit, an error), if it's still the one open.
    private func left(_ controller: GameController) {
        guard game === controller else { return }
        if let failure = controller.failure { notice = failure }
        home()
    }

    /// The store sheet for a game's packs (nil: closed). Opening it pauses the game and reads the purchases again,
    /// as Android's does.
    func showStore(_ info: GameInfo?) {
        if info != nil && opening != nil { return }
        storeFor = info
        store.sheet(open: info != nil)
        if info != nil {
            if let game, game.end == nil { game.pause() }
        } else {
            packInstalled()
        }
    }

    /**
     * A pack was installed, the game reached an end, or the store sheet closed: a game waiting at an end that its own
     * pack, now installed, unlocks opens again with it (L14). A chapter's end comes back with NEXT CHAPTER; the
     * Werewolf's last ends start again with the new stories, as PLAY AGAIN does. Other games and other ends are left
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
     */
    func onScreen(_ on: Bool) {
        shown = on
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
        if closed { nowPlaying.clear() }
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
            return SpeechListener()
        case .none:
            return UnavailableListener()
        #if DEBUG
        case .script(let answers):
            return ScriptedListener(answers)
        #endif
        }
    }

    /// GameScreen.kt's permission request as the game opens: the mic is allowed once the player says so, and then
    /// the game listens (if it's waiting for an answer by then). Allowed, the mic goes on, for the whole game.
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
        guard !granted, controller.micWorks else { return }
        Task {
            // fixed: listen() here ignored a pause and the text box; allowMic() waits for them, as Android's does.
            guard await MicPermission.request() else { return }
            if game === controller { speech?.startMic() }
            controller.allowMic()
        }
    }

    // ----- Audio -----

    /// What plays a game's turns: its clips from its installed packs, then from the app's content. A build without
    /// content (CI) plays its turns silently, by the clock.
    func makeAudio(_ info: GameInfo, _ installed: [InstalledPack]) -> any TurnPlaying {
        guard let content else { return SilentTurnPlayer() }
        return TurnPlayer(resolver: ContentResolver(gameId: info.id, content: content, packs: installed.map(\.folder)))
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
     * A call, Siri, an alarm, headphones taken out, or the audio system restarting: the game waits for a tap (L2).
     * The mic, on for the whole game, is turned on again whenever it stopped (an interruption over, its input
     * changed), so that the game can listen again with the phone still locked.
     */
    func sessionEvent(_ event: AudioSessionController.Event) {
        guard let game else { return }
        let speech = listener as? SpeechListener
        switch event {
        case .interruptionBegan:
            speech?.audioSessionChanged()
            game.pause()
        case .interruptionEnded:
            speech?.restartMic()
        case .routeChanged(let reason):
            speech?.audioSessionChanged()
            if reason == .oldDeviceUnavailable { game.pause() }
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                // Headphones in: their mic; out: the iPhone's.
                AudioSessionController.preferHeadsetMic()
            }
        case .engineConfigurationChanged(let engine):
            // An engine stopped itself: the turn's would never finish, the mic's would hear nothing more.
            let turns = (audio as? TurnPlayer)?.engine.map(ObjectIdentifier.init)
            let mic = speech?.engine.map(ObjectIdentifier.init)
            if (game.speaking && engine == turns) || (game.listening && engine == mic) {
                speech?.audioSessionChanged()
                game.pause()
            }
            if engine == mic { speech?.restartMic() }
        case .mediaServicesReset:
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
