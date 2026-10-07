// Shared by the Kotlin test ports: the games folder (Kotlin's games.dir), the slow tag, and the JUnit and kotlin.text
// helpers the Kotlin tests lean on.

import Foundation
import Testing

@testable import EpicEngine

extension Tag {
    /// Long runs: MapsTests' full counts, with EPIC_SLOW=1.
    @Tag static var slow: Self
}

/// The repo the tests read games/ from.
enum TestRepo {
    /// The repo (with games/catalog.json): EPIC_REPO_ROOT, or up from this file.
    static let root: URL? = {
        if let env = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("games/catalog.json").path) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }()

    /// Full counts for the long tests (EPIC_SLOW=1); otherwise fewer, for the quick loop.
    static var slow: Bool { ProcessInfo.processInfo.environment["EPIC_SLOW"] == "1" }

    /// games/ (the Kotlin tests' games.dir).
    static func games(sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        try #require(root, "no games/catalog.json above this file: set EPIC_REPO_ROOT", sourceLocation: sourceLocation)
            .appendingPathComponent("games")
    }

    /// A game's free map, games/<id>/map.json.
    static func load(_ id: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> GameMap {
        try GameMap.load(games(sourceLocation: sourceLocation).appendingPathComponent("\(id)/map.json"))
    }
}

/// JUnit's `@Test(expected = MapException::class)`: the body fails with a MapError of kind map (a MapException in
/// Kotlin, not some other exception).
func expectMapException(
    _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Void
) {
    let e = #expect(throws: MapError.self, comment, sourceLocation: sourceLocation) { try body() }
    if let e { #expect(e.kind == .map, "not a MapException: \(e)", sourceLocation: sourceLocation) }
}

extension Array {
    /// Kotlin's single(): the one element (a failure when there are none or more).
    func single(sourceLocation: SourceLocation = #_sourceLocation) throws -> Element {
        try #require(count == 1, "expected one element: \(self)", sourceLocation: sourceLocation)
        return self[0]
    }
}

extension String {
    /// Kotlin's removeSuffix.
    func removingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }

    /// Kotlin's substringBefore: the text before the first [delimiter], or all of it.
    func substringBefore(_ delimiter: String) -> String {
        guard let r = range(of: delimiter) else { return self }
        return String(self[..<r.lowerBound])
    }
}

/// Kotlin's Regex(pattern).find(text)?.groupValues: the whole match, then each group ("" for one that didn't take
/// part), or nil when nothing matches.
func regexFind(_ pattern: String, _ text: String) throws -> [String]? {
    let re = try NSRegularExpression(pattern: pattern)
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
}

/// Kotlin's Regex(pattern).containsMatchIn(text).
func regexContainsMatch(_ pattern: String, _ text: String) throws -> Bool { try regexFind(pattern, text) != nil }
