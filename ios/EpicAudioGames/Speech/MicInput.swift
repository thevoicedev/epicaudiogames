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
 * The listening sound plays as an answer's feed starts, and the recogniser must never take it for words: a feed has a
 * gate ([Feed.from], a host time: when the sound will have been heard out), and what the mic recorded before it is
 * dropped, or cut off where a buffer straddles it ([admit]), before the recogniser or the level meter see it. Android
 * starts its recogniser after the sound instead (ListenSequence.kt).
 *
 * Nonisolated: the tap runs on an audio thread. The answer being fed is swapped under a lock.
 */
nonisolated final class MicInput: @unchecked Sendable {
    /// No mic to listen with (an input with no channels or sample rate).
    struct NoInput: Error {}

    /// What the tap feeds: one answer's request, its level meter, and its gate.
    struct Feed: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        let meter: LevelMeter
        let level: @Sendable (Float) -> Void
        /// Nothing recorded before this host time is heard (the listening sound, until it's over); nil: all of it.
        let from: UInt64?
    }

    /// What becomes of a buffer of the mic's at the gate ([admit]).
    enum Admit: Equatable, Sendable {
        /// All of it is heard.
        case pass
        /// None of it: it was all recorded before the gate.
        case drop
        /// Its first frames (this many) were recorded before the gate: the rest is heard.
        case trim(Int)
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
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            guard let feed = feeding.withLock({ $0 }) else { return }
            // Recorded before the gate, the listening sound: never heard (MicInput's doc).
            guard let heard = MicInput.gated(buffer, when: when, from: feed.from) else { return }
            feed.request.append(heard)
            if let level = feed.meter.level(heard) { feed.level(level) }
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

    /**
     * From now on, the mic's buffers go to [request], and their level to [level] (20 times a second): those recorded
     * from host time [from] on (the gate: when the listening sound will have been heard out), or all of them.
     */
    func feed(
        _ request: SFSpeechAudioBufferRecognitionRequest, from: UInt64? = nil,
        level: @escaping @Sendable (Float) -> Void
    ) {
        let feed = Feed(request: request, meter: LevelMeter(), level: level, from: from)
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

    // ----- The gate -----

    /**
     * What of a buffer of [frames] frames at [rate] a second, its first recorded at host time [start], is heard with
     * the gate at host time [from] (nil: no gate): all of it once it starts at or after the gate; none of it if it was
     * all recorded before; else the frames from the gate on. Pure: the tap's arithmetic (MicInputTests).
     */
    static func admit(start: UInt64, frames: Int, rate: Double, from: UInt64?) -> Admit {
        guard let from, start < from, frames > 0, rate > 0 else { return .pass }
        // The frames before the gate, a hair's leeway so that one ending exactly at it isn't lost to the rounding.
        let early = (AVAudioTime.seconds(forHostTime: from - start) * rate - 1e-6).rounded(.up)
        if early >= Double(frames) { return .drop }
        return early > 0 ? .trim(Int(early)) : .pass
    }

    /// [buffer] as the gate at host time [from] lets it through: itself, the part from the gate on, or nil. [when] is
    /// the tap's time for it: the host time it was recorded at, or else its arrival less its length.
    static func gated(_ buffer: AVAudioPCMBuffer, when: AVAudioTime, from: UInt64?) -> AVAudioPCMBuffer? {
        guard let from else { return buffer }
        let rate = buffer.format.sampleRate
        let frames = Int(buffer.frameLength)
        let start = when.isHostTimeValid
            ? when.hostTime
            : mach_absolute_time() &- AVAudioTime.hostTime(forSeconds: Double(frames) / max(rate, 1))
        switch admit(start: start, frames: frames, rate: rate, from: from) {
        case .pass: return buffer
        case .drop: return nil
        case .trim(let skip): return dropping(skip, of: buffer)
        }
    }

    /// [buffer] without its first [skip] frames, as a buffer of its own; nil if there's nothing left, or its samples
    /// aren't floats or 16-bit (dropped rather than let the sound through).
    static func dropping(_ skip: Int, of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let count = Int(buffer.frameLength) - skip
        guard skip >= 0, count > 0,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)) else {
            return nil
        }
        // Interleaved: one run of samples, [stride] to a frame; else one run per channel.
        let runs = buffer.format.isInterleaved ? 1 : Int(buffer.format.channelCount)
        let stride = buffer.stride
        if let from = buffer.floatChannelData, let to = out.floatChannelData {
            for r in 0..<runs { to[r].update(from: from[r].advanced(by: skip * stride), count: count * stride) }
        } else if let from = buffer.int16ChannelData, let to = out.int16ChannelData {
            for r in 0..<runs { to[r].update(from: from[r].advanced(by: skip * stride), count: count * stride) }
        } else {
            return nil
        }
        out.frameLength = AVAudioFrameCount(count)
        return out
    }
}
