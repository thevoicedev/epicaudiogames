// GoldenTest.kt's check mode, the shared parts: the fixtures, the variants, the calls and how differences are told.

import EpicConformance
import EpicEngine
import Foundation
import Testing

/// The repo's goldens (fails, with why, when the repo or the fixtures can't be read).
func goldens() throws -> Goldens { try Goldens.shared.get() }

/// EPIC_SLOW=1: the full Tier 2 counts (500 walks a variant) instead of a quick sample.
let slow = ProcessInfo.processInfo.environment["EPIC_SLOW"] == "1"

/// The variants, in the fixtures' order (README section 1); VariantsTests checks the games folder gives the same.
enum Variants {
    static let all = [
        "alien-customs", "alien-customs+packs", "frootopia", "frootopia+packs", "leaning-tower-of-pizza", "noodle-rush",
        "pirate-quest", "signal-decoders", "the-werewolf", "the-werewolf+packs",
    ]
}

/// The same text, UTF-8 byte for byte (Swift's == would let canonically equal but different strings pass).
func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

func same(_ a: String?, _ b: String?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): same(x, y)
    default: false
    }
}

/// The same double, as the fixtures compare them: bit for bit, every NaN the same.
func same(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): Canon.json(.double(x)) == Canon.json(.double(y))
    default: false
    }
}

/// Where two lines first differ, with some text either side.
func difference(_ want: String, _ got: String) -> String {
    let a = Array(want.utf16)
    let b = Array(got.utf16)
    var i = 0
    while i < a.count && i < b.count && a[i] == b[i] { i += 1 }
    func around(_ u: [UInt16]) -> String {
        String(decoding: u[max(0, i - 120)..<min(u.count, i + 120)], as: UTF16.self)
    }
    return "column \(i + 1)\n    kotlin: …\(around(a))…\n    swift:  …\(around(b))…"
}

/**
 * Mismatches found in one test, reported together as one issue (the first few in full, then how many), so a
 * divergence shows where it starts without thousands of failures after it.
 */
struct Diffs {
    private var shown: [String] = []
    private(set) var count = 0
    let limit: Int

    init(limit: Int = 12) { self.limit = limit }

    mutating func add(_ message: @autoclosure () -> String) {
        count += 1
        if shown.count < limit { shown.append(message()) }
    }

    /// Records the mismatches, if any, as one issue.
    func report(_ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard count > 0 else { return }
        let more = count > shown.count ? "\n… and \(count - shown.count) more" : ""
        Issue.record(Comment(rawValue: "\(what): \(count) differ\n" + shown.joined(separator: "\n") + more),
                     sourceLocation: sourceLocation)
    }
}

/// A fixture input (README section 7.1) made on a map game. [last] is the turn before (for "return").
func call(
    _ input: JSON, _ s: inout Session, last: Turn?, newSession: () -> Session
) throws -> Turn {
    let a = try input.fxArray()
    switch try a[0].fxString() {
    case "start": return try s.start()
    case "answer": return try s.answer(a[1].fxString())
    case "silence": return try s.silence()
    case "next": return try s.nextChapter()
    case "restart": return try s.restart(at: a[1].fxOptString())
    case "resume": return try s.resume(Saved(node: a[1].fxString(), vars: VarStore(), ended: true))
    case "reopen":
        let saved = s.save()
        s = newSession()
        return try s.open(saved)
    case "return":
        guard last != nil else { throw ConformanceError("return before any turn") }
        let saved = s.save()     // the app stores the save after a quit too (GameController.kt finishTurn)
        s = newSession()
        return try s.open(saved)
    default: throw ConformanceError("no such call \(input.kotlinxDescription)")
    }
}
