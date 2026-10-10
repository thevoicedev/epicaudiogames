// The watch's side of WatchConnectivity: the iPhone's game coming in, the buttons going out. The iPhone's side is
// ios/EpicAudioGames/Watch/WatchBridge.swift; on Android, the Wear OS app's side of WearBridge.kt.

import Accessibility
import Foundation
import Observation
import WatchConnectivity
import WatchKit
import os

/**
 * The game on the iPhone as the watch hears of it ([state]), and its two buttons' way back ([press]), through
 * WatchConnectivity's session. The iPhone keeps its latest state there as the application context (read as the
 * session starts) and, while this app is in front, sends each new one as a message too; they're taken newest first
 * (WatchLink.swift's WatchInbox). The microphone opening buzzes the watch (watchOS's start haptic) and closing it
 * buzzes differently (stop): the cue for a player who can't hear the listening sound (docs/DESIGN.md › Watches). A
 * press that can't reach the iPhone buzzes a failure, and says so ([trouble]) until the iPhone is heard from again;
 * VoiceOver says it as it happens, unless the iPhone was listening (the Wear OS app's line is a polite live region).
 */
@Observable
final class PhoneLink {
    /// The game on the iPhone: none, until the iPhone says.
    private(set) var state = WatchState.none
    /// What a press that couldn't reach the iPhone says; nil once the iPhone is heard from again.
    private(set) var trouble: String?

    @ObservationIgnored private var inbox = WatchInbox()
    @ObservationIgnored private let session: WCSession?
    /// The session's delegate (the session holds it weakly).
    @ObservationIgnored private var events: SessionEvents?

    /// What a press that can't reach the iPhone says.
    static let unreachable = "Can't reach your iPhone. Keep it close, then try again."

    init(session: WCSession? = WCSession.isSupported() ? WCSession.default : nil) {
        self.session = session
    }

    /// Starts the session, once: the iPhone's latest state then comes in by itself.
    func start() {
        #if DEBUG
        // -EpicWatchDemo: a game's state, shown without an iPhone (screenshots, checks).
        if let demo = WatchDemo.chosen {
            state = demo
            return
        }
        #endif
        guard let session, events == nil else { return }
        let events = SessionEvents(link: self)
        self.events = events
        session.delegate = events
        session.activate()
    }

    /**
     * A button pressed: the big one ([WatchCommand.primary]) or Pause, sent to the iPhone, which does it as Magic Tap
     * or the pause does there (WatchBridge.perform). The iPhone must be in reach (near, or on the same Wi-Fi); the
     * message wakes the iPhone app if it isn't running.
     */
    func press(_ command: WatchCommand) {
        guard let session, session.activationState == .activated, session.isReachable else {
            couldntReach()
            return
        }
        session.sendMessage(command.message, replyHandler: nil, errorHandler: SessionEvents.failed(self))
    }

    /// A state from the iPhone, made [at]: shown if it's the newest, with a buzz if the microphone opened or closed.
    fileprivate func received(_ new: WatchState, at: Double) {
        let taken = inbox.take(new, at: at)
        guard taken.shown else { return }
        state = inbox.state
        trouble = nil
        switch taken.haptic {
        case .listeningStarted: buzz(.start)
        case .listeningStopped: buzz(.stop)
        case nil: break
        }
    }

    /// The iPhone in reach again: what a failed press said goes.
    fileprivate func reachable(_ yes: Bool) {
        if yes { trouble = nil }
    }

    fileprivate func couldntReach() {
        trouble = Self.unreachable
        buzz(.failure)
        // A VoiceOver player pressed the button and felt the failure: the words come too, each time, without having
        // to find the line (nothing is said without VoiceOver). Not while the iPhone was last heard listening: its
        // microphone mustn't hear the watch speak (docs/DESIGN.md › Everywhere › Status messages).
        if !state.listening { AccessibilityNotification.Announcement(Self.unreachable).post() }
    }

    private func buzz(_ haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
    }
}

/**
 * The session's delegate, on WatchConnectivity's own queue: each state is read there (only plain values cross), and
 * goes on to the main actor, in order.
 */
nonisolated private final class SessionEvents: NSObject, WCSessionDelegate, Sendable {
    private let link: PhoneLink

    init(link: PhoneLink) {
        self.link = link
    }

    static let log = Logger(subsystem: "com.epicaudiogames.app.watchkitapp", category: "phone")

    /// A press's message that didn't go (the iPhone out of reach as it went): the failure, on the main actor.
    static func failed(_ link: PhoneLink) -> @Sendable (any Error) -> Void {
        { error in
            SessionEvents.log.debug("a press didn't reach the iPhone: \(String(describing: error), privacy: .public)")
            DispatchQueue.main.async { MainActor.assumeIsolated { link.couldntReach() } }
        }
    }

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?
    ) {
        if let error {
            Self.log.error("the session didn't start: \(String(describing: error), privacy: .public)")
        }
        // The iPhone's latest state, kept from before this app opened.
        deliver(session.receivedApplicationContext)
        reachability(session)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        reachability(session)
    }

    private func reachability(_ session: WCSession) {
        let reachable = session.isReachable
        let link = link
        DispatchQueue.main.async { MainActor.assumeIsolated { link.reachable(reachable) } }
    }

    private func deliver(_ context: [String: Any]) {
        guard let received = WatchState.from(context) else { return }
        let link = link
        let state = received.state
        let at = received.at
        DispatchQueue.main.async { MainActor.assumeIsolated { link.received(state, at: at) } }
    }
}
