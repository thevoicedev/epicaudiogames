// PirateQuestTest.kt: Pirate Quest plays as the skill does.

import Testing

@testable import EpicEngine

extension Turn {
    fileprivate func plays() -> [String] {
        steps.compactMap { if case .play(let p) = $0 { p.path } else { nil } }
    }

    fileprivate func said() -> [String] {
        steps.flatMap { step -> [String] in if case .play(let p) = step { p.lines.map(\.text) } else { [] } }
    }
}

/**
 * Pirate Quest plays as the skill does (Games/pirate-quest/index.js, and the responses tools/capture.js recorded):
 * the choices and the skill's words for them, the stats that change what is heard (coins for the dice, reputation
 * for the Spanish trick, the royal information at the tavern), and leaving with the place kept.
 */
struct PirateQuestTests {
    private let map: GameMap

    init() throws {
        map = try TestRepo.load("pirate-quest")
    }

    /// A session at a node, with these stats (the rest as at the start).
    private func at(_ node: String, _ vars: VarStore = [:], choose: @escaping (Int) throws -> Int = { _ in 0 }) throws
        -> Session
    {
        let s = Session(map, choose: choose)
        try s.restore(Saved(node: node, vars: map.vars.merging(vars), ended: false))
        return s
    }

    @Test func theStartAndTheFirstChoices() throws {
        let s = Session(map) { _ in 0 }
        let start = try s.start()
        #expect(start.node == "ac-1")
        #expect(start.plays().first == "audio/pirate-quest-intro")
        #expect(try #require(start.said().last).hasSuffix("Are you ready to begin your quest?"))

        let plan = try s.answer("yes")
        #expect(plan.node == "ac-1a")
        #expect(plan.plays().contains("audio/one-eyed-will-intro"))
        #expect(try #require(s.ask).buttons.map(\.value) == ["map", "supplies"])

        let supplies = try s.answer("stock up")
        #expect(supplies.node == "ac-2")
        #expect(s.vars["coins"] == 55.0, "supplies once: 50 + 5")
        let again = try s.answer("repeat")
        #expect(again.node == "ac-2", "repeat plays the node again, and the coins aren't given twice")
        #expect(again.plays().contains("audio/supplies-sailor"))
        #expect(s.vars["coins"] == 55.0)
        #expect(try s.answer("hire").node == "ac-3")
        #expect(try s.answer("banana").said().single() == "You can say FIGHT, FLEE, or TALK")
    }

    @Test func noToStartingLeavesTheGame() throws {
        let s = Session(map) { _ in 0 }
        _ = try s.start()
        let bye = try s.answer("no")
        #expect(bye.quit)
        #expect(!bye.keep)
        #expect(bye.said() == ["Begin your pirate adventure another time."])
    }

    @Test func notSailingOnLeavesWithThePlaceKept() throws {
        let s = try at("ac-3")
        let fled = try s.answer("flee")
        #expect(fled.node == "ac-3b")
        #expect(s.vars["reputation"] == 5.0)
        let bye = try s.answer("no")
        #expect(bye.said() == ["Thanks for playing."])
        #expect(bye.quit && bye.keep)
        #expect(s.node == "ac-3b", "the question it left from")

        let back = try Session(map).resume(s.save())
        #expect(back.node == "ac-3b")
        #expect(back.plays().contains("audio/pirate-flee"))
        #expect(s.vars["reputation"] == 5.0, "the reputation isn't taken twice")
    }

    @Test func theDiceGame() throws {
        // Every die a 1: a draw.
        let draw = try at("ac-8", ["coins": 50.0]).answer("dice")
        #expect(draw.node == "ac-8b")
        #expect(
            Set(draw.said()).isSuperset(of: [
                "You have 50 coins.", "You wager 10 coins.",
                "You rolled 1, 1, 1 for a total of 3!", "They rolled 1, 1, 1 for a total of 3.",
            ]))
        #expect(draw.plays().contains("audio/tie-message"))

        // Three sixes against three ones: 10 coins won, the dice read highest first.
        var rolls = [5, 4, 3, 0, 1, 0]
        let s = try at("ac-8", ["coins": 50.0]) { n in n == 6 ? (rolls.isEmpty ? 0 : rolls.removeFirst()) : 0 }
        let won = try s.answer("dice")
        #expect(
            Set(won.said()).isSuperset(of: [
                "You rolled 6, 5, 4 for a total of 15!",
                "They rolled 2, 1, 1 for a total of 4.", "You won 10 coins.", "You have 60 coins.",
            ]))
        #expect(s.vars["coins"] == 60.0)
        #expect(try s.answer("roll").node == "ac-8b", "roll again")

        // No coins: the pouch is empty, and on to the inn.
        let broke = try at("ac-8", ["coins": 5.0]).answer("dice")
        #expect(broke.plays().contains("audio/pouch-empty"))
        #expect(broke.node == "ac-9")
        // At the second dice game, on to the tavern (the skill sends you back to the first inn).
        let broke2 = try at("ac-22", ["coins": 0.0]).answer("dice")
        #expect(broke2.node == "ac-25")
    }

    @Test func statsChangeTheStory() throws {
        #expect(try at("ac-16b", ["reputation": 50.0]).answer("yes").plays().contains("audio/convinced-spanish"))
        #expect(try at("ac-16b", ["reputation": 10.0]).answer("yes").plays().contains("audio/suspicious-spaniard"))
        #expect(try at("ac-22a").answer("yes").node == "ac-25", "no royal information: Captain Blacktooth")
        let tavern = try at("ac-22a", ["royalInfo": true]).answer("yes")
        #expect(tavern.node == "ac-23")
        #expect(tavern.plays().contains("audio/introduce-english"))
    }

    @Test func theSkillsOwnWordsAndNumbers() throws {
        #expect(try at("ac-3a1").answer("no").node == "ac-3a2", "no is a duel (a mishear of joe)")
        #expect(try at("ac-15").answer("4").node == "ac-16a", "4 is board")
        #expect(try at("ac-15").answer("five").node == "ac-16", "5 is fight")
        let end = try at("ac-shanty").answer("no")
        #expect(end.end?.kind == "ending")
        #expect(try !at("ac-28a").answer("yes").said().contains { $0.contains("minigames") })
    }
}
