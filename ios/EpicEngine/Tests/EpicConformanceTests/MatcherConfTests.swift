// maps/<variant>.matcher.json (README section 9.6): Matcher.match for up to 28 inputs at every question.

import EpicConformance
import EpicEngine
import Foundation
import Testing

@Suite struct MatcherConfTests {
    @Test(arguments: Variants.all)
    func matcher(variant: String) throws {
        let g = try goldens()
        let f = try g.readJSON("maps/\(variant).matcher.json")
        let map = try g.map(variant)
        #expect(try f.fx("variant").fxString() == variant)

        // Every question, in map order; for a +packs variant only the nodes its packs define.
        let v = try g.variant(variant)
        var only: Set<String>?
        if !v.packs.isEmpty { only = Set(try v.packs.flatMap(Goldens.packNodes)) }
        let questions = map.nodes.filter { $0.value.ask != nil && (only?.contains($0.key) ?? true) }.map(\.key)
        let asks = try f.fx("asks").fxArray()
        #expect(try asks.map { try $0.fxArray()[0].fxString() } == questions, "the questions listed")

        var diffs = Diffs()
        var n = 0
        for row in asks {
            let r = try row.fxArray()
            let id = try r[0].fxString()
            guard let ask = map.nodes[id]?.ask else {
                diffs.add("\(id): no question in the Swift map")
                continue
            }
            for input in try r[1].fxArray() {
                let x = try input.fxArray()
                let said = try x[0].fxString()
                n += 1
                do {
                    let got = try Matcher.match(map, ask, map.vars, said)
                    let text = Canon.json([
                        .string(said), .opt(got.index), .bool(got.repeat), .string(got.how), .bool(got.aside),
                    ])
                    if !same(text, Canon.reencode(input)) { diffs.add("\(id): kotlin \(Canon.reencode(input)), swift \(text)") }
                } catch {
                    diffs.add("\(id) \(Canon.json(.string(said))): swift fails: \(error)")
                }
            }
        }
        diffs.report("\(variant) matcher")
        #expect(n > 0)
    }
}
