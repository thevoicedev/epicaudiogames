// nuclear-war/fanout.jsonl (README section 9.10): 68 saved games, each opened and answered with each of 143 utterances.

import EpicConformance
import EpicEngine
import Foundation
import Testing

@Suite struct NuclearFanoutTests {
    static let saves = 68

    @Test func header() throws {
        let (utterances, saves) = try NuclearFixtures.fanout.get()
        #expect(utterances.count == 143)
        #expect(saves.count == NuclearFanoutTests.saves, "update NuclearFanoutTests.saves to the fixture's count")
        #expect(saves.allSatisfy { $0.seed == $0.k }, "save k has seed k")
        #expect(saves.allSatisfy { $0.results.count == utterances.count })
    }

    /**
     * Save [k] opened in a new game on Random(k), then each utterance: whether the game understands it, and the
     * answer's turn line (its draws included, by its hash). The opening line must be the same each time.
     */
    @Test(arguments: 1...NuclearFanoutTests.saves)
    func answers(k: Int) throws {
        let audio = try NuclearFixtures.audio.get()
        let (utterances, saves) = try NuclearFixtures.fanout.get()
        let f = try #require(saves.first { $0.k == k })
        let encoder = Canon.Encoder()
        let at = "save \(k) (\(f.saved.node), seed \(f.seed))"
        var diffs = Diffs(limit: 6)
        for (i, said) in utterances.enumerated() {
            let rnd = LoggingRandom(XorWowRandom(seed: Int32(f.seed)))
            let game = NuclearWar(audio: audio, random: rnd)
            let turns = Canon.Turns.nuclear(encoder)
            do {
                let t0 = try game.open(f.saved)
                let line0 = turns.line(0, ["open"], .list(rnd.take().map(\.canon)), t0, game.save())
                if !same(FNV.hex(FNV.hash(line0)), f.open) {
                    // The same for every utterance: told once.
                    let shown = Kt.take(line0, 800)
                    Issue.record("\(at): opening it: kotlin's line hashes to \(f.open), swift's is \(shown)")
                    return
                }
                let understands = try game.understands(said)
                let t1 = try game.answer(said)
                let line1 = turns.line(1, ["answer", .string(said)], .list(rnd.take().map(\.canon)), t1, game.save())
                let got = Canon.json([.int(i), .opt(t1.heard?.answer), .opt(t1.heard?.how), .string(t1.node),
                                      .bool(understands), .string(FNV.hex(FNV.hash(line1)))])
                if !same(got, f.results[i]) {
                    diffs.add("utterance \(i) \(Canon.json(.string(said))): kotlin \(f.results[i]), swift \(got)\n"
                        + "    swift's line: \(Kt.take(line1, 800))")
                }
            } catch {
                diffs.add("utterance \(i) \(Canon.json(.string(said))): \(error)")
            }
        }
        diffs.report("\(at), \(utterances.count) utterances")
    }

    /**
     * Two answers that do the same thing, said with phrases of the same length ("nope skip": the no words and the
     * call's "skip"): the first answer is taken, as Kotlin's maxBy takes the first maximum. The corpus of
     * fanout.jsonl has no such tie, so these rows were made by the Kotlin engine as fanout() makes its results
     * ([k, utterance, answer, how, node, understands, the hash of the answer's turn line]; save k on Random(k)).
     */
    @Test func ties() throws {
        let audio = try NuclearFixtures.audio.get()
        let saves = try NuclearFixtures.fanout.get().saves
        let encoder = Canon.Encoder()
        var diffs = Diffs()
        for want in NuclearFanoutTests.tieRows {
            let row = try JSONParser.parse(want).fxArray()
            let k = try row[0].fxInt()
            let said = try row[1].fxString()
            let f = try #require(saves.first { $0.k == k })
            let rnd = LoggingRandom(XorWowRandom(seed: Int32(f.seed)))
            let game = NuclearWar(audio: audio, random: rnd)
            let turns = Canon.Turns.nuclear(encoder)
            let t0 = try game.open(f.saved)
            _ = turns.line(0, ["open"], .list(rnd.take().map(\.canon)), t0, game.save())
            let understands = try game.understands(said)
            let t1 = try game.answer(said)
            let line = turns.line(1, ["answer", .string(said)], .list(rnd.take().map(\.canon)), t1, game.save())
            let got = Canon.json([.int(k), .string(said), .opt(t1.heard?.answer), .opt(t1.heard?.how),
                                  .string(t1.node), .bool(understands), .string(FNV.hex(FNV.hash(line)))])
            if !same(got, want) { diffs.add("kotlin \(want), swift \(got)") }
        }
        diffs.report("tied answers (\(NuclearFanoutTests.tieRows.count))")
    }

    static let tieRows = [
        #"[15,"nope skip",1,"\"nope\"","PHONE_COUNTRY",true,"9a061e229042cda6"]"#,
        #"[15,"skip nope",1,"\"nope\"","PHONE_COUNTRY",true,"f666304c71bd45b2"]"#,
        #"[15,"nope none",1,"\"nope\"","PHONE_COUNTRY",true,"f2b97aa367d13fa4"]"#,
        #"[15,"none nope",1,"\"nope\"","PHONE_COUNTRY",true,"6f1eb4f099005670"]"#,
        #"[15,"nah play",2,"\"play\"","PHONE_COUNTRY",true,"ac591dee5336c82d"]"#,
        #"[15,"play nah",2,"\"play\"","PHONE_COUNTRY",true,"72410662bb2a9f31"]"#,
        #"[15,"nope and skip",1,"\"nope\"","PHONE_COUNTRY",true,"0a3311fa6104806c"]"#,
        #"[15,"skip it nope",1,"\"nope\"","PHONE_COUNTRY",true,"ec124b600a7deefe"]"#,
        #"[15,"no thanks none",1,"\"no thanks\"","PHONE_COUNTRY",true,"3c82b4fe63f945bc"]"#,
        #"[34,"nope skip",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"44cf268d333a5594"]"#,
        #"[34,"skip nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"bd9a5dcfc00e30c4"]"#,
        #"[34,"nope none",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"9cdd70b7f6e8e3f6"]"#,
        #"[34,"none nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"3f00528b0b38b4c2"]"#,
        #"[34,"nah play",1,"\"nah\"","ENVIRONMENT_PROMPT",true,"6c4cb559276a9235"]"#,
        #"[34,"play nah",1,"\"nah\"","ENVIRONMENT_PROMPT",true,"6d57bf7f00e48a7d"]"#,
        #"[34,"nope and skip",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"2d83a0d1a55863f2"]"#,
        #"[34,"skip it nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"c51c2a699a2a42c0"]"#,
        #"[34,"no thanks none",1,"\"no thanks\"","ENVIRONMENT_PROMPT",true,"60ca8b08af792722"]"#,
        #"[43,"nope skip",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"f97294f1ea77995d"]"#,
        #"[43,"skip nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"4457fcf923620f2d"]"#,
        #"[43,"nope none",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"8d5b9eb3de8149f7"]"#,
        #"[43,"none nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"7a687908ef0ebf9b"]"#,
        #"[43,"nah play",1,"\"nah\"","ENVIRONMENT_PROMPT",true,"c6b2cdd62f313020"]"#,
        #"[43,"play nah",1,"\"nah\"","ENVIRONMENT_PROMPT",true,"976a575e8e492e28"]"#,
        #"[43,"nope and skip",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"e019cd9dc0b386eb"]"#,
        #"[43,"skip it nope",1,"\"nope\"","ENVIRONMENT_PROMPT",true,"d62274c42017ca11"]"#,
        #"[43,"no thanks none",1,"\"no thanks\"","ENVIRONMENT_PROMPT",true,"7bf1a4b4ded1af7b"]"#,
    ]

    /**
     * The saves are the Swift bot's too: going through the games from seed 1, the first 3 saves at each question
     * (README section 9.10). With EPIC_SLOW=1 until every save is found (seed 2468); else the first 40 games, whose
     * saves must begin the list.
     */
    @Test func sample() throws {
        let audio = try NuclearFixtures.audio.get()
        let want = try NuclearFixtures.fanout.get().saves.map(\.saved)
        let (got, seeds) = try NuclearFanoutTests.sampled(audio, want.count, upTo: slow ? 3000 : 40)
        for (i, (a, b)) in zip(want, got).enumerated() where a != b || !same(a.node, b.node) {
            Issue.record("save \(i + 1): kotlin's is at \(a.node), the swift bot's at \(b.node)")
            return
        }
        if slow {
            #expect(got.count == want.count, "the swift bot sampled \(got.count) saves in \(seeds) games")
        } else {
            #expect(got.count >= 40, "the swift bot sampled \(got.count) saves in \(seeds) games")
        }
    }

    /// The first 3 saves at each question of the bot's games from seed 1, until [count] (or [upTo] games). The
    /// games are played side by side in batches of 250, 25 to a worker, and their saves taken in seed order.
    static func sampled(_ audio: NuclearAudio, _ count: Int, upTo: Int) throws -> (saves: [Saved], seeds: Int) {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var games: [Int: Result<[Saved], any Error>] = [:]
        }
        var out: [Saved] = []
        var taken: [String: Int] = [:]
        var next = 1
        while out.count < count && next <= upTo {
            let seeds = Array(next...min(upTo, next + 250 - 1))
            let box = Box()
            DispatchQueue.concurrentPerform(iterations: (seeds.count + 24) / 25) { part in
                let player = NuclearPlayer(audio)
                let encoder = Canon.Encoder()
                for seed in seeds.dropFirst(part * 25).prefix(25) {
                    var saves: [Saved] = []
                    let r = Result {
                        try player.game(seed, encoder: encoder, saves: { saves.append($0) }, emit: { _ in })
                    }
                    box.lock.lock()
                    box.games[seed] = r.map { _ in saves }
                    box.lock.unlock()
                }
            }
            for seed in seeds {
                for s in try box.games[seed]!.get() where taken[s.node, default: 0] < 3 && out.count < count {
                    taken[s.node, default: 0] += 1
                    out.append(s)
                }
                if out.count == count { return (out, seed) }
            }
            next = seeds.last! + 1
        }
        return (out, next - 1)
    }
}
