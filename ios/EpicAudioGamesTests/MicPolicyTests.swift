// MicPolicyTest.kt and CircleActionTest.kt: whether the game opens the mic by itself, and its one button's names.

import Foundation
import Testing
@testable import EpicAudioGames

/// Whether the game opens the mic by itself: each "Open the microphone by itself" setting, with VoiceOver on and off.
@MainActor
struct MicPolicyTests {
    @Test func byDefaultItListensByItselfOnlyWithoutAScreenReader() {
        #expect(MicPolicy.listensByItself(policy: .notWithScreenReader, screenReaderOn: false))
        #expect(!MicPolicy.listensByItself(policy: .notWithScreenReader, screenReaderOn: true))
    }

    @Test func alwaysListensByItselfWithOrWithoutOne() {
        #expect(MicPolicy.listensByItself(policy: .always, screenReaderOn: false))
        #expect(MicPolicy.listensByItself(policy: .always, screenReaderOn: true))
    }

    @Test func neverListensByItselfWithOrWithoutOne() {
        #expect(!MicPolicy.listensByItself(policy: .never, screenReaderOn: false))
        #expect(!MicPolicy.listensByItself(policy: .never, screenReaderOn: true))
    }

    @Test func theSettingStartsAtNotWithAScreenReader() throws {
        let name = "MicPolicyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(AppSettings(defaults: defaults).micAuto == .notWithScreenReader)
    }
}

/// The game's state, as CircleAction.of takes it.
private struct GameState: CustomStringConvertible {
    let paused, speaking, listening, end, ask, micAllowed, micWorks: Bool

    var description: String {
        "paused \(paused), speaking \(speaking), listening \(listening), end \(end), ask \(ask), "
            + "micAllowed \(micAllowed), micWorks \(micWorks)"
    }

    /// All 128.
    static let all: [GameState] = (0..<128).map { bits in
        func bit(_ i: Int) -> Bool { (bits & (1 << i)) != 0 }
        return GameState(
            paused: bit(0), speaking: bit(1), listening: bit(2), end: bit(3), ask: bit(4), micAllowed: bit(5),
            micWorks: bit(6))
    }
}

/**
 * The game's one button (the talking circle, Magic Tap, the headphones' button): docs/DESIGN.md's table of names and
 * states, and which action wins, over every combination of the game's state; and the Talk button's name, from the same
 * table.
 */
@MainActor
struct CircleActionTests {
    private func action(_ s: GameState) -> CircleAction? {
        CircleAction.of(
            paused: s.paused, speaking: s.speaking, listening: s.listening, end: s.end, ask: s.ask,
            micAllowed: s.micAllowed, micWorks: s.micWorks)
    }

    /// Not paused, speaking, listening or at an end.
    private var waiting: [GameState] {
        GameState.all.filter { !$0.paused && !$0.speaking && !$0.listening && !$0.end }
    }

    @Test func namesAndStatesAreTheDesignTables() {
        let table: [(action: CircleAction, label: String, state: String, enabled: Bool)] = [
            (.carryOn, "Carry on", "Paused", true),
            (.skip, "Skip", "Speaking", true),
            (.stopListening, "Stop listening", "Listening", true),
            (.talk, "Talk", "Your turn", true),
            (.micRefused, "Talk (the microphone is off)", "Your turn", true),
            (.noRecognition, "Talk (speech recognition isn't available)", "Your turn", true),
            (.wait, "Talk", "Wait for the question", false),
        ]
        #expect(table.map { $0.action } == CircleAction.allCases)
        for row in table {
            #expect(row.action.label == row.label, "\(row.action)")
            #expect(row.action.state == row.state, "\(row.action)")
            #expect(row.action.enabled == row.enabled, "\(row.action)")
        }
    }

    @Test func pausedItCarriesOnWhateverElse() {
        for s in GameState.all where s.paused {
            #expect(action(s) == .carryOn, "\(s)")
        }
    }

    @Test func speakingItSkips() {
        for s in GameState.all where !s.paused && s.speaking {
            #expect(action(s) == .skip, "\(s)")
        }
    }

    @Test func listeningItStopsListening() {
        for s in GameState.all where !s.paused && !s.speaking && s.listening {
            #expect(action(s) == .stopListening, "\(s)")
        }
    }

    @Test func atAnEndItDoesNothing() {
        for s in GameState.all where !s.paused && !s.speaking && !s.listening && s.end {
            #expect(action(s) == nil, "\(s)")
        }
    }

    @Test func withNoQuestionYetItWaitsDisabled() {
        for s in waiting where !s.ask {
            #expect(action(s) == .wait, "\(s)")
            #expect(action(s)?.enabled == false, "\(s)")
        }
    }

    @Test func askedItTalksOrSaysWhyItCant() {
        let asked = waiting.filter(\.ask)
        #expect(asked.count == 4)
        for s in asked {
            // The mic not allowed comes first: a tap asks for it, whether or not the recogniser works.
            let expected: CircleAction = !s.micAllowed ? .micRefused : !s.micWorks ? .noRecognition : .talk
            #expect(action(s) == expected, "\(s)")
        }
    }

    @Test func theTalkButtonIsTheCircleWithAQuestionAsked() {
        // Whatever the voice is doing (while it speaks, the Talk button cuts it short and listens: Talk, not Skip).
        for s in GameState.all {
            let asked = GameState(
                paused: false, speaking: false, listening: s.listening, end: false, ask: true,
                micAllowed: s.micAllowed, micWorks: s.micWorks)
            #expect(CircleAction.mic(listening: s.listening, micAllowed: s.micAllowed, micWorks: s.micWorks)
                == action(asked), "\(s)")
        }
    }

    @Test func theTalkButtonSaysTalkStopListeningOrWhyItCant() {
        #expect(CircleAction.mic(listening: true, micAllowed: true, micWorks: true).label == "Stop listening")
        #expect(CircleAction.mic(listening: false, micAllowed: true, micWorks: true).label == "Talk")
        #expect(CircleAction.mic(listening: false, micAllowed: false, micWorks: true).label
            == "Talk (the microphone is off)")
        #expect(CircleAction.mic(listening: false, micAllowed: false, micWorks: false).label
            == "Talk (the microphone is off)")
        #expect(CircleAction.mic(listening: false, micAllowed: true, micWorks: false).label
            == "Talk (speech recognition isn't available)")
        // Never the circle's other actions, and never disabled: the Talk button always does something.
        let all = Set(GameState.all.map {
            CircleAction.mic(listening: $0.listening, micAllowed: $0.micAllowed, micWorks: $0.micWorks)
        })
        let talking: Set<CircleAction> = [.stopListening, .talk, .micRefused, .noRecognition]
        #expect(all == talking)
        #expect(all.allSatisfy { $0.enabled })
    }
}
