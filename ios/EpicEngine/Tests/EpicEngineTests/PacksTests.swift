// PacksTest.kt: a pack merged into its game: new nodes and variables, and the nodes it replaces.

import Foundation
import Testing

@testable import EpicEngine

/// A pack merged into its game: new nodes and variables, and the nodes it replaces (docs/MAP_FORMAT.md, Packs).
struct PacksTests {
    private let base = """
        {"format": 1, "id": "demo", "title": "Demo", "start": "a", "vars": {"level": 0}, "keep": ["level"],
         "who": {"HOST": ""},
         "nodes": {
           "a": {"say": [], "ask": {"reprompt": [], "answers": [{"yes": true, "go": "won1"}]}},
           "won1": {"set": {"level": "+1"}, "say": [],
                    "end": {"kind": "chapter", "title": "Level 1", "next": "level2", "locked": "demo-levels"}}
         }}
        """

    private let pack = """
        {"format": 1, "game": "demo", "id": "demo-levels", "vars": {"stars": 0}, "keep": ["stars"],
         "who": {"GUIDE": "Guide"},
         "nodes": {
           "won1": {"set": {"level": "+1"}, "say": [], "end": {"kind": "chapter", "title": "Level 1", "next": "level2"}},
           "level2": {"set": {"stars": "+1"}, "say": [], "end": {"kind": "ending", "title": "All done"}}
         }}
        """

    @Test func withoutThePackTheNextLevelIsLocked() throws {
        let map = try GameMap.parse(base)
        let s = Session(map)
        _ = try s.start()
        let won = try s.answer("yes")
        #expect(won.end?.locked == "demo-levels")
        #expect(!map.nodes.contains("level2"))
    }

    @Test func thePackAddsAndReplacesNodes() throws {
        let map = try GameMap.parse(base, packs: [pack])
        #expect(Set(map.keep) == ["level", "stars"])
        #expect(map.who["GUIDE"] == "Guide")
        let s = Session(map)
        _ = try s.start()
        let won = try s.answer("yes")
        #expect(won.end?.locked == nil, "the pack's own end isn't locked")
        let next = try s.nextChapter()
        #expect(next.node == "level2")
        #expect(s.vars["stars"] == 1.0)
        #expect(s.vars["level"] == 1.0)
    }

    @Test func aPackForAnotherGameIsRefused() {
        let other = pack.replacingOccurrences(of: "\"game\": \"demo\"", with: "\"game\": \"other\"")
        expectMapException { _ = try GameMap.parse(base, packs: [other]) }
    }
}
