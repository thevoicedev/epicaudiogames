// GoldenTest.kt's nuclear() and fanout(), read back: the Nuclear War fixtures (README sections 8.2, 9.9 to 9.11).

import EpicConformance
import EpicEngine
import Foundation

/// The Nuclear War fixtures, each read once and shared by the suites (the files are large).
enum NuclearFixtures {
    /// A Tier 1 game of games.jsonl: its game line and turn lines.
    struct Game: Sendable {
        let seed: Int
        let turns: Int
        let end: String
        let gameLine: String
        let lines: [String]
    }

    /// A sampled save of fanout.jsonl, with the results of each utterance.
    struct Fanout: Sendable {
        /// 1-based: the line after the header, and the game's seed.
        let k: Int
        let saved: Saved
        let seed: Int
        let open: String
        /// Each utterance's [i, answer, how, node, understands, hash], as canonical text.
        let results: [String]
    }

    static let audio = Result { try goldens().nuclearAudio() }

    /// games.jsonl: seeds 1 to 10.
    static let games: Result<[Game], any Error> = Result {
        let (header, lines) = try goldens().readLines("nuclear-war/games.jsonl")
        let seeds = try header.fx("seeds").fxArray().map { try $0.fxInt() }
        guard seeds == [1, 10] else { throw ConformanceError("games.jsonl: seeds \(seeds), not [1, 10]") }
        var out: [Game] = []
        var i = 0
        while i < lines.count {
            let head = try JSONParser.parse(lines[i])
            let turns = try head.fx("turns").fxInt()
            guard i + 1 + turns <= lines.count else { throw ConformanceError("games.jsonl ends inside a game") }
            out.append(Game(seed: try head.fx("seed").fxInt(), turns: turns, end: try head.fx("end").fxString(),
                            gameLine: lines[i], lines: Array(lines[(i + 1)...(i + turns)])))
            i += 1 + turns
        }
        guard out.map(\.seed) == Array(1...10) else {
            throw ConformanceError("games.jsonl: games \(out.map(\.seed)), not seeds 1 to 10")
        }
        return out
    }

    static func game(_ seed: Int) throws -> Game {
        guard let g = try games.get().first(where: { $0.seed == seed }) else {
            throw ConformanceError("no game \(seed) in games.jsonl")
        }
        return g
    }

    /// fanout.jsonl: the utterances, and the saves.
    static let fanout: Result<(utterances: [String], saves: [Fanout]), any Error> = Result {
        let (header, lines) = try goldens().readLines("nuclear-war/fanout.jsonl")
        let utterances = try header.fx("utterances").fxArray().map { try $0.fxString() }
        let saves = try lines.enumerated().map { i, line -> Fanout in
            let o = try JSONParser.parse(line)
            let s = try o.fx("save")
            return Fanout(
                k: i + 1,
                saved: Saved(node: try s.fx("node").fxString(), vars: try s.fx("vars").fxVars(),
                             ended: try s.fx("ended").fxBool()),
                seed: try o.fx("seed").fxInt(), open: try o.fx("open").fxString(),
                results: try o.fx("results").fxArray().map(Canon.reencode))
        }
        return (utterances, saves)
    }

    /// hashes.json: each game's [hash, turn lines, end title], game k being seed k + 1.
    static let hashes: Result<[(hash: String, lines: Int, end: String)], any Error> = Result {
        let f = try goldens().readJSON("nuclear-war/hashes.json")
        let seeds = try f.fx("seeds").fxArray().map { try $0.fxInt() }
        guard seeds == [1, 3000] else { throw ConformanceError("hashes.json: seeds \(seeds), not [1, 3000]") }
        return try f.fx("games").fxArray().map { g in
            let a = try g.fxArray()
            guard a.count == 3 else { throw ConformanceError("hashes.json: not [hash, lines, end]: \(g.short)") }
            return (try a[0].fxString(), try a[1].fxInt(), try a[2].fxString())
        }
    }
}

/// A Kotlin save rebuilt from turn lines: each line's "delta" applied to the one before (README section 7).
struct SaveTrail {
    private(set) var vars = VarStore()

    /// The save after [line]; fails unless its variables hash to the line's "vars".
    mutating func apply(_ line: JSON) throws -> Saved {
        let save = try line.fx("save")
        for pair in try save.fx("delta").fxArray() {
            let p = try pair.fxArray()
            let name = try p[0].fxString()
            if let v = try p[1].fxValue() { vars[name] = v } else { vars.removeValue(forKey: name) }
        }
        let hash = Canon.hash(Canon.vars(vars))
        guard same(hash, try save.fx("vars").fxString()) else {
            throw ConformanceError("the deltas don't add up to the line's variables (hash \(hash))")
        }
        return Saved(node: try save.fx("node").fxString(), vars: vars, ended: try save.fx("ended").fxBool())
    }
}

/// A Nuclear War call (README section 7.1: start, answer, silence, reopen) made on [game]. "reopen" makes a new
/// game on [newRandom] and opens the old one's save in it.
func nuclearCall(
    _ input: JSON, _ game: inout NuclearWar, audio: NuclearAudio, newRandom: () -> any KotlinRandom
) throws -> Turn {
    let a = try input.fxArray()
    switch try a[0].fxString() {
    case "start": return try game.start()
    case "answer": return try game.answer(a[1].fxString())
    case "silence": return try game.silence()
    case "reopen":
        let saved = game.save()
        game = NuclearWar(audio: audio, random: newRandom())
        return try game.open(saved)
    default: throw ConformanceError("no such Nuclear War call \(input.short)")
    }
}

/// The first field where two turn lines differ, named, with the difference (the whole line's when they don't parse).
func lineDifference(_ want: String, _ got: String) -> String {
    guard let a = try? JSONParser.parse(want).objectValue, let b = try? JSONParser.parse(got).objectValue else {
        return difference(want, got)
    }
    for (k, v) in a {
        let x = Canon.reencode(v)
        let y = b[k].map(Canon.reencode) ?? "(none)"
        if !same(x, y) {
            if k == "save", let s = v.objectValue, let t = b[k]?.objectValue {
                for (f, w) in s where !same(Canon.reencode(w), t[f].map(Canon.reencode) ?? "(none)") {
                    return "\"save\".\"\(f)\" \(difference(Canon.reencode(w), t[f].map(Canon.reencode) ?? ""))"
                }
            }
            return "\"\(k)\" \(difference(x, y))"
        }
    }
    return difference(want, got)
}
