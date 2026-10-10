// AudioPlayer.kt's AudioAttributes(USAGE_GAME, SPEECH) with audio focus: the app's audio session while a game is open;
// and AppAudio.kt's, for its sounds with no game open (none for the sting, a moment's focus for a page read aloud).

import AVFoundation
import os

/**
 * The audio session a game plays and listens in: .playAndRecord (the voice plays while the mic is on), to the
 * speaker rather than the earpiece, Bluetooth headphones allowed for listening and for their mic, and not mixed with
 * other apps' audio (as Android's audio focus stops them). One category for the whole game screen: switching it
 * between speaking and listening would stall both. The app's UIBackgroundModes has "audio": with the phone locked,
 * the game goes on speaking and listening.
 *
 * Headphones' mics: AirPods and other Bluetooth headsets are heard through the hands-free profile (HFP), which is
 * call quality both ways; their own A2DP has no mic. So with a Bluetooth headset connected, the game's voice is call
 * quality the whole time the game is open (the mic is on all that time). From iOS 26, headsets that can record in
 * high quality (recent AirPods) are asked to (.bluetoothHighQualityRecording), and the voice stays full quality;
 * other headsets fall back to HFP. The headset's mic is preferred to the iPhone's whenever one is connected.
 *
 * It reports what happens to the session (interruptions, route changes, the engine's output changing, the media
 * services restarting) as [Event]s on the main actor; what to do about them (pausing) is the game's. Nonisolated: the
 * notifications come on other threads, and their handlers are made here so they never inherit the main actor.
 *
 * With no game open, the app's own sounds have sessions of their own, set up the same way with [ambient] (the sting,
 * the short sounds) or [spoken] (a page read aloud) in place of [setUp] (AppAudio).
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

    /**
     * The category's options: the speaker rather than the earpiece; Bluetooth headphones for listening (A2DP) and,
     * to use their mic, as headsets (HFP, which iOS picks over A2DP for a headset that has both); from iOS 26,
     * high-quality Bluetooth recording where the headset has it (HFP otherwise). Not mixed with other apps.
     */
    static var options: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP]
        if #available(iOS 26.0, *) { options.insert(.bluetoothHighQualityRecording) }
        return options
    }

    /**
     * .playAndRecord with [options], then active, with the headset's mic preferred if one is connected. Haptics go on
     * while the mic records: it's on the whole time a game is open, and iOS would otherwise keep the phone still,
     * listening tick and all (Haptics).
     */
    @Sendable static func setUp(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        do {
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            // Not worth losing the game's audio over: only the ticks are missed.
            log.error("can't allow haptics while recording: \(error, privacy: .public)")
        }
        try session.setActive(true)
        preferHeadsetMic(session)
    }

    /**
     * The app's own sounds with no game open, the intro's sting and the short ones (AppAudio): .ambient, which mixes
     * with other apps' audio, keeps to the silent switch, and never records; then active. Android plays them without
     * taking the audio focus.
     */
    @Sendable static func ambient(_ session: AVAudioSession) throws {
        try session.setCategory(.ambient, mode: .default, options: [])
        try session.setActive(true)
    }

    /**
     * The welcome or a help page read aloud with no game open (AppAudio): .playback with .spokenAudio, so another
     * app's audio stops for it (a podcast pauses rather than talking over it) and comes back after, once the session is
     * let go (deactivate's notifyOthersOnDeactivation); then active. Android takes the audio focus for a moment
     * (AUDIOFOCUS_GAIN_TRANSIENT).
     */
    @Sendable static func spoken(_ session: AVAudioSession) throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    /// The inputs that are a headset's mic (AirPods and other Bluetooth headsets, wired and USB headsets, a car).
    static let headsetInputs: [AVAudioSession.Port] = [.bluetoothHFP, .headsetMic, .usbAudio, .carAudio]

    /// Which of these inputs to listen with: the first headset's, else the iPhone's own mic, else none.
    static func preferredInput(_ inputs: [AVAudioSession.Port]) -> Int? {
        inputs.firstIndex { headsetInputs.contains($0) } ?? inputs.firstIndex(of: .builtInMic)
    }

    /// The headset's mic preferred when headphones with one are connected, else the iPhone's: as the session is set
    /// up, and when the route changes. Nothing is changed when it is already the preferred input.
    static func preferHeadsetMic(_ session: AVAudioSession = .sharedInstance()) {
        let inputs = session.availableInputs ?? []
        guard let i = preferredInput(inputs.map(\.portType)) else { return }
        let pick = inputs[i]
        guard session.preferredInput?.uid != pick.uid else { return }
        do {
            try session.setPreferredInput(pick)
            log.info("listening with \(pick.portName, privacy: .public)")
        } catch {
            log.error("can't prefer \(pick.portName, privacy: .public): \(error, privacy: .public)")
        }
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

    /// Its events no longer reported, the session left as it is (AppAudio, handing the session over from one of its
    /// controllers to the other).
    func stopObserving() {
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
