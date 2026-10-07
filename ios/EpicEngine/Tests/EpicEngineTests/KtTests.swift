// Tests for the Kotlin library behaviour the engine copies: numbers, text, Random(seed) and collections.

import Testing

@testable import EpicEngine

struct KtTests {
    // ----- Reading numbers (Kotlin's toDoubleOrNull / toIntOrNull, checked against the JVM) -----

    @Test func readsDoublesWithJavasGrammar() {
        let cases: [(String, Double?)] = [
            ("1", 1), ("-1", -1), ("+1", 1), ("1.", 1), (".5", 0.5), (".", nil), ("-.5", -0.5), ("1e5", 1e5),
            ("1E5", 1e5), ("1e", nil), ("1e+", nil), ("1e-5", 1e-5), (" 12 ", 12), ("\t12\n", 12), ("12f", 12),
            ("12D", 12), ("12L", nil), ("-Infinity", -.infinity), ("+Infinity", .infinity), ("infinity", nil),
            ("Inf", nil), ("inf", nil), ("0x1p3", 8), ("0X1P3", 8), ("0x1.8p1", 3), ("0x.8p1", 1), ("0x1.p1", 2),
            ("0x.p1", nil), ("0x1", nil), ("0x1p", nil), ("0x1p-2", 0.25), ("0x1p3f", 8), ("1_000", nil),
            ("1,5", nil), ("١٢", nil), ("12a", nil), ("--1", nil), ("1e400", .infinity), ("1e-400", 0),
            ("3.e2", 300), (".e2", nil), ("e2", nil), ("1.5.5", nil), ("+", nil), ("-", nil), ("", nil), (" ", nil),
            ("\u{0}5", 5), ("5\u{a0}", nil), ("1d5", nil), ("true", nil),
        ]
        for (text, expected) in cases {
            #expect(Kt.toDoubleOrNull(text) == expected, "\(text)")
        }
        #expect(Kt.toDoubleOrNull("NaN")!.isNaN)
        #expect(Kt.toDoubleOrNull("-NaN")!.isNaN)
        #expect(Kt.toDoubleOrNull("nan") == nil)
        #expect(Kt.toDoubleOrNull("-0")!.sign == .minus)
    }

    @Test func readsIntsAsKotlinDoes() {
        #expect(Kt.int32OrNull("2147483647") == Int32.max)
        #expect(Kt.int32OrNull("2147483648") == nil)
        #expect(Kt.int32OrNull("-2147483648") == Int32.min)
        #expect(Kt.int32OrNull("-2147483649") == nil)
        #expect(Kt.int32OrNull("+5") == 5)
        #expect(Kt.int32OrNull("00012") == 12)
        #expect(Kt.int32OrNull("-") == nil)
        #expect(Kt.int32OrNull("+") == nil)
        #expect(Kt.int32OrNull("") == nil)
        #expect(Kt.int32OrNull(" 1") == nil)
        #expect(Kt.int32OrNull("1.0") == nil)
        #expect(Kt.int32OrNull("١٢") == 12)            // Character.digit takes other decimal digits
        #expect(Kt.int32OrNull("+\u{663}") == 3)
        #expect(Kt.int64OrNull("99999999999") == 99_999_999_999)
        #expect(Kt.int64OrNull("9223372036854775808") == nil)
        #expect(Kt.int64OrNull("-9223372036854775808") == Int64.min)
    }

    // ----- Writing numbers (Java's Double.toString, from JDK 17) -----

    @Test func writesDoublesAsJavaDoes() {
        let cases: [(Double, String)] = [
            (1, "1.0"), (0.001, "0.001"), (1e-4, "1.0E-4"), (1e7, "1.0E7"), (9999999.999, "9999999.999"),
            (123456789.123, "1.23456789123E8"), (-0.0, "-0.0"), (0, "0.0"), (0.1 + 0.2, "0.30000000000000004"),
            (1.0 / 3, "0.3333333333333333"), (100, "100.0"), (1e21, "1.0E21"), (12.5, "12.5"), (1e-5, "1.0E-5"),
            (2.5e-7, "2.5E-7"), (1234567, "1234567.0"), (0.000999, "9.99E-4"), (1e300, "1.0E300"), (-1.5, "-1.5"),
            (2.2250738585072014E-308, "2.2250738585072014E-308"), (.nan, "NaN"), (.infinity, "Infinity"),
            (-.infinity, "-Infinity"),
        ]
        for (d, expected) in cases {
            #expect(Kt.doubleString(d) == expected, "\(d)")
        }
    }

    @Test func truncatesToLongAsKotlinDoes() {
        #expect(Kt.saturatingLong(.nan) == 0)
        #expect(Kt.saturatingLong(1e20) == Int64.max)
        #expect(Kt.saturatingLong(-1e20) == Int64.min)
        #expect(Kt.saturatingLong(.infinity) == Int64.max)
        #expect(Kt.saturatingLong(9223372036854775807.0) == Int64.max)
        #expect(Kt.saturatingLong(-1.9) == -1)
        #expect(Kt.saturatingLong(2.9) == 2)
    }

    @Test func modIsFloored() {
        #expect(Kt.floorMod(7, 4) == 3)
        #expect(Kt.floorMod(-7, 4) == 1)
        #expect(Kt.floorMod(7, -4) == -1)
        #expect(Kt.floorMod(-7, -4) == -3)
        #expect(Kt.floorMod(5.5, 2) == 1.5)
        #expect(Kt.floorMod(-0.0, 4).sign == .minus)
        #expect(Kt.floorMod(5, .infinity) == 5)
        #expect(Kt.floorMod(-5, .infinity) == .infinity)
        #expect(Kt.floorMod(5, 0).isNaN)
        #expect(Kt.floorMod(Int32(-7), Int32(4)) == 1)
        #expect(Kt.floorMod(Int32(-1516211447), Int32(8)) == 1)
    }

    @Test func maxAndMinAreJavas() {
        #expect(Kt.max(.nan, 1).isNaN)
        #expect(Kt.max(1, .nan).isNaN)
        #expect(Kt.min(.nan, 1).isNaN)
        #expect(Kt.max(-0.0, 0).sign == .plus)
        #expect(Kt.max(0, -0.0).sign == .plus)
        #expect(Kt.min(0, -0.0).sign == .minus)
        #expect(Kt.min(-0.0, 0).sign == .minus)
        #expect(Kt.max(2, 3) == 3)
        #expect(Kt.min(2, 3) == 2)
    }

    // ----- Text (UTF-16, as Kotlin's strings) -----

    @Test func comparesTextByUTF16Units() {
        #expect(Kt.compare("a", "b") < 0)
        #expect(Kt.compare("Z", "a") < 0)
        #expect(Kt.compare("ab", "a") > 0)
        #expect(Kt.compare("", "") == 0)
        #expect(Kt.compare("\u{FFFF}", "😀") > 0)         // U+FFFF is above a high surrogate
        #expect(!Kt.utf16Equal("é", "e\u{301}"))          // Swift's == would say they're equal
        #expect(Kt.utf16Less("a", "b"))
    }

    @Test func measuresAndCutsByUTF16Units() {
        #expect(Kt.length("é😀") == 3)
        #expect(Kt.take("abc", 2) == "ab")
        #expect(Kt.take("abc", 5) == "abc")
        #expect(Kt.indexOf(" a bb ", " bb ") == 2)
        #expect(Kt.indexOf("abc", "x") == -1)
        #expect(Kt.indexOf("😀 a", " a") == 2)
        #expect(Kt.contains("abc", ""))
        #expect(Kt.split("a,,b", ",") == ["a", "", "b"])
        #expect(Kt.split("", ",") == [""])
        #expect(Kt.split("a,", ",") == ["a", ""])
    }

    @Test func trimsKotlinWhitespace() {
        #expect(Kt.trim("\u{a0} x \u{3000}") == "x")
        #expect(Kt.trim("\u{1}x\u{1}") == "\u{1}x\u{1}")
        #expect(Kt.trim("\u{1c}x\t\n") == "x")
        #expect(Kt.isWhitespace(0x2028))
        #expect(!Kt.isWhitespace(0x200B))
    }

    @Test func hashesAsJavaDoes() {
        let cases: [(String, Int32)] = [
            ("", 0), ("a", 97), ("Aa", 2112), ("BB", 2112), ("hello", 99162322), ("GRIBBO", 2110638737),
            ("PIP", 79223), ("ALEX", 2011678), ("ROBIN", 78147978), ("NARRATOR", -1516211447), ("é😀", 1996812),
        ]
        for (s, h) in cases { #expect(Kt.javaHash(s) == h, "\(s)") }
    }

    // ----- Random(seed): Kotlin's XorWowRandom, values from the JVM -----

    @Test func xorWowMatchesKotlin() throws {
        let r0 = XorWowRandom(seed: 0)
        #expect((0..<5).map { _ in r0.nextInt() } == [-1934310868, 1409199696, -649160781, -1454478562, -1464141532])
        let bounds = [1, 2, 3, 5, 6, 7, 8, 10, 16, 100, 1000, 1 << 30, Int(Int32.max)]
        #expect(try bounds.map { try r0.nextInt(until: $0) } == [0, 0, 1, 4, 5, 0, 0, 8, 3, 63, 868, 1018314137, 103896983])
        #expect(try r0.nextInt(from: -5, until: 5) == 0)
        #expect(try r0.nextInt(from: Int(Int32.min), until: Int(Int32.max)) == -1666136984)
        #expect(try r0.nextInt(from: Int(Int32.min), until: 0) == -222612309)
        #expect(try (0..<3).map { _ in try r0.nextDouble().bitPattern } == [
            0x3fe20a8ec39ce745, 0x3fc59a150f6be188, 0x3fe0af2a527e68ad,
        ])
        #expect(try (0..<4).map { _ in try r0.nextBoolean() } == [false, false, false, false])
        #expect([0, 1, 5, 31, 32].map { r0.nextBits($0) } == [0, 0, 1, 1000441712, -105673955])
        #expect(try Array(0..<9).kShuffled(r0) == [1, 0, 2, 3, 8, 5, 6, 4, 7])
        #expect(try Array(0..<9).kRandom(r0) == 4)
        #expect(try [Int]().kRandomOrNull(r0) == nil)
        #expect(try Array(0..<9).kRandomOrNull(r0) == 2)

        let r7 = XorWowRandom(seed: 7)
        #expect((0..<5).map { _ in r7.nextInt() } == [-182312124, 11901178, -1941452650, 1600128533, 1560878315])
        #expect(try bounds.map { try r7.nextInt(until: $0) } == [0, 1, 2, 2, 3, 6, 2, 4, 14, 69, 146, 413946253, 495322705])

        let rMin = XorWowRandom(seed: Int32.min)
        #expect((0..<5).map { _ in rMin.nextInt() } == [-468773749, -303786953, 2109491522, 1936655093, 905126675])

        let rMax = XorWowRandom(seed: Int32.max)
        #expect((0..<2).map { _ in rMax.nextInt() } == [-1519020059, 1146489314])
    }

    @Test func xorWowLongSeedsMatchKotlin() throws {
        let cases: [(Int64, Int, Int, UInt64)] = [
            (0, -1934310868, 48, 0x3feb29d2f54a7358),
            (-1, -280203964, 4, 0x3fe02f450a96c2c2),
            (1 << 32, 669068263, 39, 0x3fc2f1da0e72e268),
            (123456789012345, 2024811512, 88, 0x3fba463a48811df8),
            (Int64.min, -1399536436, 8, 0x3fa07af4d3125a40),
        ]
        for (seed, first, below100, double) in cases {
            let r = XorWowRandom(longSeed: seed)
            #expect(r.nextInt() == first, "\(seed)")
            #expect(try r.nextInt(until: 100) == below100, "\(seed)")
            #expect(try r.nextDouble().bitPattern == double, "\(seed)")
        }
    }

    @Test func anEmptyRandomRangeIsAnError() {
        let r = XorWowRandom(seed: 1)
        #expect(throws: PlayError("Random range is empty: [0, 0).")) { try r.nextInt(until: 0) }
        #expect(throws: PlayError.self) { try r.nextInt(from: 3, until: 3) }
        #expect(throws: PlayError("Collection is empty.")) { try [Int]().kRandom(r) }
    }

    @Test func nextIntOfOneStillDraws() throws {
        // Kotlin's nextInt(1) takes a value from the generator, as every other bound does.
        let a = XorWowRandom(seed: 3)
        let b = XorWowRandom(seed: 3)
        #expect(try a.nextInt(until: 1) == 0)
        _ = b.nextInt()
        #expect(a.nextInt() == b.nextInt())
    }

    @Test func randomOrNullOfNothingDoesNotDraw() throws {
        let a = XorWowRandom(seed: 3)
        let b = XorWowRandom(seed: 3)
        #expect(try [String]().kRandomOrNull(a) == nil)
        #expect(a.nextInt() == b.nextInt())
    }

    @Test func rangesDrawAsKotlinsNextIntOfARange() throws {
        let a = XorWowRandom(seed: 9)
        let b = XorWowRandom(seed: 9)
        #expect(try a.nextInt(in: 1...3) == b.nextInt(from: 1, until: 4))
        #expect(try a.nextInt(in: 0...Int(Int32.max)) == b.nextInt(from: -1, until: Int(Int32.max)) + 1)
    }

    // ----- Collections -----

    @Test func collectionsBehaveAsKotlins() throws {
        #expect([3, 1, 3, 2, 1].uniqued() == [3, 1, 2])
        let words = ["bb", "a", "cc", "d"]
        #expect(words.stableSorted { $0.count } == ["a", "d", "bb", "cc"])
        #expect(words.stableSorted(descending: true) { $0.count } == ["bb", "cc", "a", "d"])
        #expect(words.kMaxBy { $0.count } == "bb")
        #expect([String]().kMaxBy { $0.count } == nil)
        #expect(try 5.clamped(0, 3) == 3)
        #expect(try (-1).clamped(0, 3) == 0)
        #expect(throws: PlayError.self) { try 1.clamped(0, -1) }
    }

    // ----- Values and ordered maps -----

    @Test func valuesCompareAsBoxedKotlinValues() {
        #expect(Value.number(0) != Value.number(-0.0))
        #expect(Value.number(.nan) == Value.number(.nan))
        #expect(Value.number(1) == 1)
        #expect(Value.string("é") != Value.string("e\u{301}"))
        #expect(Value.bool(true) != Value.number(1))
        #expect(Set<Value>([.number(.nan), .number(.nan), 1, "1", true]).count == 4)
        #expect(Value.number(1).kotlinString == "1.0")
        #expect(Value.number(1e7).kotlinString == "1.0E7")
        #expect(Value.bool(false).kotlinString == "false")
    }

    @Test func linkedMapKeepsInsertionOrder() {
        var m: VarStore = ["b": 1, "a": 2]
        m["c"] = 3
        m["b"] = 4
        #expect(m.keys == ["b", "a", "c"])
        #expect(m.values == [4, 2, 3])
        m["a"] = nil
        #expect(m.keys == ["b", "c"])
        #expect(m["c"] == 3)
        m["a"] = "x"
        #expect(m.keys == ["b", "c", "a"])
        #expect(m == ["a": "x", "c": 3, "b": 4])
        #expect(m != ["a": "x", "c": 3])
        #expect(m.kotlinDescription == "{b=4.0, c=3.0, a=x}")
        var n: VarStore = ["z": true]
        n.putAll(m)
        #expect(n.keys == ["z", "b", "c", "a"])
        n.removeAll()
        #expect(n.isEmpty)
    }
}
