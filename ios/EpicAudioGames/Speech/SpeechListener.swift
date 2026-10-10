// Listener.kt: listens for one answer with the device's speech recogniser (on the device where it can).

import AVFoundation
import EpicAppCore
import Foundation
import Speech

/**
 * Listens for one answer with the device's speech recogniser, SFSpeechRecognizer in the player's English (D9), on the
 * device where it can and on Apple's servers where it can't. Reports the words as they come, the recogniser's
 * guesses (best first), speech it couldn't make out (no guesses), silence, and the sound level. iOS's recogniser
 * doesn't decide when an answer is over, as Android's does: the Endpointer does, on a 100 ms tick. One is made for
 * each game opened, as Listener.kt is.
 *
 * Its mic (MicInput) stays on from when the game opens (or the mic is allowed) until the game closes, so that it can
 * listen with the phone locked; each answer is a new request and recognition task on it ([start]).
 *
 * The game plays the listening sound first and says when it will have been heard out ([start]'s after): the mic is
 * heard from then on (MicInput's gate), and the time to answer counts from there (Settings › Time to answer, read at
 * each listen: the Endpointer's 6, 10 or 15 seconds for the first word, and 1.2 or 2 for the words to stop).
 */
final class SpeechListener: Listening {
    var events = ListenerEvents()
    /// A recogniser for the language exists (Listener.available).
    let isAvailable: Bool

    private let recognizer: SFSpeechRecognizer?
    /// The player's time to answer (Settings), read at each listen.
    private let answerTime: () -> AnswerTime
    /// The mic, on while the game is open (a new one after the media services restart).
    private(set) var mic = MicInput()
    private var capture: SpeechCapture?
    private var endpointer: Endpointer?
    private var ticker: Task<Void, Never>?
    /// Bumped by every start and stop: what the recogniser reports for a listen that's over is let go.
    private var session = 0
    private var onDevice = false
    /// The listen's hints, and when its mic is heard from, for trying it again on the server.
    private var hints: [String] = []
    private var after: ContinuousClock.Instant?
    /// The device's recogniser turned out not to have the language (Listener.kt's offline): Apple's servers instead.
    private static var onDeviceFails = false
    /// The audio session was interrupted, or its route changed, while listening: the error that follows is dropped.
    private var interrupted = false

    init(locale: Locale = SpeechListener.locale, answerTime: @escaping () -> AnswerTime = { .normal }) {
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer != nil
        self.answerTime = answerTime
    }

    /// The engine the mic listens through (AppModel tells its configuration changes apart).
    var engine: AVAudioEngine? { mic.engine }

    /// D9: the player's first English language, if the recogniser has it; else US English.
    static var locale: Locale {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        for id in Locale.preferredLanguages where id.hasPrefix("en") {
            if supported.contains(id.replacingOccurrences(of: "_", with: "-")) { return Locale(identifier: id) }
        }
        return Locale(identifier: "en-US")
    }

    func start(hints: [String]) {
        start(hints: hints, after: nil)
    }

    /**
     * Listens for one answer to what the mic records from [after] on (when the listening sound will have been heard
     * out; nil, from now), with the time to answer counted from there. Listener.kt's start, which ListenSequence.kt
     * runs once the sound is over.
     */
    func start(hints: [String], after: ContinuousClock.Instant?) {
        stop()
        session += 1
        let id = session
        interrupted = false
        self.hints = hints
        self.after = after
        guard let recognizer, recognizer.isAvailable, SFSpeechRecognizer.authorizationStatus() == .authorized else {
            // No recogniser here now (Listener.kt's ERROR_LANGUAGE_UNAVAILABLE, ERROR_NETWORK): typing and buttons.
            SpeechCapture.log.info("no recogniser to listen with")
            later(id) { $0.events.unavailable() }
            return
        }
        onDevice = recognizer.supportsOnDeviceRecognition && !Self.onDeviceFails
        // The gate on the mic's own clock (host time), worked out once.
        let gate = after.map(Self.hostTime)
        do {
            capture = try SpeechCapture(
                input: mic, recognizer: recognizer, hints: hints, onDevice: onDevice, from: gate
            ) { [weak self] event in self?.received(event, id) }
        } catch is MicInput.NoInput {
            SpeechCapture.log.info("no mic to listen with")
            later(id) { $0.events.unavailable() }
            return
        } catch {
            // The mic couldn't start (Android's ERROR_AUDIO; in the background, iOS's cannotStartRecording): passing
            // trouble, not the player's silence.
            SpeechCapture.log.error("can't start listening: \(error, privacy: .public)")
            later(id) { $0.events.trouble() }
            return
        }
        let time = answerTime()
        endpointer = Endpointer(at: max(.now, after ?? .now), noSpeech: time.duration, settle: time.settle)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.session == id else { return }
                self.tick()
            }
        }
    }

    func stop() {
        session += 1
        end()
    }

    /// The game closing: listening stops, and so does the mic.
    func release() {
        stop()
        mic.stop()
    }

    // ----- The mic, on while the game is open -----

    /**
     * The mic on, if the game can listen (a recogniser, and the mic and speech recognition allowed), between answers
     * feeding nothing: as the game opens, as the mic is allowed, and as the app comes back to the screen. In the
     * foreground: iOS won't start it in the background.
     */
    func startMic() {
        guard isAvailable, MicPermission.granted else { return }
        do {
            try mic.start()
        } catch {
            MicInput.log.error("can't start the mic: \(error, privacy: .public)")
        }
    }

    /// The mic on again after it stopped itself (its input changed, an interruption ended), if it was on.
    func restartMic() {
        mic.restart()
    }

    /// The media services restarted: the mic's engine is no use. A new one, on if the old one was.
    func resetMic() {
        let wasOn = mic.isWanted
        stop()
        mic.stop()
        mic = MicInput()
        if wasOn { startMic() }
    }

    /// An interruption or a route change while listening: the recogniser's error that follows means nothing.
    func audioSessionChanged() {
        if capture != nil { interrupted = true }
    }

    // ----- One listen -----

    private func received(_ event: SpeechCapture.Event, _ id: Int) {
        guard id == session, capture != nil else { return }
        switch event {
        case .partial(let text):
            endpointer?.partial(text, at: .now)
            let t = Kt.trim(text)
            if !t.isEmpty { events.partial(t) }
        case .level(let level):
            if endpointer?.endingAudio != true { events.level(level) }
        case .final(let guesses):
            // No words, and none came while listening: nobody spoke (Listener.kt's NO_MATCH with no partials).
            finish(Endpointer.outcome(final: guesses, words: endpointer?.words ?? ""))
        case .failed(let domain, let code):
            let words = endpointer?.endingAudio == true ? endpointer?.words : nil
            let outcome = Endpointer.outcome(
                domain: domain, code: code, onDevice: onDevice, interrupted: interrupted, words: words)
            SpeechCapture.log.info("recogniser error \(domain, privacy: .public) \(code): \(String(describing: outcome))")
            if outcome == .unavailable && onDevice && domain == Endpointer.ErrorCode.localDomain {
                // The device can't recognise the language after all: the same listen again, on the server, the mic
                // still heard only from the gate (no listening sound again).
                Self.onDeviceFails = true
                start(hints: hints, after: after)
                return
            }
            // Dropped: the Endpointer still ends the listen (a silence, or the words heard).
            if outcome != .ignore { finish(outcome) }
        }
    }

    private func tick() {
        guard var e = endpointer else { return }
        let decision = e.tick(at: .now)
        endpointer = e
        switch decision {
        case .wait:
            break
        case .silence:
            finish(.silence)
        case .endAudio:
            capture?.endAudio()
            events.level(0)
        case .giveUp:
            finish(e.words.isEmpty ? .silence : .heard([e.words]))
        }
    }

    private func finish(_ outcome: ListenOutcome) {
        end()
        switch outcome {
        case .heard(let guesses): events.heard(guesses)
        case .silence: events.silence()
        case .unavailable: events.unavailable()
        case .trouble: events.trouble()
        case .ignore: break
        }
    }

    private func end() {
        ticker?.cancel()
        ticker = nil
        capture?.cancel()
        capture = nil
        endpointer = nil
    }

    /// [instant] on the mic's clock (the host time its buffers carry): now's host time, and how far off it is.
    nonisolated static func hostTime(_ instant: ContinuousClock.Instant) -> UInt64 {
        let wait = instant - .now
        let seconds = Double(wait.components.seconds) + Double(wait.components.attoseconds) / 1e18
        let now = mach_absolute_time()
        return seconds > 0 ? now + AVAudioTime.hostTime(forSeconds: seconds) : now
    }

    /// Reported after start() returns, as the recogniser's errors are, unless listening has stopped by then.
    private func later(_ id: Int, _ report: @escaping (SpeechListener) -> Void) {
        Task { [weak self] in
            guard let self, self.session == id else { return }
            report(self)
        }
    }
}
