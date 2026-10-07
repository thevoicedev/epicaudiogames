// Listener.kt's SpeechRecognizer session (startListening to its results): the mic and the recogniser for one answer.

import AVFoundation
import os
import Speech

/**
 * The mic and the recogniser for one answer: an input-only AVAudioEngine of its own (the mic is on only while
 * listening, apart from the engine the turns play on), its tap feeding an SFSpeechAudioBufferRecognitionRequest.
 *
 * Nonisolated: the tap runs on an audio thread and the recogniser calls back on its own queue, and a closure made in
 * main-actor code traps there (Swift 6 checks its isolation when it runs). So they are made here, and every event
 * reaches the main actor through DispatchQueue.main.
 */
nonisolated final class SpeechCapture: @unchecked Sendable {
    enum Event: Sendable {
        /// The words so far (the best guess).
        case partial(String)
        /// The recogniser's guesses, best first, once it has finished.
        case final([String])
        case failed(domain: String, code: Int)
        /// The sound level, 0 to 1, 20 times a second.
        case level(Float)
    }

    /// No mic to listen with (an input with no channels or sample rate).
    struct NoInput: Error {}

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "speech")

    let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private let micOn = OSAllocatedUnfairLock(initialState: false)

    /// Starts listening with [recognizer], on the device when [onDevice]. [onEvent] is called on the main actor.
    init(
        recognizer: SFSpeechRecognizer, hints: [String], onDevice: Bool,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) throws {
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = hints
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NoInput() }

        @Sendable func send(_ event: Event) {
            DispatchQueue.main.async { MainActor.assumeIsolated { onEvent(event) } }
        }
        let request = request
        let meter = LevelMeter()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            if let level = meter.level(buffer) { send(.level(level)) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        micOn.withLock { $0 = true }
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                if result.isFinal {
                    send(.final(Self.guesses(result)))
                } else {
                    send(.partial(result.bestTranscription.formattedString))
                }
            } else if let error {
                let e = error as NSError
                send(.failed(domain: e.domain, code: e.code))
            }
        }
    }

    deinit {
        stopMic()
        task?.cancel()
    }

    /// The answer is over: the mic goes off, and the recogniser finishes what it has (its final result comes next).
    func endAudio() {
        stopMic()
        request.endAudio()
    }

    /// Stops listening, reporting nothing more (the recogniser's cancellation error is the caller's to drop).
    func cancel() {
        stopMic()
        task?.cancel()
        task = nil
    }

    private func stopMic() {
        let wasOn = micOn.withLock { on in
            defer { on = false }
            return on
        }
        guard wasOn else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The best guess, then the others (Listener.kt's RESULTS_RECOGNITION, best first), each once, none blank.
    static func guesses(_ result: SFSpeechRecognitionResult) -> [String] {
        var out: [String] = []
        for t in [result.bestTranscription] + result.transcriptions {
            let text = t.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && !out.contains(text) { out.append(text) }
        }
        return out
    }
}

/**
 * The mic's level for the listening ring: the buffer's RMS in dBFS, from a quiet room (-55 dB) to speaking up close
 * (-15 dB), as 0 to 1 (Listener.kt maps the recogniser's rmsdB the same way), at most 20 times a second.
 */
nonisolated final class LevelMeter: @unchecked Sendable {
    private let last = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private static let every = AVAudioTime.hostTime(forSeconds: 0.05)

    func level(_ buffer: AVAudioPCMBuffer) -> Float? {
        let now = mach_absolute_time()
        let due = last.withLock { t in
            guard now &- t >= Self.every else { return false }
            t = now
            return true
        }
        guard due, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        return Self.level(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }

    static func level(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return min(max((db + 55) / 40, 0), 1)
    }
}
