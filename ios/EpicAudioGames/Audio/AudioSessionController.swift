// AudioPlayer.kt's AudioAttributes(USAGE_GAME, SPEECH) with audio focus: the app's audio session while a game is open.

import AVFoundation
import os

/**
 * The audio session a game plays and listens in: .playAndRecord (the voice plays while the mic can open), to the
 * speaker rather than the earpiece, Bluetooth headphones allowed, and not mixed with other apps' audio (as Android's
 * audio focus stops them). One category for the whole game screen: switching it between speaking and listening
 * would stall both.
 *
 * It reports what happens to the session (interruptions, route changes, the engine's output changing, the media
 * services restarting) as [Event]s on the main actor; what to do about them (pausing) is the game's. Nonisolated: the
 * notifications come on other threads, and their handlers are made here so they never inherit the main actor.
 */
nonisolated final class AudioSessionController: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        /// A call, Siri or an alarm took the audio: the engines have stopped.
        case interruptionBegan
        /// The interruption is over; [shouldResume] is the system's hint (the app waits for a tap regardless).
        case interruptionEnded(shouldResume: Bool)
        /// The output changed: headphones in or out, Bluetooth connected, a switch in Control Center.
        /// .oldDeviceUnavailable is the player's headphones gone.
        case routeChanged(AVAudioSession.RouteChangeReason)
        /// An engine's input or output format changed (AVAudioEngineConfigurationChange): it has stopped itself.
        /// Which engine: the turns' or the mic's.
        case engineConfigurationChanged(ObjectIdentifier?)
        /// The media services restarted: every engine and the session must be set up again.
        case mediaServicesReset
    }

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "session")

    private let session: AVAudioSession
    private let onEvent: @MainActor @Sendable (Event) -> Void
    /// Sets the session up and makes it active (tests make it fail, as a call does).
    private let setUp: @Sendable (AVAudioSession) throws -> Void
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []

    init(
        session: AVAudioSession = .sharedInstance(),
        setUp: @escaping @Sendable (AVAudioSession) throws -> Void = AudioSessionController.setUp,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) {
        self.session = session
        self.setUp = setUp
        self.onEvent = onEvent
    }

    /// .playAndRecord to the speaker, Bluetooth headphones allowed, not mixed with other apps; then active.
    @Sendable static func setUp(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    /// Its events are being reported.
    var isObserving: Bool { lock.withLock { !observers.isEmpty } }

    deinit {
        stopObserving()
    }

    /// The session's events reported, and the session set up and active: when a game opens, and again after the
    /// media services restart. Its events are reported even if it can't be made active now (a call has the audio):
    /// a turn then makes it active as it plays (AudioGraph.start), and the next interruption still pauses the game.
    func activate() throws {
        startObserving()
        try setUp(session)
    }

    /**
     * The session let go, for other apps' audio to carry on (when the game closes). Every engine is stopped first:
     * deactivating with an engine running fails ("busy"). Returns whether it was deactivated.
     */
    @discardableResult
    func deactivate(stopping engines: [AVAudioEngine]) -> Bool {
        stopObserving()
        for e in engines { e.stop() }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            Self.log.error("can't deactivate the audio session: \(error, privacy: .public)")
            return false
        }
    }

    private func startObserving() {
        stopObserving()
        let center = NotificationCenter.default
        let report = onEvent
        @Sendable func send(_ event: Event) {
            DispatchQueue.main.async { MainActor.assumeIsolated { report(event) } }
        }
        let added = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { note in
                guard let event = Self.interruption(note.userInfo) else { return }
                send(event)
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                send(.routeChanged(AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown))
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { note in
                send(.engineConfigurationChanged((note.object as AnyObject?).map(ObjectIdentifier.init)))
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                               queue: nil) { _ in
                send(.mediaServicesReset)
            },
        ]
        lock.withLock { observers = added }
    }

    private func stopObserving() {
        let old = lock.withLock {
            defer { observers = [] }
            return observers
        }
        for o in old { NotificationCenter.default.removeObserver(o) }
    }

    static func interruption(_ info: [AnyHashable: Any]?) -> Event? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}
