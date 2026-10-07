// Tests for the JSON reader and writer that stand in for kotlinx.serialization in GameMap.kt.

import Foundation
import Testing

@testable import EpicEngine

/// The repo (with games/catalog.json): EPIC_REPO_ROOT, or up from this file.
private func jsonTestsRepo() -> URL? {
    if let env = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
    while dir.path != "/" {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("games/catalog.json").path) { return dir }
        dir.deleteLastPathComponent()
    }
    return nil
}

struct JSONTests {
    @Test func keepsKeyOrder() throws {
        let o = try JSONParser.parse(#"{"z": 1, "a": 2, "m": {"y": 1, "b": 2}}"#).jsonObject()
        #expect(o.keys == ["z", "a", "m"])
        #expect(try o["m"]!.jsonObject().keys == ["y", "b"])
    }

    @Test func aRepeatedKeyKeepsItsPlaceAndItsLastValue() throws {
        // kotlinx: {"k":1,"j":2,"k":3} reads as {"k":3,"j":2}.
        let o = try JSONParser.parse(#"{"k":1,"j":2,"k":3}"#)
        #expect(o.kotlinxDescription == #"{"k":3,"j":2}"#)
    }

    @Test func keepsNumbersAsWritten() throws {
        let a = try JSONParser.parse("[1.0, -0, 1e5, 1E+5, 0.10]").jsonArray()
        #expect(a.map(\.content) == ["1.0", "-0", "1e5", "1E+5", "0.10"])
        #expect(a[0].doubleOrNull == 1.0)
        #expect(a[1].doubleOrNull!.sign == .minus)
        #expect(a[2].doubleOrNull == 100000)
    }

    @Test func readsPrimitivesAsKotlinxDoes() throws {
        let o = try JSONParser.parse(#"{"t": true, "T": "TRUE", "f": "False", "n": null, "d": "1.5", "x": "yes", "o": {}}"#).jsonObject()
        #expect(o["t"]?.booleanOrNull == true)
        #expect(o["T"]?.booleanOrNull == true)        // case-insensitive, and quoted text counts
        #expect(o["f"]?.booleanOrNull == false)
        #expect(o["x"]?.booleanOrNull == nil)
        #expect(o["n"]?.content == "null")            // JsonNull's content
        #expect(o["n"]?.isPrimitive == true)
        #expect(o["n"]?.doubleOrNull == nil)
        #expect(o["d"]?.doubleOrNull == 1.5)          // doubleOrNull reads strings too
        #expect(o["d"]?.isString == true)
        #expect(o["t"]?.isString == false)
        #expect(o["o"]?.content == nil)
        #expect(o["o"]?.booleanOrNull == nil)
        #expect(throws: MapError.self) { try o["o"]!.primitiveContent() }
        #expect(throws: MapError.self) { try o["t"]!.jsonObject() }
        #expect(throws: MapError.self) { try o["t"]!.jsonArray() }
    }

    @Test func readsIntegersAsKotlinxDoes() throws {
        // kotlinx's consumeNumericLiteral: whole numbers only, exponents allowed, stops at a space or comma.
        let cases: [(String, Int64?, Int32?)] = [
            ("12", 12, 12), ("-3", -3, -3), ("1e2", 100, 100), ("\"12 x\"", 12, 12), ("\"\\\"5\\\"\"", 5, 5),
            ("1.5", nil, nil), ("1e-1", nil, nil), ("2147483648", 2147483648, nil),
            ("9223372036854775807", Int64.max, nil), ("9223372036854775808", nil, nil),
            ("-9223372036854775808", Int64.min, nil), ("true", nil, nil), ("null", nil, nil), ("\"\"", nil, nil),
            ("\"-\"", nil, nil), ("\"e5\"", nil, nil),
        ]
        for (text, long, int) in cases {
            let p = try JSONParser.parse(text)
            #expect(p.longOrNull == long, "\(text)")
            #expect(p.intOrNull == int, "\(text)")
        }
        #expect(try JSONParser.parse("7").int() == 7)
        #expect(throws: PlayError.self) { try JSONParser.parse("7.5").int() }
        #expect(try JSONParser.parse("\"TRUE\"").boolean() == true)
        #expect(throws: PlayError.self) { try JSONParser.parse("1").boolean() }
    }

    @Test func readsEscapes() throws {
        let s = try JSONParser.parse(#""a\"b\\c\/d\b\f\n\r\t\u00e9\ud83d\ude00""#)
        #expect(s == .string("a\"b\\c/d\u{8}\u{C}\n\r\té😀"))
        // A lone surrogate can't be held in a Swift String.
        #expect(try JSONParser.parse(#""\ud800x""#) == .string("\u{FFFD}x"))
    }

    @Test func readsOnlyRFC8259() {
        // kotlinx takes unquoted words; this reader doesn't (docs/IOS_PARITY.md, L12). A raw control character in a
        // string is kotlinx's, though (ParityRegressionTests).
        for bad in [
            "", "{", "[1,]", "{\"a\":1,}", "{a:1}", "['a']", "01", "1.", ".5", "+1", "-", "1e", "NaN", "Infinity",
            "tru", "nul", "\"\\x\"", "[1 2]", "{\"a\" 1}", "1 2", "// c\n1", "\u{FEFF}1", "\"\\u12\"",
        ] {
            #expect(throws: JSONParseError.self, "\(bad)") { try JSONParser.parse(bad) }
        }
        for good in ["0", "-0", "1.5e-3", " [ ] ", "{}", "\"\"", "null", "true", "[[[]]]", "-12.5E+2"] {
            #expect(throws: Never.self, "\(good)") { try JSONParser.parse(good) }
        }
    }

    @Test func readsDeepNestingWithoutRecursion() throws {
        // kotlinx reads any depth; JSON.release frees it a level at a time (Swift's own freeing would recurse).
        let deep = String(repeating: "[", count: 2000) + String(repeating: "]", count: 2000)
        var deepJSON = try JSONParser.parse(deep)
        let describedTheSame = deepJSON.kotlinxDescription == deep
        JSON.release(&deepJSON)
        #expect(describedTheSame)
        let ok = String(repeating: "{\"a\":[", count: 250) + "1" + String(repeating: "]}", count: 250)
        let json = try JSONParser.parse(ok)
        #expect(json.kotlinxDescription == ok)
    }

    @Test func describesAsKotlinxDoes() throws {
        // From kotlinx 1.6.3's JsonElement.toString() on the same text.
        let text = #"{"b":1.0,"a":[true,null,"x\"y\n\u0001\u001F\b\f\r\t/\u2028é😀"],"c":{},"d":-0,"e":1e5,"f":1E+5}"#
        let kotlinx = "{\"b\":1.0,\"a\":[true,null,\"x\\\"y\\n\\u0001\\u001f\\b\\f\\r\\t/\u{2028}é😀\"],\"c\":{},\"d\":-0,\"e\":1e5,\"f\":1E+5}"
        #expect(try JSONParser.parse(text).kotlinxDescription == kotlinx)
        #expect(JSON.null.kotlinxDescription == "null")
        #expect(JSON.string("q").kotlinxDescription == "\"q\"")
    }

    @Test func writesOrgJSONEscapes() {
        #expect(JSONWriter.quote("a/b\u{2028}\u{1}", escaping: .orgJSON) == #""a\/b\u2028\u0001""#)
        #expect(JSONWriter.quote("a/b\u{2028}\u{1}") == "\"a/b\u{2028}\\u0001\"")
    }

    @Test func comparesAsKotlinxDoes() throws {
        // Objects are equal in any key order; a string isn't the literal with the same text.
        #expect(try JSONParser.parse(#"{"a":1,"b":[2]}"#) == JSONParser.parse(#"{"b":[2],"a":1}"#))
        #expect(try JSONParser.parse(#"[1,2]"#) != JSONParser.parse(#"[2,1]"#))
        #expect(JSON.string("1") != JSON.literal("1"))
        #expect(JSON.literal("1") != JSON.literal("1.0"))
    }

    @Test func buildsNumbers() {
        #expect(JSON.number(3) == .literal("3"))
        #expect(JSON.number(-0.0) == .literal("-0"))
        #expect(JSON.number(0.5) == .literal("0.5"))
        #expect(JSON.number(1e15) == .literal("1000000000000000"))
        #expect(JSON.number(1e20) == .literal("1.0E20"))          // past Long's range, as org.json writes it
        #expect(JSON.number(1e300) == .literal("1.0E300"))
        #expect(JSON(Value.bool(true)) == .literal("true"))
        #expect(JSON(Value.string("x")) == .string("x"))
    }

    @Test func mergesAsKotlinMapPlus() {
        // Map.plus: the first map's keys keep their places (taking the second's values), new keys go at the end.
        let a: JSONObject = ["x": 1, "y": 2, "z": 3]
        let b: JSONObject = ["w": 9, "y": 8]
        let m = a.merging(b)
        #expect(m.keys == ["x", "y", "z", "w"])
        #expect(m["y"] == .literal("8"))
    }

    @Test func mergesPacksInOrder() throws {
        let map = """
            {"format":1,"id":"g","title":"G","start":"a","vars":{"v1":1,"v2":2},"keep":["v1"],"who":{"A":"a"},
             "nodes":{"a":{"go":"b"},"b":{"end":{"kind":"chapter","title":"C1","next":"c","locked":"p"}}}}
            """
        let pack = """
            {"format":1,"game":"g","id":"p","vars":{"v3":3,"v1":10},"keep":["v3","v1"],
             "nodes":{"c":{"end":{"kind":"ending","title":"E"}},"b":{"end":{"kind":"chapter","title":"C1","next":"c"}}}}
            """
        let m = try GameMap.parse(map, packs: [pack])
        #expect(m.nodes.keys == ["a", "b", "c"])
        #expect(m.nodes["b"]?.end?.locked == nil)
        #expect(m.vars.keys == ["v1", "v2", "v3"])
        #expect(m.vars["v1"] == 10)
        #expect(m.keep == ["v1", "v3"])
        let other = #"{"format":1,"game":"h","id":"q","nodes":{}}"#
        #expect(throws: MapError("pack \"q\" is for h, not g")) { try GameMap.parse(map, packs: [other]) }
    }

    @Test func mapErrorsQuoteTheJSONAsKotlinxDoes() {
        // MapException messages embed JsonElement.toString(), cut to 120 UTF-16 units.
        let long = String(repeating: "x", count: 200)
        let map = """
            {"format":1,"id":"t","title":"T","start":"a","nodes":{"a":{"say":[{"play":"\(long)","durr":1}],"end":{"kind":"k","title":"t"}}}}
            """
        let message = "missing number \"dur\" in " + String(("{\"play\":\"" + long).prefix(120))
        #expect(throws: MapError(message)) { try GameMap.parse(map) }
        #expect(throws: MapError("format 1.0: only format 1 is supported")) { try GameMap.parse(#"{"format":1.0}"#) }
        #expect(throws: MapError("format null: only format 1 is supported")) { try GameMap.parse("{}") }
        #expect(throws: MapError("format \"2\": only format 1 is supported")) { try GameMap.parse(#"{"format":"2"}"#) }
        // Bad JSON isn't a MapException in Kotlin either.
        let bad = #expect(throws: MapError.self) { try GameMap.parse("{") }
        #expect(bad?.kind == .other)
    }

    @Test func readsEveryGameFile() throws {
        let repo = try #require(jsonTestsRepo(), "set EPIC_REPO_ROOT or run from the repo")
        let games = repo.appendingPathComponent("games")
        let files = try FileManager.default.subpathsOfDirectory(atPath: games.path).filter { $0.hasSuffix(".json") }.sorted()
        #expect(files.count >= 13)
        for f in files {
            let data = try Data(contentsOf: games.appendingPathComponent(f))
            let json = try JSONParser.parse(data)
            #expect(json.isPrimitive == false, "\(f)")
        }
    }
}
