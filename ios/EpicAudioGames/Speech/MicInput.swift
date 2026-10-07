// No Kotlin counterpart: Android's recogniser opens the mic itself. On iOS the mic stays open while a game is.

import AVFoundation
import os
import Speech

/**
 * The mic, kept running the whole time a game is open with the mic allowed: an input-only AVAudioEngine (apart from
 * the engine the turns play on; voice processing stays off, D13) with one tap. Between answers its buffers go
 * nowhere; while the game listens they feed that answer's SFSpeechAudioBufferRecognitionRequest ([feed]).
 *
 * Why it isn't started for each answer: iOS refuses to start recording from the background
 * (AVAudioSession.ErrorCode.cannotStartRecording), so with the phone locked a mic opened per answer would never
 * listen. Started in the foreground (as the game opens, or as the mic is allowed), it goes on listening while the
 * phone is locked. It stops itself when its input changes (a route change, an interruption): AppModel starts it again
 * (restart).
 *
 * Nonisolated: the tap runs on an audio thread. The answer being fed is swapped under a lock.
 */
nonisolated final class MicInput: @unchecked Sendable {
    /// No mic to listen with (an input with no channels or sample rate).
    struct NoInput: Error {}

    /// What the tap feeds: one answer's request, and its level meter.
    struct Feed: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        let meter: LevelMeter
        let level: @Sendable (Float) -> Void
    }

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "mic")

    let engine = AVAudioEngine()
    private let feeding = OSAllocatedUnfairLock<Feed?>(initialState: nil)
    /// The tap is installed (it is installed again with the input's format at each start).
    private let tapped = OSAllocatedUnfairLock(initialState: false)
    /// Started on purpose, and not stopped since: what restart() starts again after the engine stopped itself.
    private let wanted = OSAllocatedUnfairLock(initialState: false)

    var isRunning: Bool { engine.isRunning }

    /// Whether it should be running (started, and not stopped since), even if the engine has stopped itself.
    var isWanted: Bool { wanted.withLock { $0 } }

    /**
     * Starts the mic if it isn't running, its tap in the input's format now. Throws [NoInput] with no mic, or the
     * engine's error (in the background: cannotStartRecording). If the session was left inactive (an interruption),
     * it is made active and the start tried again, as AudioGraph.start does.
     */
    func start() throws {
        wanted.withLock { $0 = true }
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NoInput() }
        removeTap()
        let feeding = feeding
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let feed = feeding.withLock({ $0 }) else { return }
            feed.request.append(buffer)
            if let level = feed.meter.level(buffer) { feed.level(level) }
        }
        tapped.withLock { $0 = true }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
            } catch {
                removeTap()
                throw error
            }
        }
        Self.log.info("mic on: \(format.sampleRate) Hz, \(format.channelCount) channel(s)")
    }

    /// Starts it again if it should be running and has stopped (its input changed, an interruption ended).
    func restart() {
        guard isWanted, !engine.isRunning else { return }
        do {
            try start()
        } catch {
            Self.log.error("can't start the mic again: \(error, privacy: .public)")
        }
    }

    /// The mic off (the game closing, the media services restarting).
    func stop() {
        wanted.withLock { $0 = false }
        feeding.withLock { $0 = nil }
        engine.stop()
        removeTap()
    }

    /// From now on, the mic's buffers go to [request], and their level to [level] (20 times a second).
    func feed(_ request: SFSpeechAudioBufferRecognitionRequest, level: @escaping @Sendable (Float) -> Void) {
        let feed = Feed(request: request, meter: LevelMeter(), level: level)
        feeding.withLock { $0 = feed }
    }

    /// The mic's buffers go nowhere again, if they were going to [request] (a later answer's feed is left alone).
    func unfeed(_ request: SFSpeechAudioBufferRecognitionRequest) {
        let id = ObjectIdentifier(request)
        feeding.withLock { feed in
            if let f = feed, ObjectIdentifier(f.request) == id { feed = nil }
        }
    }

    /// Whether buffers are going to a request now.
    var isFeeding: Bool { feeding.withLock { $0 != nil } }

    private func removeTap() {
        let was = tapped.withLock { t in
            defer { t = false }
            return t
        }
        if was { engine.inputNode.removeTap(onBus: 0) }
    }
}
