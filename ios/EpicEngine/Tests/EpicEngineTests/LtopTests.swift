// LtopTest.kt: Leaning Tower of Pizza plays as the skill does.

import Testing

@testable import EpicEngine

extension Turn {
    fileprivate func plays() -> [String] {
        steps.compactMap {
            switch $0 {
            case .play(let p): p.path
            case .bed(let path, _, _): "bed:\(path ?? "null")"
            default: nil
            }
        }
    }

    fileprivate func said() -> [String] {
        steps.flatMap { step -> [String] in if case .play(let p) = step { p.lines.map(\.text) } else { [] } }
    }
}

extension Session {
    /// The word that lies (or tells the truth) at the current question.
    fileprivate func word(_ lie: Bool) throws -> String {
        let ask = try #require(try map.node(node).ask)
        let target = Go.to(lie ? "lie" : "honest")
        let a = try #require(ask.answers.first { if case .words = $0.match { $0.go == target } else { false } })
        guard case .words(let phrases) = a.match else { throw PlayError("not a words answer") }
        return try #require(phrases.first).text
    }

    fileprivate func lie() throws -> Turn { try answer(word(true)) }
    fileprivate func truth() throws -> Turn { try answer(word(false)) }
}

/**
 * Leaning Tower of Pizza plays as the skill does (Games/leaning-tower-of-pizza/index.js, and the responses that
 * tools/capture.js recorded from it): the question order, the nose, the win and the challenge mode.
 */
struct LtopTests {
    private let map: GameMap

    init() throws {
        map = try TestRepo.load("leaning-tower-of-pizza")
    }

    @Test func firstBattle() throws {
        let s = Session(map)
        let intro = try s.start()
        #expect(intro.node == "first_intro")
        #expect(intro.plays().first == "bed:audio/background")
        #expect(try #require(intro.said().last).hasSuffix("Are you ready to play?"))

        let battle = try s.answer("yes")
        #expect(battle.node.hasPrefix("q_ez"), "an easy first question")
        #expect(Array(battle.plays().prefix(2)) == ["bed:audio/background", "bed:audio/throw-loop"])
        #expect(battle.said().contains("Let's save the city!"))
        #expect(battle.said().last == "True, or false?")

        let lie = try s.lie()
        #expect(s.vars["nose"] == 10.0)
        #expect(Set(lie.plays()).isSuperset(of: ["audio/fx/correct-ping", "bed:audio/throw-loop"]))
        #expect(lie.plays().contains { $0.hasPrefix("mix/lie-40-") })
        #expect(lie.said().contains { $0 == "Only 40 metres to go!" })
        #expect(lie.node.hasPrefix("q_q"), "then the main questions")

        let honest = try s.truth()
        #expect(s.vars["nose"] == 10.0)
        #expect(honest.said().contains("40 metres to go!"))
        #expect(honest.plays().contains { $0.hasPrefix("mix/wrong-") })

        _ = try s.truth()
        #expect(s.node.hasPrefix("q_tr"), "the 4th question is a trick")
        for _ in 0..<3 { _ = try s.lie() }
        #expect(s.vars["nose"] == 40.0)
        #expect(s.node.hasPrefix("q_dn"), "on the very first battle the winning question is a double negative")
        #expect(try s.lie().node == "unlock", "the 5th lie wins, and unlocks challenge mode")
    }

    @Test func winUnlocksChallengeMode() throws {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer("yes")
        var t: Turn
        repeat { t = try s.lie() } while t.ask != nil && s.node.hasPrefix("q_") && s.vars["nose"] != 50.0
        #expect(t.node == "unlock")
        #expect(t.plays().contains("audio/never-stop-2"))
        #expect(t.plays().contains("bed:null"))
        #expect(t.said().contains("You've just unlocked challenge mode!"))
        #expect(s.vars["unlocked"] == true)

        let start = try s.answer("yes")
        #expect(start.plays().contains("audio/gepetto/intro-first-time"))
        #expect(start.node.hasPrefix("q_ez"))
        #expect(s.vars["playedChallenge"] == true)

        let one = try s.lie()
        #expect(s.vars["streak"] == 1.0)
        #expect(one.plays().contains { $0.hasPrefix("audio/gepetto/milestone-1/") })
        #expect(one.plays().contains("audio/grow-nose"))         // the skill's ltop-nose-grow.mp3 isn't on the CDN
        #expect(one.said().contains("Your nose is 10 metres long."))
        _ = try s.lie()
        _ = try s.lie()
        #expect(s.node.hasPrefix("q_tr"), "a trick question after the 3rd lie in a row")

        let q = s.vars["q"]                                       // Kotlin: s.vars["q"] as String
        let over = try s.truth()
        #expect(over.node == "c_over")
        #expect(over.end?.kind == "gameover")
        #expect(over.said().contains("Your streak was 3!"))
        #expect(s.vars["best"] == 3.0)
        #expect(q?.stringValue != nil)

        // Played again: the mode question, Gepetto's welcome back, the high scores.
        let again = try s.restart(at: "start")
        #expect(again.node == "mode_select")
        #expect(try s.answer("what's my high score").node == "scores")
        #expect(try s.answer("challenge").plays().contains { $0.hasPrefix("audio/gepetto/intro-return/") })
        _ = try s.restart(at: "start")
        #expect(try s.answer("battle please").node.hasPrefix("q_ez"))
    }

    @Test func resumingPlaysTheRandomPartsToo() throws {
        let s = Session(map)
        _ = try s.start()
        let back = try Session(map).resume(s.save())
        #expect(back.plays().contains { $0.hasPrefix("audio/monster/") }, "the intro's robot line (a pick) is played on a resume")
    }

    @Test func answerWords() throws {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer("yes")
        let lieIsTrue = try ["true", "too", "two", "2"].contains(s.word(true))
        let lieWord = lieIsTrue ? "two" : "pause"            // "pause" is a mishear of "false"
        #expect(try s.answer(lieWord).visited.first == "lie")

        let asked = s.node
        let banana = try s.answer("banana")
        #expect(banana.node == asked)
        #expect(banana.said().last == "True, or false?")
        let falseIsLie = try !["true", "too", "two", "2"].contains(s.word(true))
        let yesNo = try s.answer("yes no")                              // the last word: "no", so false
        #expect(yesNo.visited.first == (falseIsLie ? "lie" : "honest"))
    }
}
