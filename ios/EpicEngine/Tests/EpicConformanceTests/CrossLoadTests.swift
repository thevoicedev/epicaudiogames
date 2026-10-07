// Session.kt's and NuclearWar.kt's open(saved), on the saves Kotlin wrote in Tier 1 (rebuilt from the lines' deltas).

import EpicConformance
import EpicEngine
import Testing

/**
 * Kotlin's saves opened in Swift, through `any Play` as the app opens them (so a game's own `open` must be the one
 * called, not the protocol's default): the turn must be the golden one that followed in Kotlin.
 */
@Suite struct CrossLoadTests {
    /// Each "reopen" and "return" of the map walks: the save after the line before, opened in a new Session whose
    /// choose draws are the line's.
    @Test(arguments: Variants.all)
    func maps(variant: String) throws {
        let g = try goldens()
        let map = try g.map(variant)
        let (_, lines) = try g.readLines("maps/\(variant).walks.jsonl")
        var diffs = Diffs(limit: 6)
        var opened = 0
        var w = -1
        var trail = SaveTrail()
        var before: Saved?
        for text in lines {
            let j = try JSONParser.parse(text)
            if let walk = j["walk"] {
                w = try walk.fxInt()
                trail = SaveTrail()
                before = nil
                continue
            }
            let t = try j.fx("t").fxInt()
            let input = try j.fx("in")
            let kind = try input.fxArray()[0].fxString()
            if kind == "reopen" || kind == "return", let kotlin = before {
                let at = "walk \(w), t \(t) (\(input.short))"
                // The app stores the save after a quit too (GameController.kt finishTurn).
                let rng = try j.fx("rng")
                let chooser = ReplayChooser()
                try chooser.load(rng)
                let game: any Play = Session(map, choose: { try chooser($0) })
                do {
                    let turn = try game.open(kotlin)
                    try chooser.finish()
                    let turns = Canon.Turns(Canon.Encoder())
                    turns.after(kotlin.vars)
                    let got = turns.line(t, .raw(Canon.reencode(input)), .raw(Canon.reencode(rng)), turn, game.save())
                    if !same(got, text) { diffs.add("\(at): \(lineDifference(text, got))") }
                } catch {
                    diffs.add("\(at): \(error)")
                }
                opened += 1
            }
            before = try trail.apply(j)
        }
        #expect(opened >= 6 * 3, "\(variant): saves opened")
        diffs.report("\(variant): Kotlin's saves opened")
    }

    /// Each Tier 1 game's save before its "reopen" (t = 37), opened in a new Swift game whose draws are the line's.
    @Test(arguments: 1...10)
    func nuclearReopen(seed: Int) throws {
        let audio = try NuclearFixtures.audio.get()
        let g = try NuclearFixtures.game(seed)
        var trail = SaveTrail()
        var kotlin: Saved?
        var opened = 0
        for (t, text) in g.lines.enumerated() {
            let j = try JSONParser.parse(text)
            let input = try j.fx("in")
            if try input.fxArray()[0].fxString() == "reopen" {
                let saved = try #require(kotlin)
                #expect(t == NuclearPlayer.reopen)
                let rng = try j.fx("rng")
                let replay = ReplayRandom(try Draw.list(rng))
                let game: any Play = NuclearWar(audio: audio, random: replay)
                do {
                    let turn = try game.open(saved)
                    try replay.finish()
                    let turns = Canon.Turns.nuclear(Canon.Encoder())
                    turns.after(saved.vars)
                    let got = turns.line(t, .raw(Canon.reencode(input)), .raw(Canon.reencode(rng)), turn, game.save())
                    if !same(got, text) { Issue.record("seed \(seed), t \(t): \(lineDifference(text, got))") }
                } catch {
                    Issue.record("seed \(seed), t \(t): \(error)")
                }
                opened += 1
            }
            kotlin = try trail.apply(j)
        }
        #expect(opened == 1, "seed \(seed): reopened \(opened) times")
    }

    /**
     * Every fanout save opened as a Play on Random(k): its opening line. At an end (GAME_OVER) the game starts again
     * and keeps the save's settings (no tutorial the second time).
     */
    @Test func nuclearFanoutOpen() throws {
        let audio = try NuclearFixtures.audio.get()
        let encoder = Canon.Encoder()
        var diffs = Diffs()
        var ended = 0
        for f in try NuclearFixtures.fanout.get().saves {
            let rnd = LoggingRandom(XorWowRandom(seed: Int32(f.seed)))
            let game: any Play = NuclearWar(audio: audio, random: rnd)
            do {
                let turn = try game.open(f.saved)
                let line = Canon.Turns.nuclear(encoder).line(0, ["open"], .list(rnd.take().map(\.canon)), turn,
                                                             game.save())
                if !same(FNV.hex(FNV.hash(line)), f.open) {
                    diffs.add("save \(f.k) (\(f.saved.node)): kotlin's line hashes to \(f.open), swift's is "
                        + Kt.take(line, 800))
                }
                if f.saved.ended {
                    ended += 1
                    let kept = game.save().vars["settings"]?.stringValue
                    if !same(kept, f.saved.vars["settings"]?.stringValue) {
                        diffs.add("save \(f.k): the settings \(f.saved.vars["settings"]?.stringValue ?? "-") "
                            + "became \(kept ?? "-")")
                    }
                }
            } catch {
                diffs.add("save \(f.k) (\(f.saved.node)): \(error)")
            }
        }
        #expect(ended > 0, "the fanout has ended saves")
        diffs.report("fanout saves opened as a Play")
    }
}
