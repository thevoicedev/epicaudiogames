// Regression tests for Kotlin-vs-Swift differences found in review: each input was run through the Kotlin engine
// (GameMap.kt, Session.kt, Matcher.kt on the JVM with kotlinx-serialization 1.6.3), and the expected values are its.

import Foundation
import Testing

@testable import EpicEngine

/// A map's JSON: format 1, id "g", title "T", the given start, and the rest (which must hold "nodes").
private func mapText(start: String = "s", title: String = "T", _ rest: String) -> String {
    "{\"format\":\"1\",\"id\":\"g\",\"title\":\"\(title)\",\"start\":\"\(start)\",\(rest)}"
}

/// A node that ends the game with this title.
private func endNode(_ title: String = "t", play: String? = nil) -> String {
    let say = play.map { "\"say\":[{\"play\":\"\($0)\",\"dur\":1}]," } ?? ""
    return "{\(say)\"end\":{\"kind\":\"k\",\"title\":\"\(title)\"}}"
}

private func parse(_ text: String, packs: [String] = []) throws -> GameMap { try GameMap.parse(text, packs: packs) }

/// The clips a turn plays, in order.
private func clips(_ turn: Turn) -> [String] {
    turn.steps.compactMap { if case .play(let c) = $0 { c.path } else { nil } }
}

/// "é" precomposed (NFC), the same letter decomposed (NFD), and U+212A KELVIN SIGN (canonically "K").
private let nfc = "\u{E9}"
private let nfd = "e\u{301}"
private let kelvin = "\u{212A}"

/// Kotlin's String.equals.
private func same(_ a: String, _ b: String) -> Bool { Kt.utf16Equal(a, b) }

private func sameList(_ a: [String], _ b: [String]) -> Bool { a.count == b.count && zip(a, b).allSatisfy(same) }

struct ParityRegressionTests {
    // ----- JSON as kotlinx 1.6.3 reads it -----

    @Test func rawControlCharactersInStringsAreKotlinxs() throws {
        // kotlinx finds a string's closing quote and never looks for control characters.
        #expect(try parse(mapText(title: "a\u{9}b", "\"nodes\":{\"s\":\(endNode())}")).title == "a\tb")
        let who = try parse(mapText("\"who\":{\"a\u{A}b\":\"x\"},\"nodes\":{\"s\":\(endNode())}")).who
        #expect(who["a\nb"] == "x")
        #expect(try parse(mapText(title: "a\u{1}b\u{0}c\u{1F}d", "\"nodes\":{\"s\":\(endNode())}")).title == "a\u{1}b\u{0}c\u{1F}d")
        // Outside a string a control character is still an error.
        #expect(throws: MapError.self) { try parse(mapText("\u{1}\"nodes\":{\"s\":\(endNode())}")) }
    }

    @Test func aStrayCloseBracketCarriesTheArrayOn() throws {
        // kotlinx's readArray keeps reading while a value follows, even after "]".
        #expect(try parse(mapText("\"keep\":[\"a\"] \"b\"],\"nodes\":{\"s\":\(endNode())}")).keep == ["a", "b"])
        let m = try parse(mapText(
            "\"nodes\":{\"s\":{\"ask\":{\"answers\":[{\"any\":true}] {\"yes\":true,\"go\":\"t\"}]}},\"t\":\(endNode())}"
        ))
        let answers = try #require(m.nodes["s"]?.ask?.answers)
        #expect(answers.count == 2)
        #expect(answers.last?.go == .to("t"))
        let turn = try Session(m).answer("yes")
        #expect(turn.heard?.how == "\"yes\"")
        #expect(turn.end?.title == "t")
        #expect(try JSONParser.parse("[1] 2] 3]") == .array([.literal("1"), .literal("2"), .literal("3")]))
        #expect(try JSONParser.parse("[[1] 2]]") == .array([.array([.literal("1"), .literal("2")])]))
        // Where kotlinx stops: "]" then "]", an empty array, an object, or the end of the text.
        for bad in [
            "\"keep\":[\"a\"]] ,", "\"keep\":[[\"a\"] \"b\"],", "\"keep\":[] \"b\"],", "\"who\":{\"a\":\"x\"} \"b\":\"y\"},",
        ] {
            #expect(throws: MapError.self, "\(bad)") { try parse(mapText(bad + "\"nodes\":{\"s\":\(endNode())}")) }
        }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("[1] 2") }
    }

    @Test func nestingHasNoLimit() throws {
        // kotlinx reads any depth (objects without recursion); a map ignores keys it doesn't know.
        for (open, close) in [("[", "]"), ("{\"a\":", "}")] {
            for depth in [600, 100_000] {
                let notes = String(repeating: open, count: depth) + "1" + String(repeating: close, count: depth)
                let m = try parse(mapText("\"notes\":\(notes),\"nodes\":{\"s\":\(endNode("end"))}"))
                #expect(try Session(m).start().end?.title == "end", "\(open) x \(depth)")
            }
        }
        // A save nested as deep reads as no save, without running out of stack.
        let deep = "{\"node\":\"s\",\"vars\":{},\"x\":" + String(repeating: "[", count: 100_000)
            + String(repeating: "]", count: 100_000) + "}"
        #expect(SavedCodec.decode(deep)?.node == "s")
    }

    @Test func malformedUTF8ReadsAsJavasDecoderReadsIt() throws {
        // File.readText: JDK 17's decoder makes an encoded surrogate one U+FFFD (Swift's own decoding makes three).
        func title(_ bytes: [UInt8]) throws -> String {
            let text = Array("{\"format\":\"1\",\"id\":\"g\",\"title\":\"".utf8) + bytes
                + Array("\",\"start\":\"s\",\"nodes\":{\"s\":{\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}}".utf8)
            return try GameMap.parse(data: Data(text)).title
        }
        #expect(try title([0x61, 0xED, 0xA0, 0x80, 0x62]) == "a\u{FFFD}b")
        // E0 80, ED A0 before "c", a cut-off F0 9F 98, F4 90 80 80 (past U+10FFFF), C0 AF, and E2 82 before the quote.
        let mixed: [UInt8] = [0x61, 0xE0, 0x80, 0x62, 0xED, 0xA0, 0x63, 0xF0, 0x9F, 0x98, 0x64, 0xF4, 0x90, 0x80, 0x80,
                              0x65, 0xC0, 0xAF, 0x67, 0xE2, 0x82]
        let r = "\u{FFFD}"
        #expect(try title(mixed) == "a\(r)\(r)b\(r)c\(r)d\(r)\(r)\(r)\(r)e\(r)\(r)g\(r)")
        // The same inside a string with escapes, and in a key.
        let escaped = Array("{\"k\\n\u{ED}\u{A0}\u{80}\":\"x\\t\u{ED}\u{A0}\u{80}y\"}".unicodeScalars.map { UInt8($0.value) })
        let o = try JSONParser.parse(Data(escaped)).jsonObject()
        #expect(o.keys == ["k\n\u{FFFD}"])
        #expect(o["k\n\u{FFFD}"] == .string("x\t\u{FFFD}y"))
    }

    // ----- Text compared as Kotlin compares it: UTF-16 unit by unit -----

    @Test func canonicallyEqualNodeIdsAreTwoNodes() throws {
        let m = try parse(mapText(
            start: nfc,
            "\"nodes\":{\"\(nfc)\":{\"go\":\"s\"},\"\(nfd)\":{\"go\":\"t\"},\"s\":\(endNode("S", play: "at_s")),"
                + "\"t\":\(endNode("T", play: "at_t"))}"
        ))
        #expect(m.nodes.count == 4)
        let turn = try Session(m).start()
        #expect(clips(turn) == ["at_s"])
        #expect(sameList(turn.visited, [nfc, "s"]))
        // U+212A is a node of its own, not "K".
        let k = try GameMap.parse(
            "{\"format\":\"1\",\"id\":\"g\",\"title\":\"T\",\"start\":\"a\",\"nodes\":{\"a\":{\"go\":\"\(kelvin)\"},"
                + "\"\(kelvin)\":\(endNode("Kelvin", play: "kelvin")),\"K\":\(endNode("K", play: "k"))}}"
        )
        #expect(k.nodes.count == 3)
        let kt = try Session(k).start()
        #expect(kt.end?.title == "Kelvin")
        #expect(clips(kt) == ["kelvin"])
    }

    @Test func canonicallyEqualVariablesAreTwoVariables() throws {
        let m = try parse(mapText("\"nodes\":{\"s\":{\"set\":{\"\(nfc)\":1,\"\(nfd)\":2},\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"))
        let s = Session(m)
        _ = try s.start()
        #expect(s.vars.count == 2)
        #expect(sameList(s.vars.keys, [nfc, nfd]))
        #expect(s.vars[nfc] == .number(1))
        #expect(s.vars[nfd] == .number(2))
        // "K > 1" reads the variable K, which a map's U+212A isn't.
        let k = try parse(mapText(
            "\"vars\":{\"\(kelvin)\":5},\"nodes\":{\"s\":{\"ask\":{\"answers\":[{\"words\":[\"go\"],\"when\":\"K > 1\","
                + "\"go\":\"win\"},{\"any\":true,\"go\":\"lose\"}]}},\"win\":\(endNode("WIN")),\"lose\":\(endNode("LOSE"))}"
        ))
        let ks = Session(k)
        _ = try ks.start()
        let turn = try ks.answer("go")
        #expect(turn.heard?.how == "any")
        #expect(turn.end?.title == "LOSE")
    }

    @Test func canonicallyEqualKeepNamesAreBothKept() throws {
        let m = try parse(mapText("\"keep\":[\"\(nfc)\",\"\(nfd)\"],\"nodes\":{\"s\":\(endNode())}"))
        #expect(sameList(m.keep, [nfc, nfd]))
        // A pack's keep merges with Kotlin's distinct().
        let pack = "{\"id\":\"p\",\"game\":\"g\",\"keep\":[\"\(nfd)\",\"\(nfc)\"]}"
        let merged = try parse(mapText("\"keep\":[\"\(nfc)\"],\"nodes\":{\"s\":\(endNode())}"), packs: [pack])
        #expect(sameList(merged.keep, [nfc, nfd]))
    }

    @Test func bigObjectsKeepCanonicallyEqualKeysApart() throws {
        // Past 12 keys a map keeps an index; keys that are canonically equal but not the same stay two keys.
        let filler = (0..<14).map { "\"k\($0)\":\($0)" }.joined(separator: ",")
        var o = try JSONParser.parse("{\(filler),\"\(nfc)\":1,\"K\":2,\"\(nfd)\":3,\"\(kelvin)\":4}").jsonObject()
        #expect(o.count == 18)
        #expect(o[nfc] == .literal("1"))
        #expect(o["K"] == .literal("2"))
        #expect(o[nfd] == .literal("3"))
        #expect(o[kelvin] == .literal("4"))
        o[nfc] = nil
        #expect(o[nfc] == nil)
        #expect(o[nfd] == .literal("3"))
        o[nfc] = .literal("5")
        #expect(sameList(Array(o.keys.suffix(4)), ["K", nfd, kelvin, nfc]))
        // A twin arriving after the index was built.
        var v = VarStore()
        for i in 0..<20 { v["v\(i)"] = .number(Double(i)) }
        v[nfc] = "a"
        v[nfd] = "b"
        #expect(v.count == 22)
        #expect(v[nfc] == "a")
        #expect(v[nfd] == "b")
        #expect(v["v19"] == .number(19))
    }

    @Test func aByCaseMatchesOnlyItsExactText() throws {
        let m = try parse(mapText(
            "\"vars\":{\"mood\":\"caf\(nfc)\"},\"nodes\":{\"s\":{\"say\":[{\"by\":\"mood\",\"cases\":{\"caf\(nfd)\":"
                + "[{\"play\":\"x\",\"dur\":1}]},\"else\":[{\"play\":\"y\",\"dur\":1}]}],\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"
        ))
        #expect(clips(try Session(m).start()) == ["y"])
    }

    @Test func aDrawDeckHoldsExactNames() throws {
        let m = try GameMap.parse(
            "{\"format\":\"1\",\"id\":\"g\",\"title\":\"T\",\"start\":\"a\",\"vars\":{\"deck_d\":\"caf\(nfc)\"},\"nodes\":{"
                + "\"a\":{\"go\":{\"draw\":[\"caf\(nfd)\",\"b\"],\"deck\":\"d\"}},\"caf\(nfd)\":\(endNode("W1", play: "nfd")),"
                + "\"caf\(nfc)\":\(endNode("W0", play: "nfc")),\"b\":\(endNode("W2"))}}"
        )
        var calls: [Int] = []
        let s = Session(m, choose: { n in calls.append(n); return 0 })
        let turn = try s.start()
        #expect(turn.end?.title == "W1")
        #expect(clips(turn) == ["nfd"])
        #expect(calls == [2])
        #expect(s.vars["deck_d"] == .string("caf\(nfc),caf\(nfd)"))
    }

    @Test func symbolTablesKeepCanonicallyEqualSymbols() throws {
        func play(_ answer: String, _ said: String) throws -> Turn {
            let m = try parse(mapText(
                "\"symbols\":{\"uni\":{\"\(nfc)\":[\"eh\"],\"\(nfd)\":[\"ee\"],\"x\":[\"ex\"]}},\"nodes\":{\"s\":{\"ask\":"
                    + "{\"answers\":[\(answer),{\"any\":true,\"go\":\"lose\"}]}},\"win\":\(endNode("WIN")),"
                    + "\"lose\":\(endNode("LOSE"))}"
            ))
            #expect(m.symbols["uni"]?.count == 3)
            let s = Session(m)
            _ = try s.start()
            return try s.answer(said)
        }
        #expect(try play("{\"seq\":\"\(nfc)\",\"symbols\":\"uni\",\"go\":\"win\"}", "eh").heard?.how == "seq")
        let spelled = try play("{\"seq\":\"x\",\"symbols\":\"uni\",\"spelled\":true,\"least\":2,\"go\":\"win\"}", "eh ee")
        #expect(spelled.heard?.how == "seq")
        #expect(spelled.end?.title == "WIN")
    }

    @Test func answersGoingToCanonicallyEqualNodesAreRivals() throws {
        // Kotlin's data class equality on Go.To: two different node names, so "red or blue" is unclear.
        let m = try parse(mapText(
            "\"nodes\":{\"s\":{\"ask\":{\"answers\":[{\"words\":[\"red\"],\"go\":\"caf\(nfc)\"},{\"words\":[\"blue\"],"
                + "\"go\":\"caf\(nfd)\"}],\"else\":\"other\"}},\"caf\(nfc)\":\(endNode("NFC")),\"caf\(nfd)\":\(endNode("NFD")),"
                + "\"other\":\(endNode("ELSE"))}"
        ))
        let ask = try #require(m.nodes["s"]?.ask)
        #expect(try Matcher.match(m, ask, m.vars, "red or blue") == Matcher.Result(index: nil, repeat: false, how: "not understood"))
        let s = Session(m)
        _ = try s.start()
        #expect(try s.answer("red").end?.title == "NFC")
        #expect(Go.to("caf\(nfc)") != Go.to("caf\(nfd)"))
    }

    @Test func regularExpressionsAreKeptByTheirExactText() throws {
        // Each Match.Re compiles its own pattern: "[^é]" spelled decomposed doesn't take "e".
        let m = try parse(mapText(
            "\"nodes\":{\"s\":{\"ask\":{\"answers\":[{\"re\":\"^[^\(nfc)]+$\",\"go\":\"s2\"},{\"any\":true,\"go\":\"s2\"}]}},"
                + "\"s2\":{\"ask\":{\"answers\":[{\"re\":\"^[^\(nfd)]+$\",\"go\":\"m2\"},{\"any\":true,\"go\":\"none\"}]}},"
                + "\"m2\":\(endNode("M2")),\"none\":\(endNode("NONE"))}"
        ))
        let s = Session(m)
        _ = try s.start()
        #expect(try s.answer("x").heard?.how == "re")
        let turn = try s.answer("e")
        #expect(turn.heard?.how == "any")
        #expect(turn.end?.title == "NONE")
        // The shared cache of compiled patterns keeps the two apart too.
        let a = try RegexCache.shared.regex("^[\(nfc)]$")
        let b = try RegexCache.shared.regex("^[\(nfd)]$")
        #expect(same(a.pattern, "^[\(nfc)]$"))
        #expect(same(b.pattern, "^[\(nfd)]$"))
    }

    // ----- Text Kotlin writes -----

    @Test func aMissingKeyMessageCutsAPairAsTheJVMPrintsIt() throws {
        // take(120) keeps half of the emoji; the JVM writes the lone surrogate as "?".
        let text = String(repeating: "a", count: 103) + "\u{1F600}bbbb"
        let e = #expect(throws: MapError.self) {
            try parse(mapText(
                "\"nodes\":{\"s\":{\"say\":[{\"play\":\"p\",\"dur\":1,\"lines\":[{\"at\":0,\"text\":\"\(text)\"}]}],"
                    + "\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"
            ))
        }
        #expect(e?.kind == .map)
        #expect(e?.message == "missing \"who\" in {\"at\":0,\"text\":\"" + String(repeating: "a", count: 103) + "?")
    }

    @Test func doublesAreWrittenWithJDK17sDigits() throws {
        // Java's FloatingDecimal: not always the shortest digits (from JDK 17's Double.toString).
        let cases: [(UInt64, String)] = [
            (0x1, "4.9E-324"), (0x2, "1.0E-323"), (0xA, "4.9E-323"), (0xC, "5.9E-323"), (0x12, "8.9E-323"),
            (0x20, "1.58E-322"), (0x800, "1.0118E-320"), (0x20000, "6.47582E-319"),
            (0x44B5_2D02_C7E1_4AF6, "9.999999999999999E22"), (0x44A5_2D02_C7E1_4AF6, "4.9999999999999996E22"),
            (0x44AD_A56A_4B08_35C0, "7.0000000000000004E22"), (0x8000_0000_0000_0001, "-4.9E-324"),
        ]
        for (bits, java) in cases {
            #expect(Kt.doubleString(Double(bitPattern: bits)) == java, "\(java)")
        }
        // A by-case on the smallest Double: Kotlin's key is "4.9E-324".
        let m = try parse(mapText(
            "\"vars\":{\"x\":5e-324},\"nodes\":{\"s\":{\"say\":[{\"by\":\"x\",\"cases\":{\"4.9E-324\":[{\"play\":\"case\","
                + "\"dur\":1}]},\"else\":[{\"play\":\"else\",\"dur\":1}]}],\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"
        ))
        let s = Session(m)
        #expect(clips(try s.start()) == ["case"])
        #expect(s.vars.kotlinDescription == "{x=4.9E-324}")
    }

    // ----- Random choices: Kotlin asks choose(n) first, then coerceIn -----

    @Test func theChooserIsAskedBeforeTheRangeIsChecked() throws {
        var calls: [Int] = []
        let chooser: (Int) throws -> Int = { n in calls.append(n); return 0 }
        // to - from + 1 wraps to Int.MIN_VALUE; { 0 } still gives 0, which coerceIn(0, Int.MAX_VALUE) keeps.
        let wide = try parse(mapText("\"nodes\":{\"s\":{\"set\":{\"r\":\"rand(0, 2147483647)\"},\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"))
        let s = Session(wide, choose: chooser)
        _ = try s.start()
        #expect(s.vars["r"] == .number(0))
        #expect(calls == [-2_147_483_648])
        for (go, expected) in [
            ("{\"random\":[]}", "maximum -1 is less than minimum 0."), ("{\"draw\":[],\"deck\":\"d\"}", "maximum -1 is less than minimum 0."),
        ] {
            calls = []
            let m = try parse(mapText("\"nodes\":{\"s\":{\"go\":\(go)}}"))
            let e = #expect(throws: PlayError.self) { try Session(m, choose: chooser).start() }
            #expect(e?.message == "Cannot coerce value to an empty range: " + expected)
            #expect(calls == [0])
        }
        calls = []
        let backwards = try parse(mapText("\"nodes\":{\"s\":{\"set\":{\"r\":\"rand(5, 3)\"},\"end\":{\"kind\":\"k\",\"title\":\"t\"}}}"))
        let e = #expect(throws: PlayError.self) { try Session(backwards, choose: chooser).start() }
        #expect(e?.message == "Cannot coerce value to an empty range: maximum -2 is less than minimum 0.")
        #expect(calls == [-1])
    }
}
