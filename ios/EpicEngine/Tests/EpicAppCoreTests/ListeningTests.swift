// Listening.swift: the hints a listener is given for a question, and the protocols' fakes for the app's tests.

import Testing

@testable import EpicAppCore

struct ListeningTests {
    private func answer(_ match: Match) -> Answer {
        Answer(match: match, go: .to("x"), set: [:], whenCond: nil, opposite: nil)
    }

    @Test func hintsAreTheButtonsThenThePhrases() {
        let ask = Ask(
            reprompt: [],
            answers: [
                answer(.yes(extra: [Phrase("sure thing", false)])),
                answer(.words([Phrase("the usa", false), Phrase("france", true)])),
                answer(.anyText),
                answer(.no(extra: [])),
            ],
            otherwise: nil,
            buttons: [
                AnswerButton(label: "Answer", value: "yes"), AnswerButton(label: "the USA", value: "USA"),
                AnswerButton(label: " Yes ", value: "yes"), AnswerButton(label: "", value: " "),
            ]
        )
        #expect(ListenHints.of(ask) == ["Answer", "yes", "the USA", "USA", "Yes", "sure thing", "the usa", "france"])
        #expect(ListenHints.of(nil).isEmpty)
    }

    @Test func hintsAreCapped() {
        let buttons = (0..<150).map { AnswerButton(label: "b\($0)", value: "b\($0)") }
        let hints = ListenHints.of(Ask(reprompt: [], answers: [], otherwise: nil, buttons: buttons))
        #expect(hints.count == ListenHints.limit)
        #expect(hints.first == "b0")
    }

    /// The protocols take main-actor fakes, as the app's GameController tests will.
    @MainActor
    @Test func fakesConform() {
        final class Audio: TurnPlaying {
            var onFinished: (@MainActor @Sendable () -> Void)?
            var onStalled: (@MainActor @Sendable () -> Void)?
            var played: [[Step]] = []
            var stops = 0
            func play(_ steps: [Step]) { played.append(steps) }
            func stop() { stops += 1 }
            func position() -> ClipPosition? { nil }
            func clipsDone() -> Int { 0 }
            func release() {}
        }
        final class Ears: Listening {
            var events = ListenerEvents()
            var isAvailable: Bool { true }
            var hints: [String] = []
            func start(hints: [String]) { self.hints = hints }
            func stop() {}
            func release() {}
        }
        @MainActor final class Heard {
            var guesses: [String] = []
        }
        let audio = Audio()
        let ears = Ears()
        let deps = GameDependencies(saves: MemorySaveStore(), audio: audio, listener: ears)
        deps.audio.play([clip("a")])
        deps.audio.skip()
        #expect(audio.played.count == 1)
        #expect(audio.stops == 1)
        let heard = Heard()
        ears.events = ListenerEvents(heard: { heard.guesses = $0 })
        deps.listener.start(hints: ["yes"])
        #expect(ears.hints == ["yes"])
        ears.events.heard(["yes", "yeah"])
        #expect(heard.guesses == ["yes", "yeah"])
    }
}
