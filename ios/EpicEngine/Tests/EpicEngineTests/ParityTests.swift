// ParityTest.kt: answers played through the maps take the same paths as in the Alexa skills.

import Testing

@testable import EpicEngine

extension Session {
    /// The session put at [node], with these variables (the rest as at the start).
    fileprivate func at(_ node: String, _ vars: VarStore = [:]) throws -> Session {
        try restore(Saved(node: node, vars: vars, ended: false))
        return self
    }
}

extension Turn {
    fileprivate func plays() -> [String] {
        steps.compactMap { if case .play(let p) = $0 { p.path } else { nil } }
    }
}

/**
 * Answers played through the maps take the same paths as in the Alexa skills (the rules are in each game's
 * alexa/lambda/Games/<game>/index.js in all-minigames-sites).
 */
struct ParityTests {
    @Test func noodleRush() throws {
        let map = try TestRepo.load("noodle-rush")
        let s = Session(map) { _ in 0 }
        #expect(try s.start().node == "Page1")
        // doNoodleNo: "no" on the title leaves with "No problem!".
        do {
            let it = try s.answer("no")
            #expect(it.quit)
            #expect(it.plays() == ["common/no-problem"])
        }
        _ = try s.restart()
        #expect(try s.answer("yes").node == "Page2")
        // doNoodleYes: no "yes" branch, one forward option ("inside"): yes takes it.
        #expect(try s.answer("yeah").node == "go")
        #expect(try s.at("Page2").answer("nope").node == "walkaway")
        #expect(try s.at("go").answer("I'll skip the line").node == "cut")
        #expect(try s.at("go").answer("wait patiently").node == "wait")
        // The longest phrase wins.
        #expect(try s.at("rehearse").answer("the red one").node == "redlever")
        #expect(try s.at("rehearse").answer("green").node == "show")
        // The "nana" flag hands "search" over to "search-nana".
        do {
            let it = try s.at("chase", ["nana": true]).answer("yes")
            #expect(it.node == "search-nana")
            #expect(!it.visited.contains("search"))
        }
        #expect(try s.at("chase").answer("yes").node == "search")
        // A one-option question: "no" gives up.
        do {
            let it = try s.at("sellmore").answer("no")
            #expect(it.quit)
            #expect(it.plays() == ["common/give-up"])
        }
        // repromptNoodle: anything else plays the question again.
        do {
            let it = try s.at("go").answer("banana")
            #expect(it.node == "go")
            #expect(it.plays() == ["prompts/queue"])
        }
        // The skill has no repeat intent: "repeat" plays the question again, like any answer it doesn't know.
        #expect(try s.at("go").answer("say that again").plays() == ["prompts/queue"])
        do {
            let it = try s.at("order").answer("spicy")
            #expect(it.node == "dragonfire")
            #expect(it.end?.title == "Dragon Fire Ending")
            #expect(it.ask == nil)
        }
    }

    @Test func frootopia() throws {
        let map = try TestRepo.load("frootopia")
        let s = Session(map)
        #expect(try s.start().node == "fr-1")
        #expect(try s.answer("fine").node == "fr-2")                              // YES_EXACT
        do {
            let it = try s.at("fr-1").answer("I'm fine")                          // not a whole-answer "fine"
            #expect(it.node == "fr-1")
            #expect(it.plays() == ["common/unhandled"])
        }
        #expect(try s.at("fr-1").answer("I guess not").node == "fr-1a")          // "guess not" beats "i guess"
        #expect(try s.at("fr-1").answer("don't go").node == "fr-1a")             // "don't" beats "go"
        #expect(try s.at("fr-1").answer("repeat that").plays() == ["scenes/fr-1"])
        #expect(try s.at("fr-9").answer("let's fight").node == "fr-10a")          // NODE_CHOICE_WORDS
        #expect(try s.at("fr-9").answer("run away").node == "fr-10b")
        #expect(try s.at("fr-12").answer("a pipe please").node == "fr-13")        // NAMED_ANSWER_IS
        #expect(try s.at("fr-12").answer("no thanks").node == "fr-12a")
        do {
            let it = try s.at("fr-gameover-1").answer("yes")
            #expect(it.visited == ["_restart", "fr-1"])
            #expect(it.plays().first == "common/restart")
        }
        do {
            let it = try s.at("fr-gameover-1").answer("no")
            #expect(it.quit)
            #expect(it.plays() == ["scenes/fr-exit"])
        }
        // The endings: the scene, then the sting, then story 2 in the pack.
        for ending in ["fr-54", "fr-55"] {
            let found = map.nodes.values.lazy.compactMap { n -> (String, String)? in
                guard let a = n.ask?.answers.first(where: { $0.go == .to(ending) }) else { return nil }
                if case .yes = a.match { return (n.id, "yes") }
                return (n.id, "no")
            }.first
            let (from, said) = try #require(found, "no answer goes to \(ending)")
            let it = try s.at(from).answer(said)
            #expect(it.node == ending)
            #expect(it.plays() == ["scenes/\(ending)", "scenes/fr-sting"])
            #expect(it.end?.kind == "chapter")
            #expect(it.end?.locked == "frootopia-stories")
        }
    }

    @Test func signalDecoders() throws {
        let map = try TestRepo.load("signal-decoders")
        let s = Session(map)
        do {
            let it = try s.start()
            #expect(it.visited == ["ai-title", "ai-open-1", "ai-open-2"])
            #expect(it.node == "ai-open-2")
        }
        // "Not sure" (a "sure" in it) asks again, with the sorry clip.
        do {
            let it = try s.answer("I'm not sure")
            #expect(it.node == "ai-open-2")
            #expect(it.plays() == ["common/unhandled", "prompts/ai-open-2"])
        }
        #expect(try s.answer("no thanks").node == "ai-open-no")
        #expect(try s.answer("nope").quit)
        #expect(try s.at("ai-open-2").answer("yes").node == "ai-p1")

        // Puzzle 1: wrong, the hint; wrong again, the reveal, which flows on; tries back to 0.
        do {
            let it = try s.at("ai-p1").answer("a c a")
            #expect(it.node == "ai-p1-hint")
            #expect(s.vars["tries"] == 1.0)
        }
        do {
            let it = try s.answer("c c a")
            #expect(Set(it.visited).isSuperset(of: ["ai-p1-reveal", "ai-p1-yes"]))
            #expect(it.node == "ai-s3c")
            #expect(s.vars["tries"] == 0.0)
        }
        #expect(try s.at("ai-p1").answer("see a see").node == "ai-s3c")
        #expect(try s.at("ai-p1").answer("c ac").node == "ai-s3c")                   // a spelled run
        #expect(try s.at("ai-p1").answer("kak").node == "ai-s3c")                    // the regular expression
        #expect(try s.at("ai-p1").answer("repeat").node == "ai-p1-again")
        #expect(try s.at("ai-p1").answer("c a c again").node == "ai-s3c")             // an answer, not a repeat

        // Puzzle 2: "two two one one" only counts after the hint.
        #expect(try s.at("ai-p2", ["tries": 0.0]).answer("two two one one").node == "ai-p2-hint")
        #expect(try s.answer("two two one one").visited.contains("ai-p2-yes"))
        #expect(try s.at("ai-p2").answer("forty two thousand two hundred and eleven").visited.contains("ai-p2-yes"))

        // The choice, its negation, and chapter 2 picking it up.
        do {
            let it = try s.at("ai-choice").answer("don't follow it")
            #expect(it.node == "ai-fin-hide")
            #expect(it.end?.kind == "chapter")
            #expect(it.end?.next == "ai2-title")
        }
        #expect(s.vars["episode1Choice"] == "hide")
        do {
            let it = try s.nextChapter()
            #expect(Set(it.visited).isSuperset(of: ["ai2-title", "ai2-s1h"]))
        }
        #expect(try s.at("ai-choice").answer("follow the signal").node == "ai-fin-follow")
        do {
            let it = try s.at("ai-choice").answer("hmm")
            #expect(it.node == "ai-choice")
            #expect(it.plays() == ["common/unhandled", "prompts/ai-choice"])
        }
        // Chapter 5's end is the end of the season.
        let last = try map.node("ai5-fin").end
        #expect(last != nil)
        #expect(try #require(last).kind == "ending")
    }
}
