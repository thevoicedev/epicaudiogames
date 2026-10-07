// AnswersTest.kt: answers the games used to take the wrong way.

import Testing

@testable import EpicEngine

/**
 * Answers the games used to take the wrong way: a negated or unsure answer taken as a yes (or "I don't know" as a
 * no), and "to", "for", "won" or "oh" read as numbers. These depart from the Alexa skills on purpose.
 */
struct AnswersTests {
    /// The answer [said] is taken as at [node], or nil.
    private func taken(_ map: GameMap, _ node: String, _ said: String) throws -> Answer? {
        let ask = try #require(try map.node(node).ask)
        return try Matcher.match(map, ask, map.vars, said).index.map { ask.answers[$0] }
    }

    private func isYes(_ a: Answer?) -> Bool { if case .yes? = a?.match { true } else { false } }
    private func isNo(_ a: Answer?) -> Bool { if case .no? = a?.match { true } else { false } }

    private func goes(_ a: Answer?) -> String? { if case .to(let node)? = a?.go { node } else { nil } }

    private func choice(_ a: Answer?) -> Value? { if case .assign(let v)? = a?.set["choice"] { v } else { nil } }

    @Test func aNegatedOrUnsureAnswerIsNeitherYesNorNo() throws {
        let asks = [("frootopia", "fr-1a"), ("signal-decoders", "ai-open-2"), ("alien-customs", "L0_intro"),
                    ("pirate-quest", "ac-3a2")]
        for (game, node) in asks {
            let map = try TestRepo.load(game)
            #expect(isYes(try taken(map, node, "yes")), "\(game): yes")
            for said in ["I'm not sure", "of course not", "definitely not", "I'm not ready", "probably not",
                         "I don't know", "no idea"] {
                let a = try taken(map, node, said)
                #expect(!isYes(a), "\(game): \"\(said)\" is a yes")
                #expect(!(isNo(a) && ["I don't know", "no idea"].contains(said)), "\(game): \"\(said)\" is a no")
            }
        }
        let froot = try TestRepo.load("frootopia")
        #expect(isYes(try taken(froot, "fr-1a", "of course")))
        #expect(isNo(try taken(froot, "fr-1a", "I guess not")))          // "guess not" is a no word
        #expect(isNo(try taken(froot, "fr-1a", "no I'm not ready")))
        // Still heard, so the app doesn't take another of the recogniser's guesses ("of course") instead.
        let s = Session(froot)
        try s.restore(Saved(node: "fr-1a", vars: [:], ended: false))
        for said in ["I'm not sure", "of course not", "I don't know"] { #expect(try s.understands(said), "\(said)") }
        #expect(try !s.understands("banana"))
    }

    @Test func notTrueIsFalse() throws {
        // fixed: "not true" was a true (the skill's parseTrueFalse looks for "true" first); now it's a false
        let map = try TestRepo.load("leaning-tower-of-pizza")
        let node = try #require(map.nodes.first { $0.key.hasPrefix("q_") && $0.value.ask != nil }?.key)
        let truth = try taken(map, node, "true")?.go
        let falsehood = try taken(map, node, "false")?.go
        #expect(truth != falsehood)
        for said in ["not true", "that's not true"] { #expect(try taken(map, node, said)?.go == falsehood, "\(said)") }
        #expect(try taken(map, node, "not false")?.go == truth)
        #expect(try taken(map, node, "I'm not too sure") == nil)      // a mishear of true, said with "not": neither
    }

    @Test func aChoiceStillTakesItsOpposite() throws {
        let map = try TestRepo.load("signal-decoders")
        #expect(choice(try taken(map, "ai-choice", "don't follow it")) == "hide")
        #expect(choice(try taken(map, "ai-choice", "follow it")) == "follow")
        // fixed: the "not" of "not sure" made it a "don't follow", so it hid
        #expect(try taken(map, "ai-choice", "I'm not sure, follow") == nil)
    }

    @Test func toAndForArentNumbersOnTheirOwn() throws {
        // fixed: "I want to play" read as 2 and picked story 2; "go for it" as 4
        let wolf = try TestRepo.load("the-werewolf")
        func at(_ said: String) throws -> String? { goes(try taken(wolf, "offer", said)) }
        for said in ["I want to play", "yes I want to play", "I'm ready to play"] {
            #expect(try at(said) == "offer_yes", "\(said)")
        }
        #expect(try at("four") == "offer_n4")
        #expect(try at("I'd love to") != "offer_n2")
        #expect(try at("go for it") != "offer_n4")

        // A request to hear the puzzle again isn't a guess.
        let s = Session(try TestRepo.load("signal-decoders"))
        try s.restore(Saved(node: "ai3-p2", vars: ["tries": 0.0], ended: false))
        #expect(try s.answer("I need to listen to it again").heard?.how != "digits")
        #expect(s.vars["tries"] == 0.0)
        try s.restore(Saved(node: "ai5-p1", vars: ["tries": 0.0], ended: false))
        #expect(try s.answer("one zero").visited.contains("ai5-p1-yes"))
    }
}
