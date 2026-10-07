// Listener.kt's SpeechRecognizer session (startListening to its results): the recogniser for one answer.

import AVFoundation
import os
import Speech

/**
 * The recogniser for one answer: an SFSpeechAudioBufferRecognitionRequest fed by the game's mic (MicInput, which
 * stays running between answers, so the game can listen with the phone locked), and its task.
 *
 * Nonisolated: the mic's tap runs on an audio thread and the recogniser calls back on its own queue, and a closure made
 * in main-actor code traps there (Swift 6 checks its isolation when it runs). So they are made here, and every event
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

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "speech")

    private let input: MicInput
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    /**
     * Starts listening with [recognizer] to [input] (started first if it isn't running: in the foreground it can be,
     * in the background it throws), on the device when [onDevice]. [onEvent] is called on the main actor.
     */
    init(
        input: MicInput, recognizer: SFSpeechRecognizer, hints: [String], onDevice: Bool,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) throws {
        self.input = input
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = hints
        try input.start()

        @Sendable func send(_ event: Event) {
            DispatchQueue.main.async { MainActor.assumeIsolated { onEvent(event) } }
        }
        input.feed(request) { send(.level($0)) }
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
        input.unfeed(request)
        task?.cancel()
    }

    /// The answer is over: the mic stops feeding it (it stays on), and the recogniser finishes what it has (its final
    /// result comes next).
    func endAudio() {
        input.unfeed(request)
        request.endAudio()
    }

    /// Stops listening, reporting nothing more (the recogniser's cancellation error is the caller's to drop).
    func cancel() {
        input.unfeed(request)
        task?.cancel()
        task = nil
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
