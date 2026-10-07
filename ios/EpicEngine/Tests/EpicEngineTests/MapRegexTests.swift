// The maps' "re" answers: ICU (NSRegularExpression) must read them as java.util.regex does in the Kotlin engine.

import Foundation
import Testing
@testable import EpicEngine

@Suite struct MapRegexTests {
    /// Where ICU and java.util.regex part ways: POSIX and Unicode classes, class set operations ([a-z&&[^e]],
    /// [a--b], nested classes), inline flags, back references and the newer escapes. A map's pattern keeps clear of
    /// all of them, so both engines take the same answers.
    static let unsafe: [(String, String)] = [
        ("[[", "a class inside a class"), ("&&", "a class intersection"), ("--", "a class difference"),
        ("[:", "a POSIX class"), ("(?", "an inline flag or a look-around (only (?: is safe)"),
        ("\\p", "a Unicode class"), ("\\P", "a Unicode class"), ("\\N", "a named character"),
        ("\\X", "a grapheme cluster"), ("\\R", "a line break"), ("\\h", "horizontal space"), ("\\v", "vertical space"),
        ("\\k", "a named back reference"), ("\\b{", "a boundary type"), ("\\G", "the end of the last match"),
        ("\\Z", "the end of input"), ("\\z", "the end of input"),
    ]

    static func problems(_ pattern: String) -> [String] {
        var found = unsafe.filter { $0.0 == "(?" ? pattern.replacingOccurrences(of: "(?:", with: "").contains("(?") : pattern.contains($0.0) }
            .map { "\($0.1) (\($0.0))" }
        if pattern.range(of: #"\\[1-9]"#, options: .regularExpression) != nil { found.append("a back reference") }
        return found
    }

    /// Every "re" in games/ (maps and packs).
    static func shippedPatterns() throws -> [(file: String, pattern: String)] {
        let games = try TestRepo.games()
        let files = FileManager.default.enumerator(at: games, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        var out: [(String, String)] = []
        func walk(_ x: Any, _ file: String) {
            if let o = x as? [String: Any] {
                for (k, v) in o {
                    if k == "re", let p = v as? String { out.append((file, p)) }
                    walk(v, file)
                }
            } else if let a = x as? [Any] {
                a.forEach { walk($0, file) }
            }
        }
        for f in files { walk(try JSONSerialization.jsonObject(with: Data(contentsOf: f)), f.lastPathComponent) }
        return out
    }

    @Test func everyMapPatternIsOneBothEnginesReadAlike() throws {
        let shipped = try Self.shippedPatterns()
        #expect(!shipped.isEmpty)
        for (file, pattern) in shipped {
            #expect(Self.problems(pattern).isEmpty, "\(file): \(pattern) uses \(Self.problems(pattern))")
            #expect(throws: Never.self, "\(file): \(pattern)") { try RegexBox(pattern) }
        }
    }

    @Test func theGuardCatchesWhatTheEnginesReadDifferently() {
        for p in ["[[:digit:]]", "[a-z&&[^e]]", "(?i)yes", "\\pL", "(a)\\1", "[a-z--[aeiou]]"] {
            #expect(!Self.problems(p).isEmpty, "\(p)")
        }
        #expect(Self.problems("\\b(sos|s o s)\\b").isEmpty)
        #expect(Self.problems("\\bguess\\b.*\\bwerewolf\\b").isEmpty)
        #expect(Self.problems("(?:a|b)+").isEmpty)
    }

    @Test func theShippedPatternsTakeWhatJavaTakes() throws {
        // From JDK 17's Pattern.compile(p).matcher(text).find(). U+0008 (a "\b" the JSON turned into a backspace) is
        // a plain character in both engines, so those patterns never match spoken text.
        let cases: [(String, String, Bool)] = [
            ("\\b(sos|s o s)\\b", "sos", true), ("\\b(sos|s o s)\\b", "it's s o s now", true),
            ("\\b(sos|s o s)\\b", "sosa", false), ("\u{8}(sos|s o s)\u{8}", "sos", false),
            ("\\b(cac|kak|cack|kack|cak|kac|caac|cacc|kaka?k)\\b", "kakak", true),
            ("\\b(cac|kak|cack|kack|cak|kac|caac|cacc|kaka?k)\\b", "cactus", false),
            ("\\bguess\\b.*\\bwerewolf\\b", "i guess the werewolf is bob", true),
            ("\\bguess\\b.*\\bwerewolf\\b", "werewolf guess", false),
        ]
        for (pattern, text, java) in cases {
            #expect(try RegexBox(pattern).containsMatch(in: text) == java, "\(pattern) on \(text)")
        }
    }

    @Test func negationQuotesThePhrase() {
        #expect(SpokenText.negated("i don't think yes", "yes"))
        #expect(SpokenText.negated("never ever say no", "no"))
        #expect(!SpokenText.negated("yes not really", "yes"))
        #expect(!SpokenText.negated("not a b c d yes", "yes"))
        #expect(SpokenText.negated("not a.b", "a.b"))
        #expect(!SpokenText.negated("not axb", "a.b"))
    }
}
