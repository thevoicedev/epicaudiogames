// maps/<variant>.digest.json (README section 9.5): the parsed map's header and every node's canonical hash.

import EpicConformance
import EpicEngine
import Testing

@Suite struct MapDigestConfTests {
    @Test(arguments: Variants.all)
    func digest(variant: String) throws {
        let g = try goldens()
        let f = try g.readJSON("maps/\(variant).digest.json")
        let map = try g.map(variant)
        let encoder = Canon.Encoder()
        #expect(try f.fx("variant").fxString() == variant)
        let files = try f.fx("files").fxArray().map { try $0.fxString() }
        #expect(try files == g.variant(variant).files.map(g.relative), "the files loaded")

        let header = Canon.json(encoder.mapHeader(map))
        let want = Canon.reencode(try f.fx("map"))
        #expect(same(header, want), "the map header differs at \(difference(want, header))")

        var diffs = Diffs()
        let nodes = try f.fx("nodes").fxArray().map { row in
            let r = try row.fxArray()
            return (id: try r[0].fxString(), hash: try r[1].fxString())
        }
        let ids = map.nodes.keys
        if nodes.map(\.id) != ids {
            diffs.add("the node ids or their order differ: kotlin \(nodes.count) nodes, swift \(ids.count)")
        }
        for (id, hash) in nodes {
            guard let n = map.nodes[id] else {
                diffs.add("\(id): not in the Swift map")
                continue
            }
            let canon = Canon.json(encoder.node(n))
            if !same(FNV.hex(FNV.hash(canon)), hash) {
                // Compare with `./gradlew :engine:goldens -Pgoldens.dump=<variant>/nodes`.
                diffs.add("\(id): node hash kotlin \(hash); swift's node:\n    \(canon)")
            }
        }
        diffs.report("\(variant) nodes")
        #expect(same(Canon.hash(encoder.map(map)), try f.fx("hash").fxString()), "the map hash")
    }
}
