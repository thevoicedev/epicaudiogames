// Listener.kt as SpeechListener ports it: the language it listens in (D9), and no recogniser meaning typing.

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

@MainActor
struct SpeechTests {
    @MainActor final class Heard {
        var unavailable = 0
        var other = 0
    }

    /// D9: the player's English, else US English.
    @Test func itListensInEnglish() {
        #expect(SpeechListener.locale.identifier.hasPrefix("en"))
    }

    /// Listener.available false (no recogniser for the language): the mic is off from the start, and asking it to
    /// listen says so later, as Android's onError does; a stop before then says nothing.
    @Test func noRecogniserForTheLanguageIsUnavailable() async throws {
        let listener = SpeechListener(locale: Locale(identifier: "xx-XX"))
        #expect(!listener.isAvailable)
        let heard = Heard()
        listener.events = ListenerEvents(
            heard: { _ in heard.other += 1 }, silence: { heard.other += 1 }, unavailable: { heard.unavailable += 1 })
        listener.start(hints: ["yes"])
        #expect(heard.unavailable == 0)
        for _ in 0..<50 where heard.unavailable == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(heard.unavailable == 1)
        listener.start(hints: [])
        listener.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard.unavailable == 1)
        #expect(heard.other == 0)
    }
}
