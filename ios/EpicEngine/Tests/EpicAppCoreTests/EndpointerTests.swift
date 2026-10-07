// Endpointer.swift: when listening for one answer is over, and what the recogniser's errors mean (Listener.kt).

import Testing

@testable import EpicAppCore

struct EndpointerTests {
    let t0 = ContinuousClock.now

    private func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }

    @Test func nobodySpeakingIsASilenceAfterSixSeconds() {
        var e = Endpointer(at: t0)
        #expect(e.tick(at: at(5_900)) == .wait)
        #expect(e.tick(at: at(6_000)) == .silence)
        #expect(e.tick(at: at(9_000)) == .wait)          // once
        // Blank partials aren't speech.
        var blank = Endpointer(at: t0)
        blank.partial("  ", at: at(1_000))
        #expect(blank.tick(at: at(6_000)) == .silence)
    }

    @Test func wordsThatStopChangingAreTheAnswer() {
        var e = Endpointer(at: t0)
        e.partial("yes", at: at(2_000))
        #expect(e.tick(at: at(3_100)) == .wait)
        e.partial("yes please", at: at(3_100))
        e.partial("yes please", at: at(3_900))           // the same words: no change
        #expect(e.tick(at: at(4_200)) == .wait)
        #expect(!e.endingAudio)
        #expect(e.tick(at: at(4_300)) == .endAudio)
        #expect(e.endingAudio)
        #expect(e.words == "yes please")
        #expect(e.tick(at: at(7_200)) == .wait)
        // No final result after that: the words heard are the answer.
        #expect(e.tick(at: at(7_300)) == .giveUp)
        #expect(e.tick(at: at(9_000)) == .wait)
        #expect(!e.endingAudio)
    }

    @Test func listeningStopsAfterTwentySeconds() {
        var e = Endpointer(at: t0)
        for ms in stride(from: 500, to: 20_000, by: 500) {
            e.partial("word \(ms)", at: at(ms))
            #expect(e.tick(at: at(ms)) == .wait)
        }
        #expect(e.tick(at: at(20_000)) == .endAudio)
    }

    typealias Code = Endpointer.ErrorCode

    @Test func errorsAreReadAsAndroidReadsItsOwn() {
        func outcome(_ domain: String, _ code: Int, onDevice: Bool = true, interrupted: Bool = false,
                     words: String? = nil) -> ListenOutcome {
            Endpointer.outcome(domain: domain, code: code, onDevice: onDevice, interrupted: interrupted, words: words)
        }
        // No speech: as if nobody answered (Android's ERROR_SPEECH_TIMEOUT).
        #expect(outcome(Code.assistantDomain, Code.noSpeech) == .silence)
        // Cancellations are the game's own doing.
        #expect(outcome(Code.assistantDomain, Code.cancelled) == .ignore)
        #expect(outcome(Code.localDomain, Code.requestCancelled) == .ignore)
        // No recogniser for the language, or Siri and Dictation off: typing and buttons (ERROR_LANGUAGE_*).
        #expect(outcome(Code.localDomain, 201) == .unavailable)
        #expect(outcome(Code.localDomain, 102) == .unavailable)
        // A server recogniser with no network (ERROR_NETWORK); on the device a network error is passing trouble.
        #expect(outcome(Code.urlDomain, -1009, onDevice: false) == .unavailable)
        #expect(outcome(Code.urlDomain, -1009, onDevice: true) == .silence)
        // Other trouble: as if nobody answered.
        #expect(outcome(Code.speechDomain, 1) == .silence)
        #expect(outcome("Other", 7) == .silence)
        // After an interruption or a route change, nothing (the game pauses itself), and never unavailable.
        #expect(outcome(Code.localDomain, 201, interrupted: true) == .ignore)
        #expect(outcome(Code.assistantDomain, Code.noSpeech, interrupted: true) == .ignore)
        // Words already heard when the recogniser failed to finish: they are the answer.
        #expect(outcome(Code.assistantDomain, Code.noSpeech, words: " yes ") == .heard(["yes"]))
        #expect(outcome(Code.assistantDomain, Code.noSpeech, words: " ") == .silence)
    }

    /// A final result with no words is speech only if words came while listening; else nobody spoke (Listener.kt's
    /// NO_MATCH with no partial words).
    @Test func aFinalResultWithNoWordsIsASilenceUnlessWordsCame() {
        #expect(Endpointer.outcome(final: ["yes", "yeah"], words: "") == .heard(["yes", "yeah"]))
        // fixed: a silent listen ended with an empty result was "…" and the question's else; now it's a silence.
        #expect(Endpointer.outcome(final: [], words: "") == .silence)
        #expect(Endpointer.outcome(final: [], words: "  ") == .silence)
        #expect(Endpointer.outcome(final: [], words: "mumble") == .heard([]))
    }
}
