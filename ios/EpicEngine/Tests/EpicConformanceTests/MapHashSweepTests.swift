// maps/hashes.json (README sections 8.1 and 9.8), Tier 2: the hash of each of 500 bot walks per variant. The
// deterministic stand-in for MapsTest's printed stats. EPIC_SLOW=1 walks all 500; otherwise a sample.

import EpicConformance
import EpicEngine
import Testing

@Suite struct MapHashSweepTests {
    /// The walks to check: all of them with EPIC_SLOW=1, else the first 12 and a few from further on.
    static func sample(_ count: Int) -> [Int] {
        slow ? Array(0..<count) : (Array(0..<12) + [37, 128, 255, 498, 499]).filter { $0 < count }
    }

    @Test(arguments: Variants.all)
    func sweep(variant: String) throws {
        let g = try goldens()
        let f = try g.readJSON("maps/hashes.json")
        #expect(try f.fx("walks").fxInt() == 500)
        #expect(try f.fx("turns").fxInt() == MapWalker.turns)
        #expect(try f.fx("reopen").fxInt() == MapWalker.reopen)
        guard let row = try f.fx("variants").fxArray().first(where: { try $0.fx("variant").fxString() == variant }) else {
            Issue.record("no \(variant) in maps/hashes.json")
            return
        }
        let entries = try row.fx("entries").fxArray().map { try $0.fxString() }
        #expect(entries == (try g.entries(variant)))
        let want = try row.fx("walks").fxArray().map { try $0.fxString() }
        let map = try g.map(variant)
        let walker = MapWalker(map, entries: entries)
        let encoder = Canon.Encoder()
        var diffs = Diffs()
        var lines = 0
        var visited = Set<String>()
        let walks = MapHashSweepTests.sample(want.count)
        for w in walks {
            var h = FNV.start
            do {
                lines += try walker.walk(w, encoder: encoder, onTurn: { visited.formUnion($0.visited) }) { line in
                    h = FNV.hash("\n", FNV.hash(line, h))
                }
            } catch {
                diffs.add("walk \(w): fails: \(error)")
                continue
            }
            if !same(FNV.hex(h), want[w]) {
                diffs.add("walk \(w): kotlin \(want[w]), swift \(FNV.hex(h)) (eag --dump \(variant)/walk/\(w))")
            }
        }
        diffs.report("\(variant) walk hashes (\(walks.count) of \(want.count))")
        if walks.count == want.count {
            #expect(lines == (try row.fx("lines").fxInt()), "turn lines")
            #expect(visited.count == (try row.fx("visited").fxInt()), "nodes visited")
        }
        #expect(map.nodes.count == (try row.fx("nodes").fxInt()), "nodes")
    }
}
