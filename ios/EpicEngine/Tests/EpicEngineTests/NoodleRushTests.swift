// NoodleRushTest.kt: Noodle Rush takes a yes or a no only as the whole answer, from a longer list.

import Testing

@testable import EpicEngine

/**
 * Noodle Rush takes a yes or a no only as the whole answer, as the skill's doNoodleAnswer does, from a longer list
 * than the skill's ("okay", "I do", "not now"), and the title takes being ready.
 */
struct NoodleRushTests {
    private let map: GameMap

    init() throws {
        map = try TestRepo.load("noodle-rush")
    }

    /// The answer to the title's "Are you ready to play?".
    private func title(_ said: String) throws -> Turn {
        let s = Session(map)
        _ = try s.start()
        return try s.answer(said)
    }

    @Test func theTitleTakesBeingReady() throws {
        // fixed: only the skill's own words were taken, so "I'm ready" or "okay" asked again
        for said in ["I'm ready", "yes I'm ready", "let's play", "yeah let's go", "okay", "sure thing", "yes okay"] {
            #expect(try title(said).node == "Page2", "\(said)")
        }
        for said in ["not now", "no thank you"] { #expect(try title(said).quit, "\(said)") }
        #expect(try title("I'm not sure").node == "Page1", "not a yes")
        #expect(try title("I have no idea").node == "Page1", "a no inside a sentence isn't the answer")
    }

    @Test func laterQuestionsTakeTheLongerListsToo() throws {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer("yes")
        #expect(try s.answer("I do").node == "go", "Page2: do you want to go inside?")
        let s2 = Session(map)
        _ = try s2.start()
        _ = try s2.answer("yes")
        #expect(try s2.answer("let's go").node == "Page2", "being ready is only the title's")
    }
}
