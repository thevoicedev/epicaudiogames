// Cli.kt (lines 24-37): games/nuclear-war/lines.json is Lines.all(), entry for entry, as --nuclear-lines writes it.

import Foundation
import Testing

@testable import EpicEngine

/**
 * games/nuclear-war/lines.json, which Kotlin's `--nuclear-lines` writes from Lines.all() for tools/games/nuclearwar.py,
 * is what the Swift Lines.all() gives: the same phrases in the same order, each with Cli.kt's keys ("speak" only
 * where it differs from "text", "before" and "after" only where they aren't empty), and the file laid out as Cli.kt
 * writes it (kotlinx's JSON, one object per line). Texts compare UTF-16 unit by unit, as Kotlin's do.
 */
struct LinesFileTests {
    private let file: URL
    private let lines: [Lines.Phrase]

    init() throws {
        file = try TestRepo.games().appendingPathComponent("\(NuclearWar.id)/lines.json")
        lines = try Lines.all()
    }

    /// A phrase as Cli.kt writes it.
    private static func entry(_ p: Lines.Phrase) -> JSONObject {
        var o = JSONObject()
        o["text"] = .string(p.text)
        if !Kt.utf16Equal(p.speak, p.text) { o["speak"] = .string(p.speak) }
        if !p.before.isEmpty { o["before"] = .string(p.before) }
        if !p.after.isEmpty { o["after"] = .string(p.after) }
        return o
    }

    @Test func everyEntryIsThePhraseAtItsPlace() throws {
        let entries = try JSONParser.parse(Data(contentsOf: file)).jsonArray()
        #expect(entries.count == lines.count, "lines.json has \(entries.count) lines, Lines.all() \(lines.count)")
        var wrong = 0
        for (i, (e, p)) in zip(entries, lines).enumerated() {
            let o = try e.jsonObject()
            let expected = Self.entry(p)
            // kotlinx's equality ignores key order; Cli.kt's keys come in its order too.
            if o.keys != expected.keys || JSON.object(o) != JSON.object(expected) {
                wrong += 1
                if wrong <= 10 {
                    let want = JSON.object(expected).kotlinxDescription
                    Issue.record("entry \(i): lines.json has \(e.kotlinxDescription), Lines.all() gives \(want)")
                }
            }
        }
        #expect(wrong == 0, "\(wrong) entries differ")
    }

    @Test func theFileIsAsCliWritesIt() throws {
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        let written = JSONWriter.write(.array(lines.map { .object(Self.entry($0)) }))
            .replacingOccurrences(of: "},{", with: "},\n{", options: .literal) + "\n"
        if Kt.utf16Equal(text, written) { return }
        let have = Kt.split(text, "\n")
        let want = Kt.split(written, "\n")
        let i = zip(have, want).enumerated().first { !Kt.utf16Equal($0.element.0, $0.element.1) }?.offset
            ?? min(have.count, want.count)
        Issue.record("""
            lines.json differs from Cli.kt's writing of Lines.all() at line \(i + 1):
              file:  \(have.getOrNull(i) ?? "(end)")
              Swift: \(want.getOrNull(i) ?? "(end)")
            """)
    }
}
