// AlienCustomsTest.kt: Alien Customs plays as the skill does.

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
    /// Plays the level from its intro to its end, every answer to the officer right (or every one wrong).
    fileprivate func playLevel(_ right: Bool) throws -> Turn {
        var t = try answer("yes")
        while t.end == nil { t = try node.hasSuffix("_ann") ? answer("play") : answer(reply(right)) }
        return t
    }

    /// The answer the officer wants at the current question (or the wrong one).
    fileprivate func reply(_ right: Bool) throws -> String {
        let ask = try #require(try map.node(node).ask)
        let yes = try #require(ask.answers.first { if case .yes = $0.match { true } else { false } })
        guard case .to(let to) = yes.go else { throw PlayError("the yes answer doesn't go to a node") }
        let yesIsRight = try regexContainsMatch(#"_r\d+$"#, to)
        return yesIsRight == right ? "yes" : "no"
    }
}

/**
 * Alien Customs plays as the skill does (Games/alien-customs/index.js, and the responses tools/capture.js recorded):
 * the welcome, Slug's announcement for each item in a shuffled order, the officer's questions, deportation after two
 * wrong answers, and the next level after three items cleared.
 */
struct AlienCustomsTests {
    private let map: GameMap

    init() throws {
        map = try TestRepo.load("alien-customs")
    }

    @Test func aLevelFromWelcomeToDeportation() throws {
        let s = Session(map)
        let welcome = try s.start()
        #expect(welcome.node == "L0_intro")
        #expect(try #require(welcome.said().first).hasPrefix("Welcome to Alien Customs."))

        let ann = try s.answer("yes")
        #expect(ann.node.hasSuffix("_ann"))
        #expect(try #require(ann.said().first).hasPrefix("Listen carefully, there is an announcement about"))
        #expect(ann.said().last == "Repeat, or play?")
        #expect(try s.answer("repeat").node == ann.node, "repeat replays the announcement")

        let start = try s.answer("play")
        let item = start.node.removingSuffix("_q0")
        #expect(start.plays().contains { $0.hasPrefix("mix/intro-0-") }, "the level's intro comes before its first item")
        #expect(start.plays().contains { $0.hasPrefix("audio/dialogue/ordinal-first-") })
        #expect(try #require(start.plays().last).hasSuffix("\(item)-q1"))

        let wrong = try s.answer(s.reply(false))
        #expect(wrong.plays().contains { $0.hasPrefix("mix/\(item)-w0-") })
        let host = wrong.steps.filter {
            if case .play(let p) = $0 { p.lines.contains { $0.who == "HOST" } } else { false }
        }
        #expect(host.count == 1, "one warning in Jessica's voice after the first mistake")
        #expect(wrong.node == "\(item)_q1")

        let deported = try s.answer(s.reply(false))
        #expect(deported.end?.kind == "gameover")
        #expect(deported.end?.retry == "L0_intro", "fixed: try again is the item's own level, not level_intro")
        #expect(Set(deported.said()).isSuperset(of: ["Access denied", "You have been deported back to Earth"]))

        #expect(try s.restart(at: deported.end?.retry).node == "L0_intro", "the same level again")
    }

    @Test func clearingThreeItemsWinsTheLevel() throws {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer("yes")
        var items: [String] = []
        var t = try s.answer("play")
        while t.end == nil {
            if s.node.hasSuffix("_ann") {
                t = try s.answer("play")
                continue
            }
            items.append(s.node.substringBefore("_q"))
            t = try s.answer(s.reply(true))
        }
        #expect(t.end?.kind == "chapter")
        #expect(t.end?.next == "L1_intro")
        #expect(s.vars["level"] == 1.0)
        #expect(Set(items).count == 3, "all three of the level's items, each once")
        #expect(t.said().contains { $0.hasPrefix("Congratulations, traveler.") })

        // The next level, and the welcome back from level 3 on.
        #expect(try s.nextChapter().node == "L1_intro")
        try s.restore(Saved(node: "L1_intro", vars: ["level": 2.0], ended: false))
        #expect(try s.restart(at: "level_intro").node == "L2_intro")
        #expect(
            try #require(s.restart(at: "level_intro").said().first)
                .hasPrefix("Welcome back to Alien Customs! You are currently on level 3"))
    }

    @Test func theOfficerNeedsAYesOrNo() throws {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer("yes")
        _ = try s.answer("play")
        let asked = s.node
        let huh = try s.answer("banana")
        #expect(huh.node == asked)
        #expect(huh.said().last == "The officer needs a yes or no answer.")
        let forgiving = try s.answer("yes it is")
        #expect(!forgiving.visited.isEmpty)
    }

    @Test func okayIsAYesAndNotNowANo() throws {
        // fixed: "okay", "ok" and "not now" weren't understood
        let s = Session(map)
        _ = try s.start()
        #expect(try s.answer("okay").node.hasSuffix("_ann"))
        let leave = Session(map)
        _ = try leave.start()
        #expect(try leave.answer("not now").quit)
    }

    @Test func playAgainAfterTheLastFreeLevelKeepsTheLevelInStep() throws {
        // fixed: a win added 1 to level, so after PLAY AGAIN at "Level 5 cleared" it drifted (level 1 won made it 6)
        let s = Session(map)
        try s.restore(Saved(node: "L1_intro", vars: ["level": 4.0], ended: false))
        #expect(try s.restart(at: "level_intro").node == "L4_intro")
        let five = try s.playLevel(true)
        #expect(five.end?.locked == "alien-customs-levels")
        #expect(s.vars["level"] == 5.0)

        #expect(try s.restart().node == "L0_intro", "level 6 is in the pack: level 1 again")
        let one = try s.playLevel(true)
        #expect(one.end?.next == "L1_intro")
        #expect(s.vars["level"] == 1.0)

        #expect(try s.nextChapter().node == "L1_intro")
        let deported = try s.playLevel(false)
        #expect(deported.end?.kind == "gameover")
        #expect(try s.restart(at: deported.end?.retry).node == "L1_intro", "try again is level 2")
    }

    @Test func withThePackEachWinSetsItsOwnLevel() throws {
        // fixed: the pack's wins added 1 too, so a level that had drifted stayed off
        let dir = try TestRepo.games().appendingPathComponent("alien-customs")
        let full = try GameMap.load(
            dir.appendingPathComponent("map.json"),
            packs: [dir.appendingPathComponent("packs/alien-customs-levels.json")])
        for k in 0..<15 {
            let s = Session(full)
            try s.restore(Saved(node: "L\(k)_win", vars: ["level": 9.0], ended: false))
            let won = try s.restart(at: "L\(k)_win")
            #expect(s.vars["level"]?.numberValue == (k < 14 ? Double(k + 1) : 0.0), "L\(k)_win")
            #expect(won.end?.next == (k < 14 ? "L\(k + 1)_intro" : "level_intro"))
        }
    }
}
