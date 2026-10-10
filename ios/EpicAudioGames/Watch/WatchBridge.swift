// WearBridge.kt (the phone's side of the Wear OS app): the Apple Watch app's link with the game, through
// WatchConnectivity. The watch's side is ios/EpicWatch (PhoneLink.swift); docs/WATCH.md has the whole of it.

import EpicAppCore
import Foundation
import Observation
import WatchConnectivity
import os

/**
 * The Apple Watch app's view of the game (docs/DESIGN.md › Watches): the open game's title, what it's doing in words,
 * its one button named as on the iPhone (the talking circle's CircleAction), whether the microphone is open, and
 * whether Pause can do anything ([state(of:)]: WatchLink.swift's WatchState). The watch is told whenever that changes
 * (observed, as the screen may not be drawn while the phone is locked) and again whenever its link can hear it
 * ([link]'s onReady); its two buttons come back as Magic Tap and the pause ([perform]). The game is read afresh each
 * time ([game]). The app's model starts it (AppModel.watch). Android's is WearBridge.kt.
 */
final class WatchBridge {
    private let link: any WatchLinking
    private let game: () -> GameController?
    /// What the watch was last told: a change that leaves it as it is isn't told again.
    private var told: WatchState?

    init(link: any WatchLinking, game: @escaping () -> GameController?) {
        self.link = link
        self.game = game
    }

    /// Starts the link, tells the watch what's open now, and follows the game from here.
    func start() {
        link.onCommand = { [weak self] in self?.perform($0) }
        link.onReady = { [weak self] in self?.tell(again: true) }
        link.start()
        tell(again: true)
        watch()
    }

    /// The watch is told the game's state if it changed since it was last told, or [again] whatever it is.
    func tell(again: Bool = false) {
        let now = Self.state(of: game())
        if !again && now == told { return }
        told = now
        link.tell(now)
    }

    /// The game's state for the watch, watched: each change is told a moment later, once the change is made.
    private func watch() {
        withObservationTracking {
            _ = Self.state(of: game())
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.tell()
                self?.watch()
            }
        }
    }

    /**
     * A button on the watch. The big one does what Magic Tap does, as the headphones' button has it (NowPlaying.press):
     * skips the voice, carries on after a pause, starts or stops listening; the microphone's question can't be asked
     * from the wrist, so with the mic not allowed it does nothing (the watch shows it dimmed, [state(of:)]). Pause
     * pauses, as Escape and the lock screen's pause do: not over a pause, nor at an end. Nothing without a game, and
     * the big button nothing at an end (the watch has none then: a press sent just before it heard), as WearBridge.kt's.
     */
    func perform(_ command: WatchCommand) {
        guard let game = game() else { return }
        switch command {
        case .primary:
            guard game.end == nil else { return }
            game.magicTap {
                if game.micAllowed { game.mic() }
            }
        case .pause:
            if !game.paused && game.end == nil { game.pause() }
        }
    }

    /**
     * What the watch shows for [game] (nil: none open): the circle's name for the big button and its state in words
     * (listening as the status line has it, "Listening…"); at an end, no button and the end panel's heading, whatever
     * the circle says (a call can pause a game at its end, and the circle then says Carry on), as the big button does
     * nothing there ([perform]) and the end panel's choices are the iPhone's. With the mic not allowed the button can't
     * do anything from the watch (only the iPhone can ask for the mic): it's dimmed, still named "Talk (the microphone
     * is off)", which says why. WearBridge.kt's wearState.
     */
    static func state(of game: GameController?) -> WatchState {
        guard let game else { return .none }
        let action = game.end == nil ? game.circleAction : nil
        return WatchState(
            title: game.info.title,
            state: action.map(words) ?? game.end?.heading ?? "",
            action: action.map(watchAction),
            label: action?.label ?? "",
            enabled: action.map { $0.enabled && $0 != .micRefused } ?? false,
            listening: game.listening,
            canPause: !game.paused && game.end == nil)
    }

    /// What the game is doing, in words: the circle's state (its VoiceOver value), listening as the status line says.
    static func words(_ action: CircleAction) -> String {
        action == .stopListening ? "Listening…" : action.state
    }

    /// The circle's action as the watch knows it: the same names.
    static func watchAction(_ action: CircleAction) -> WatchAction {
        switch action {
        case .carryOn: .carryOn
        case .skip: .skip
        case .stopListening: .stopListening
        case .talk: .talk
        case .micRefused: .micRefused
        case .noRecognition: .noRecognition
        case .wait: .wait
        }
    }
}

/// Where the watch's state goes, and where its buttons come from: WatchConnectivity (WatchSession), or a test's.
protocol WatchLinking: AnyObject {
    /// A button pressed on the watch.
    var onCommand: (WatchCommand) -> Void { get set }
    /// The watch can be told again (the session has started, the watch app was installed, or it came to the front):
    /// the state goes again, changed or not.
    var onReady: () -> Void { get set }
    func start()
    /// What the game is doing now, for the watch.
    func tell(_ state: WatchState)
}

/**
 * WatchConnectivity's session on the iPhone. [tell] keeps the state as the application context, which the watch reads
 * as its app opens (the newest replacing the last), and while the watch app is in front (reachable) sends it as a
 * message too, so it shows at once. The watch's buttons come as messages, which wake the app if it isn't running
 * ([onCommand]). Nothing goes before the session is active, nor without a paired watch with the app on it; the
 * session says when that changes ([onReady]). The process's one ([app]): a session has one delegate.
 */
final class WatchSession: WatchLinking {
    var onCommand: (WatchCommand) -> Void = { _ in }
    var onReady: () -> Void = {}
    private let session: WCSession
    /// The session's delegate (the session holds it weakly).
    private var events: SessionEvents?

    private init(_ session: WCSession) {
        self.session = session
    }

    /// The process's session, once made ([app]).
    private static var made: WatchSession?

    /**
     * The process's session, made the first time it's asked for; none where there's no watch to pair with (an iPad,
     * a Mac, Vision Pro) and none for the unit tests' host (XCTest's configuration is in its environment), whose own
     * models are a test's.
     */
    static func app() -> WatchSession? {
        if let made { return made }
        guard WCSession.isSupported(),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return nil }
        let link = WatchSession(WCSession.default)
        made = link
        return link
    }

    func start() {
        guard events == nil else { return }
        let events = SessionEvents(link: self)
        self.events = events
        session.delegate = events
        session.activate()
    }

    func tell(_ state: WatchState) {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = state.context(at: Date().timeIntervalSince1970)
        do {
            try session.updateApplicationContext(context)
        } catch {
            SessionEvents.log.error("the watch's state wasn't kept: \(String(describing: error), privacy: .public)")
        }
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: SessionEvents.failed)
        }
    }
}

/**
 * The session's delegate, on WatchConnectivity's own queue: a command is read there (only plain values cross), and
 * what it hears goes on to the main actor, in order.
 */
nonisolated private final class SessionEvents: NSObject, WCSessionDelegate, Sendable {
    private let link: WatchSession

    init(link: WatchSession) {
        self.link = link
    }

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "watch")

    /// A message to the watch that didn't go (its app gone from the front as it went): the next state goes anyway.
    static let failed: @Sendable (any Error) -> Void = { error in
        SessionEvents.log.debug("a message to the watch didn't go: \(String(describing: error), privacy: .public)")
    }

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?
    ) {
        if let error {
            Self.log.error("the watch's session didn't start: \(String(describing: error), privacy: .public)")
        }
        ready()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Another watch was picked in the Watch app: the session starts again, for it.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app installed or taken off, or a watch paired or unpaired.
    func sessionWatchStateDidChange(_ session: WCSession) {
        ready()
    }

    /// The watch app came to the front (or went): in front, it's told at once.
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { ready() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchCommand(message: message) else { return }
        let link = link
        DispatchQueue.main.async { MainActor.assumeIsolated { link.onCommand(command) } }
    }

    private func ready() {
        let link = link
        DispatchQueue.main.async { MainActor.assumeIsolated { link.onReady() } }
    }
}
