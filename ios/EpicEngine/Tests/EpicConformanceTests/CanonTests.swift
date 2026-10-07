// Canon.kt checked against README sections 2 and 3: the encoder and hash every other suite relies on.

import EpicConformance
import EpicEngine
import Testing

@Suite struct CanonTests {
    @Test func fnvOverUTF16() {
        #expect(FNV.hex(FNV.hash("")) == "cbf29ce484222325")
        #expect(FNV.hex(FNV.hash("a")) == "af63dc4c8601ec8c")
        #expect(FNV.hex(FNV.hash("é😀")) == "d7bced195d50c881")
        // Carried on: two strings hashed one after the other hash as one.
        #expect(FNV.hash("bc", FNV.hash("a")) == FNV.hash("abc"))
        var h = FNV.start
        for u in "x\u{1}é😀\u{2028}".utf16 { h = (h ^ UInt64(u)) &* 0x100000001b3 }
        #expect(FNV.hash("x\u{1}é😀\u{2028}") == h)
    }

    @Test func doubles() {
        let cases: [(Double, String)] = [
            (3, "3"), (-2, "-2"), (0, "0"), (0.5, "\"x3fe0000000000000\""), (0.2, "\"x3fc999999999999a\""),
            (-0.0, "\"x8000000000000000\""), (1e300, "\"x7e37e43c8800759c\""), (.infinity, "\"x7ff0000000000000\""),
            (.nan, "\"x7ff8000000000000\""), (-.nan, "\"x7ff8000000000000\""),
            (Double(bitPattern: 0x7ff0_0000_0000_0001), "\"x7ff8000000000000\""),
            (9_007_199_254_740_991, "9007199254740991"), (9_007_199_254_740_992, "\"x4340000000000000\""),
        ]
        for (d, text) in cases { #expect(Canon.json(.double(d)) == text, "\(d)") }
    }

    @Test func strings() {
        #expect(Canon.json("a\"b\\c\n\u{1f}\u{7f}\u{2028}é") == "\"a\\\"b\\\\c\\u000a\\u001f\u{7f}\u{2028}é\"")
        #expect(Canon.json(.object([("k", [nil, true, 1, .double(2.5)])])) == "{\"k\":[null,true,1,\"x4004000000000000\"]}")
    }

    @Test func turnLineExample() throws {
        // README section 7's example line is noodle-rush's first: Swift's own line must be the same, byte for byte.
        let g = try goldens()
        let map = try g.map("noodle-rush")
        let s = Session(map, choose: { _ in throw ConformanceError("no draws") })
        let t = try s.start()
        let line = Canon.Turns(Canon.Encoder()).line(0, ["start"], [], t, s.save())
        #expect(line == """
            {"t":0,"in":["start"],"rng":[],"node":"Page1","visited":["Page1"],"quit":false,"keep":false,"end":null,"heard":null,"steps":[["p","scenes/title","000","998ce49735409f87"]],"ask":{"b":[["Yes","yes"],["No","no"]],"r":[["p","prompts/title","0","9d96ffe300354dc3"]],"a":"c0b3f88822601ee9"},"save":{"node":"Page1","ended":false,"vars":"51ce9fb89d4a914c","delta":[["nana",["b",false]]]}}
            """)
    }
}

/// The fixture files themselves: all there, each with a current header.
@Suite struct HeaderTests {
    @Test func everyFixtureIsCurrent() throws {
        let g = try goldens()
        var files = ["random.json", "text.json", "expr.json", "map-errors.json", "maps/hashes.json",
                     "nuclear-war/games.jsonl", "nuclear-war/fanout.jsonl", "nuclear-war/hashes.json"]
        for v in Variants.all { files += ["maps/\(v).digest.json", "maps/\(v).matcher.json", "maps/\(v).walks.jsonl"] }
        for f in files {
            if f.hasSuffix(".jsonl") { _ = try g.readLines(f) } else { _ = try g.readJSON(f) }
        }
    }

    /// A header made from other games or another engine fails with the message that says how to remake them.
    @Test func staleHeadersFail() throws {
        let g = try goldens()
        let s = try g.stamp()
        func header(_ format: String, _ games: String, _ engine: String) -> JSONObject {
            ["format": .literal(format), "games_sha256": .string(games), "engine_sha256": .string(engine)]
        }
        try g.checkHeader(header("1", s.gamesSha256, s.engineSha256), "current.json")
        for h in [header("1", String(repeating: "0", count: 64), s.engineSha256),
                  header("1", s.gamesSha256, String(repeating: "f", count: 64))] {
            let e = #expect(throws: ConformanceError.self) { try g.checkHeader(h, "stale.json") }
            #expect(e?.message.hasPrefix("fixtures stale: cd android && ./gradlew :engine:goldens") == true)
        }
        let e = #expect(throws: ConformanceError.self) {
            try g.checkHeader(header("2", s.gamesSha256, s.engineSha256), "format2.json")
        }
        #expect(e?.message.contains("not 1") == true)
    }

    @Test func variantsAreTheGamesFolders() throws {
        let g = try goldens()
        #expect(g.variants.map(\.name) == Variants.all)
    }
}
