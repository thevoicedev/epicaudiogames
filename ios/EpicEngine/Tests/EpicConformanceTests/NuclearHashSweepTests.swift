// nuclear-war/hashes.json (README sections 8.2 and 9.11), Tier 2: the hash of each Nuclear War game for seeds 1-3000.
// EPIC_SLOW=1 plays all 3000; otherwise a sample.

import EpicConformance
import EpicEngine
import Testing

@Suite struct NuclearHashSweepTests {
    static let games = 3000
    /// With EPIC_SLOW=1 the games are played in parts of this many, side by side.
    static let part = 100

    /// The parts to play: all of them with EPIC_SLOW=1, else one (the sample).
    static let parts = slow ? Array(0..<(games / part)) : [0]

    /// The seeds of a part: with EPIC_SLOW=1 its 100; else the first 20 and a few from further on.
    static func seeds(_ part: Int) -> [Int] {
        slow ? Array((part * NuclearHashSweepTests.part + 1)...((part + 1) * NuclearHashSweepTests.part))
            : Array(1...20) + [37, 101, 500, 999, 1500, 2048, 2500, 2999, 3000]
    }

    @Test(arguments: NuclearHashSweepTests.parts)
    func sweep(part: Int) throws {
        let audio = try NuclearFixtures.audio.get()
        let want = try NuclearFixtures.hashes.get()
        try #require(want.count == NuclearHashSweepTests.games, "hashes.json: \(want.count) games")
        let player = NuclearPlayer(audio)
        let encoder = Canon.Encoder()
        var diffs = Diffs()
        let seeds = NuclearHashSweepTests.seeds(part)
        for seed in seeds {
            let w = want[seed - 1]
            var h = FNV.start
            let game: NuclearPlayer.Game
            do {
                game = try player.game(seed, encoder: encoder) { line in h = FNV.hash("\n", FNV.hash(line, h)) }
            } catch {
                diffs.add("seed \(seed): fails: \(error) (eag --dump nuclear-war/game/\(seed))")
                continue
            }
            if !same(FNV.hex(h), w.hash) || game.lines != w.lines || !same(game.end, w.end) {
                diffs.add("seed \(seed): kotlin \(w.hash), \(w.lines) lines, \"\(w.end)\"; swift \(FNV.hex(h)), "
                    + "\(game.lines) lines, \"\(game.end)\" (eag --dump nuclear-war/game/\(seed))")
            }
        }
        diffs.report("Nuclear War game hashes, seeds \(seeds.first!)-\(seeds.last!) (\(seeds.count) of \(want.count))")
    }
}
