// maps/<variant>.walks.jsonl (README sections 7, 8.1 and 9.7), Tier 1: every turn of the first walks, replayed.

import EpicConformance
import EpicEngine
import Testing

@Suite struct MapWalkReplayTests {
    private struct Walk {
        let w: Int
        let lines: [String]
    }

    /// The file's walks, its header checked.
    private func walks(_ g: Goldens, _ variant: String) throws -> [Walk] {
        let (header, lines) = try g.readLines("maps/\(variant).walks.jsonl")
        #expect(try header.fx("variant").fxString() == variant)
        let entries = try header.fx("entries").fxArray().map { try $0.fxString() }
        #expect(entries == (try g.entries(variant)), "the chapter ends walks start at")
        let count = try header.fx("walks").fxInt()
        var out: [Walk] = []
        var i = 0
        while i < lines.count {
            let head = try JSONParser.parse(lines[i])
            let w = try head.fx("walk").fxInt()
            #expect(try head.fx("seed").fxInt() == MapWalker.seed(w))
            out.append(Walk(w: w, lines: Array(lines[(i + 1)..<min(lines.count, i + 2 + MapWalker.turns)])))
            i += 2 + MapWalker.turns
        }
        #expect(out.map(\.w) == Array(0..<count))
        #expect(out.allSatisfy { $0.lines.count == MapWalker.turns + 1 })
        return out
    }

    /**
     * Each line's call made on the Swift engine, its choose draws played back from the line's "rng": the line
     * Swift writes must be the line Kotlin wrote. This finds where the engines part, whatever the bot does.
     */
    @Test(arguments: Variants.all)
    func replay(variant: String) throws {
        let g = try goldens()
        let map = try g.map(variant)
        var diffs = Diffs(limit: 6)
        for walk in try walks(g, variant) {
            let chooser = ReplayChooser()
            func session() -> Session { Session(map, choose: { try chooser($0) }) }
            var s = session()
            let turns = Canon.Turns(Canon.Encoder())
            var last: Turn?
            for (t, line) in walk.lines.enumerated() {
                let j = try JSONParser.parse(line)
                let input = try j.fx("in")
                do {
                    try chooser.load(j.fx("rng"))
                    let turn = try call(input, &s, last: last, newSession: session)
                    try chooser.finish()
                    let got = turns.line(t, .raw(Canon.reencode(input)), .raw(Canon.reencode(try j.fx("rng"))), turn, s.save())
                    last = turn
                    if !same(got, line) {
                        diffs.add("walk \(walk.w), t \(t) (\(input.short)): \(difference(line, got))")
                        break
                    }
                } catch {
                    diffs.add("walk \(walk.w), t \(t) (\(input.short)): \(error)")
                    break
                }
            }
        }
        diffs.report("\(variant) walks replayed")
    }

    /// The Swift bot (MapWalker) walks the same walks, its own draws and the session's from one XorWow.
    @Test(arguments: Variants.all)
    func bot(variant: String) throws {
        let g = try goldens()
        let walker = MapWalker(try g.map(variant), entries: try g.entries(variant))
        var diffs = Diffs(limit: 6)
        for walk in try walks(g, variant) {
            var lines: [String] = []
            do {
                try walker.walk(walk.w) { lines.append($0) }
            } catch {
                diffs.add("walk \(walk.w): fails after \(lines.count) lines: \(error)")
                continue
            }
            if let t = lines.indices.first(where: { $0 < walk.lines.count && !same(lines[$0], walk.lines[$0]) }) {
                diffs.add("walk \(walk.w), t \(t): \(difference(walk.lines[t], lines[t]))")
            } else if lines.count != walk.lines.count {
                diffs.add("walk \(walk.w): kotlin \(walk.lines.count) lines, swift \(lines.count)")
            }
        }
        diffs.report("\(variant) walks by the Swift bot")
    }
}
