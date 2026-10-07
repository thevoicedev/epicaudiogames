// text.json (README section 9.2): Text, Commands, Matcher.mixed, toDoubleOrNull, Double.toString and kotlinx's JSON.

import EpicConformance
import EpicEngine
import Testing

@Suite struct TextConfTests {
    private func file() throws -> JSONObject { try goldens().readJSON("text.json") }

    /// Text.normalise, Text.digits and Commands.isPause.
    @Test func strings() throws {
        var diffs = Diffs()
        for row in try file().fx("strings").fxArray() {
            let r = try row.fxArray()
            let s = try r[0].fxString()
            let normalised = SpokenText.normalise(s)
            if !same(normalised, try r[1].fxString()) {
                diffs.add("normalise \(Canon.json(.string(s))): kotlin \(r[1].short), swift \(Canon.json(.string(normalised)))")
            }
            let digits = SpokenText.digits(s)
            if !same(digits, try r[2].fxString()) {
                diffs.add("digits \(Canon.json(.string(s))): kotlin \(r[2].short), swift \(Canon.json(.string(digits)))")
            }
            if AppCommands.isPause(s) != (try r[3].fxBool()) { diffs.add("isPause \(Canon.json(.string(s)))") }
        }
        diffs.report("text.json strings")
    }

    @Test func phrases() throws {
        let f = try file()
        var diffs = Diffs()
        func phrase(_ j: JSON) throws -> Phrase {
            let p = try j.fxArray()
            return Phrase(try p[0].fxString(), try p[1].fxBool())
        }
        for row in try f.fx("phraseLength").fxArray() {
            let r = try row.fxArray()
            let got = SpokenText.phraseLength(try r[0].fxString(), try phrase(r[1]))
            if got != (try r[2].fxInt()) { diffs.add("phraseLength \(row.short): swift \(got)") }
        }
        for row in try f.fx("longest").fxArray() {
            let r = try row.fxArray()
            let got = SpokenText.longest(try r[0].fxString(), try r[1].fxArray().map(phrase))
            let text = got.map { Canon.json([.string($0.text), .bool($0.exact)]) } ?? "null"
            if !same(text, Canon.reencode(r[2])) { diffs.add("longest \(row.short): swift \(text)") }
        }
        for row in try f.fx("negated").fxArray() {
            let r = try row.fxArray()
            let got = SpokenText.negated(try r[0].fxString(), try r[1].fxString())
            if got != (try r[2].fxBool()) { diffs.add("negated \(row.short): swift \(got)") }
        }
        diffs.report("text.json phraseLength, longest and negated")
    }

    @Test func symbols() throws {
        let f = try file()
        var tables: [String: LinkedMap<[String]>] = [:]
        for (name, rows) in try f.fx("tables").fxObject() {
            var table = LinkedMap<[String]>()
            for row in try rows.fxArray() {
                let r = try row.fxArray()
                table[try r[0].fxString()] = try r[1].fxArray().map { try $0.fxString() }
            }
            tables[name] = table
        }
        var diffs = Diffs()
        for row in try f.fx("symbols").fxArray() {
            let r = try row.fxArray()
            guard let table = tables[try r[1].fxString()] else { throw ConformanceError("no table in \(row.short)") }
            let got = SpokenText.symbols(try r[0].fxString(), table, spelled: try r[2].fxBool())
            if !same(got, try r[3].fxString()) { diffs.add("symbols \(row.short): swift \(Canon.json(.string(got)))") }
        }
        diffs.report("text.json symbols")
    }

    /// Matcher.mixed with each free variant's map.
    @Test func mixed() throws {
        let g = try goldens()
        var diffs = Diffs()
        for row in try file().fx("mixed").fxArray() {
            let r = try row.fxArray()
            let got = Matcher.mixed(try g.map(r[0].fxString()), try r[1].fxString())
            if got != (try r[2].fxOptBool()) { diffs.add("mixed \(row.short): swift \(got.map { "\($0)" } ?? "nil")") }
        }
        diffs.report("text.json mixed")
    }

    /// Kotlin's String.toDoubleOrNull and Java's Double.toString (where JDK 17 has the shortest digits).
    @Test func numbers() throws {
        let f = try file()
        var diffs = Diffs()
        for row in try f.fx("toDouble").fxArray() {
            let r = try row.fxArray()
            let got = Kt.toDoubleOrNull(try r[0].fxString())
            if !same(got, try r[1].fxOptDouble()) {
                diffs.add("toDoubleOrNull \(r[0].short): kotlin \(r[1].short), swift \(got.map { Canon.json(.double($0)) } ?? "null")")
            }
        }
        for row in try f.fx("doubleString").fxArray() {
            let r = try row.fxArray()
            let got = Kt.doubleString(try r[0].fxDouble())
            if !same(got, try r[1].fxString()) { diffs.add("doubleString \(r[0].short): kotlin \(r[1].short), swift \(got)") }
        }
        diffs.report("text.json toDouble and doubleString")
    }

    /// kotlinx's primitive accessors (the texts are all RFC 8259 JSON, which is what the Swift reader takes).
    @Test func primitives() throws {
        var diffs = Diffs()
        for row in try file().fx("primitives").fxArray() {
            let r = try row.fxArray()
            let text = try r[0].fxString()
            let p = try JSONParser.parse(text)
            func check(_ what: String, _ ok: Bool, _ got: String) {
                if !ok { diffs.add("\(what) of \(text): kotlin \(row.short), swift \(got)") }
            }
            check("content", same(p.content, try r[1].fxString()), p.content ?? "nil")
            check("isString", p.isString == (try r[2].fxBool()), "\(p.isString)")
            check("doubleOrNull", same(p.doubleOrNull, try r[3].fxOptDouble()), "\(p.doubleOrNull.map { "\($0)" } ?? "nil")")
            check("booleanOrNull", p.booleanOrNull == (try r[4].fxOptBool()), "\(p.booleanOrNull.map { "\($0)" } ?? "nil")")
            check("intOrNull", p.intOrNull.map(Int.init) == (try r[5].fxOptInt()), "\(p.intOrNull.map { "\($0)" } ?? "nil")")
            check("longOrNull", same(p.longOrNull.map { String($0) }, try r[6].fxOptString()),
                  "\(p.longOrNull.map { "\($0)" } ?? "nil")")
        }
        diffs.report("text.json primitives")
    }
}

/// text.json's "json": kotlinx's JsonElement.toString(), the text MapException messages embed.
@Suite struct KotlinxDescriptionTests {
    @Test func samples() throws {
        var diffs = Diffs()
        var n = 0
        for row in try goldens().readJSON("text.json").fx("json").fxArray() {
            let r = try row.fxArray()
            let text = try r[0].fxString()
            let got = try JSONParser.parse(text).kotlinxDescription
            if !same(got, try r[1].fxString()) { diffs.add("\(text): kotlin \(r[1].short), swift \(got)") }
            n += 1
        }
        diffs.report("text.json json")
        #expect(n > 30)
    }
}
