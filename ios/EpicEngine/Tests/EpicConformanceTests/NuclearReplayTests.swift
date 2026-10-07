// nuclear-war/games.jsonl (README sections 7, 8.2 and 9.9), Tier 1: every turn of 10 games, replayed draw by draw.

import EpicConformance
import EpicEngine
import Testing

@Suite struct NuclearReplayTests {
    /**
     * Each line's call made on the Swift engine, its draws played back from the line's "rng" call by call (the first
     * call whose method or bound differs fails, naming the draw): then the state JSON and the whole line Swift writes
     * must be Kotlin's. A game stops at its first difference.
     */
    @Test(arguments: 1...10)
    func replay(seed: Int) throws {
        let audio = try NuclearFixtures.audio.get()
        let g = try NuclearFixtures.game(seed)
        var replay = ReplayRandom()
        var game = NuclearWar(audio: audio, random: replay)
        let turns = Canon.Turns.nuclear(Canon.Encoder())
        var kotlin = SaveTrail()
        var last: Turn?
        for (t, line) in g.lines.enumerated() {
            let j = try JSONParser.parse(line)
            let input = try j.fx("in")
            let rng = try j.fx("rng")
            let at = "seed \(seed), t \(t) (\(input.short))"
            try #require(try j.fx("t").fxInt() == t, "\(at): the line's t")
            let draws = try Draw.list(rng)
            let turn: Turn
            do {
                replay.load(draws)
                turn = try nuclearCall(input, &game, audio: audio) {
                    replay = ReplayRandom(draws)
                    return replay
                }
                try replay.finish()
            } catch {
                Issue.record("\(at): \(error)")
                return
            }
            let saved = game.save()
            let want = try kotlin.apply(j)
            let state = saved.vars["state"]?.stringValue
            let wantState = want.vars["state"]?.stringValue
            if !same(state, wantState) {
                Issue.record("\(at): the state JSON differs at \(difference(wantState ?? "-", state ?? "-"))")
                return
            }
            let got = turns.line(t, .raw(Canon.reencode(input)), .raw(Canon.reencode(rng)), turn, saved)
            if !same(got, line) {
                Issue.record("\(at): \(lineDifference(line, got))")
                return
            }
            last = turn
        }
        #expect(g.lines.count == g.turns)
        #expect(same(last?.end?.title, g.end), "seed \(seed): the end")
    }

    /// The Swift bot (NuclearPlayer) plays the same games, its own draws from one XorWow and the game's from another.
    @Test(arguments: 1...10)
    func bot(seed: Int) throws {
        let audio = try NuclearFixtures.audio.get()
        let g = try NuclearFixtures.game(seed)
        var lines: [String] = []
        let result = Result { try NuclearPlayer(audio).game(seed) { lines.append($0) } }
        if let t = lines.indices.first(where: { $0 < g.lines.count && !same(lines[$0], g.lines[$0]) }) {
            Issue.record("seed \(seed), t \(t): \(lineDifference(g.lines[t], lines[t]))")
            return
        }
        switch result {
        case .failure(let error):
            Issue.record("seed \(seed): fails after \(lines.count) lines: \(error)")
        case .success(let game):
            #expect(lines.count == g.lines.count, "seed \(seed): turn lines")
            #expect(same(NuclearPlayer.gameLine(seed, game), g.gameLine), "seed \(seed): the game line")
        }
    }

    /// eag --dump nuclear-war/game/<seed> writes the game as games.jsonl has it.
    @Test func dump() throws {
        let g = try NuclearFixtures.game(3)
        let lines = try Dump.lines("nuclear-war/game/3", goldens())
        #expect(lines.count == g.lines.count + 1)
        #expect(lines.elementsEqual([g.gameLine] + g.lines, by: same))
    }
}
