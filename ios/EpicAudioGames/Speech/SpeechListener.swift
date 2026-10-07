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
 */
final class SpeechListener: Listening {
    var events = ListenerEvents()
    /// A recogniser for the language exists (Listener.available).
    let isAvailable: Bool

    private let recognizer: SFSpeechRecognizer?
    private var capture: SpeechCapture?
    private var endpointer: Endpointer?
    private var ticker: Task<Void, Never>?
    /// Bumped by every start and stop: what the recogniser reports for a listen that's over is let go.
    private var session = 0
    private var onDevice = false
    /// The listen's hints, for trying it again on the server.
    private var hints: [String] = []
    /// The device's recogniser turned out not to have the language (Listener.kt's offline): Apple's servers instead.
    private static var onDeviceFails = false
    /// The audio session was interrupted, or its route changed, while listening: the error that follows is dropped.
    private var interrupted = false

    init(locale: Locale = SpeechListener.locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer != nil
    }

    /// The engine the mic is listening through, while it is (AppModel tells its configuration changes apart).
    var engine: AVAudioEngine? { capture?.engine }

    /// D9: the player's first English language, if the recogniser has it; else US English.
    static var locale: Locale {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        for id in Locale.preferredLanguages where id.hasPrefix("en") {
            if supported.contains(id.replacingOccurrences(of: "_", with: "-")) { return Locale(identifier: id) }
        }
        return Locale(identifier: "en-US")
    }

    func start(hints: [String]) {
        stop()
        session += 1
        let id = session
        interrupted = false
        self.hints = hints
        guard let recognizer, recognizer.isAvailable, SFSpeechRecognizer.authorizationStatus() == .authorized else {
            // No recogniser here now (Listener.kt's ERROR_LANGUAGE_UNAVAILABLE, ERROR_NETWORK): typing and buttons.
            SpeechCapture.log.info("no recogniser to listen with")
            later(id) { $0.events.unavailable() }
            return
        }
        onDevice = recognizer.supportsOnDeviceRecognition && !Self.onDeviceFails
        do {
            capture = try SpeechCapture(recognizer: recognizer, hints: hints, onDevice: onDevice) { [weak self] event in
                self?.received(event, id)
            }
        } catch is SpeechCapture.NoInput {
            SpeechCapture.log.info("no mic to listen with")
            later(id) { $0.events.unavailable() }
            return
        } catch {
            // The mic couldn't start (Android's ERROR_AUDIO): passing trouble, not the player's silence.
            SpeechCapture.log.error("can't start listening: \(error, privacy: .public)")
            later(id) { $0.events.trouble() }
            return
        }
        endpointer = Endpointer(at: .now)
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

    func release() {
        stop()
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
                // The device can't recognise the language after all: the same listen again, on the server.
                Self.onDeviceFails = true
                start(hints: hints)
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

    /// Reported after start() returns, as the recogniser's errors are, unless listening has stopped by then.
    private func later(_ id: Int, _ report: @escaping (SpeechListener) -> Void) {
        Task { [weak self] in
            guard let self, self.session == id else { return }
            report(self)
        }
    }
}
