// StepsTest.kt: expressions (ExprTest), and the steps that vary, beds, computed values and decks (StepsTest).

import Testing

@testable import EpicEngine

struct ExprTests {
    private func eval(_ src: String, _ vars: VarStore = [:]) throws -> Value? { try Expr.parse(src).eval(vars) }

    @Test func arithmetic() throws {
        #expect(try eval("2 + 3 * 4") == 14.0)
        #expect(try eval("(2 + 3) * 4") == 20.0)
        #expect(try eval("7 % 4") == 3.0)
        #expect(try eval("-5 + 2") == -3.0)
        #expect(try eval("streak * 10", ["streak": 7.0]) == 70.0)
        #expect(try eval("max(best, streak)", ["best": 9.0, "streak": 4.0]) == 9.0)
        #expect(try eval("floor(streak / 3)", ["streak": 8.0]) == 2.0)
        #expect(try eval("missing + 1") == 1.0)
    }

    @Test func logic() throws {
        let trick = try Expr.parse("streak >= 3 && (streak - 3) % 4 == 0")
        #expect(trick.test(["streak": 7.0]))
        #expect(!trick.test(["streak": 5.0]))
        #expect(!trick.test(["streak": 0.0]))
        #expect(try eval("a > b ? a : b", ["a": 8.0, "b": 3.0]) == 8.0)
        #expect(try Expr.parse("choice == \"hide\"").test(["choice": "hide"]))
        #expect(try Expr.parse("!missing").test([:]))
        #expect(try Expr.parse("mode == \"challenge\" || nose >= 50").test(["mode": "battle", "nose": 50.0]))
        #expect(try Expr.parse("streak > best && streak >= 2").names == ["streak", "best"])
    }

    @Test func rejectsNonsense() {
        for bad in ["a >> 2", "(a", "max(", "a +", "foo(1)", "a = 2"] {
            expectMapException("accepted \"\(bad)\"") { _ = try Expr.parse(bad) }
        }
    }
}

/// The steps that vary (when, pick, by), beds, computed values and decks, on a small map.
struct StepsTests {
    private static func clip(_ path: String) -> String {
        #"{ "play": "\#(path)", "dur": 1.0, "lines": [{ "at": 0, "len": 1, "who": "H", "text": "\#(path)" }] }"#
    }

    private let map: GameMap

    init() throws {
        map = try GameMap.parse(
            """
            {
              "format": 1, "id": "t", "title": "T", "start": "a",
              "vars": { "n": 0, "best": 0, "mode": "x", "deck_d": "" },
              "keep": ["best", "deck_d"],
              "who": { "H": "" },
              "nodes": {
                "a": {
                  "set": { "n": "+1", "best": "=n > best ? n : best" },
                  "say": [
                    { "bed": "music", "volume": 0.25, "dur": 9 },
                    \(Self.clip("always")),
                    { "when": "n == 1", "play": "first", "dur": 1, "lines": [] , "sfx": true },
                    { "when": "n != 1", "play": "later", "dur": 1, "lines": [], "sfx": true },
                    { "pick": [[\(Self.clip("p0"))], [\(Self.clip("p1"))]] },
                    { "by": "mode", "cases": { "x": [\(Self.clip("modeX"))] }, "else": [\(Self.clip("other"))] },
                    { "bed": null }
                  ],
                  "go": { "draw": ["q1", "q2", "q3"], "deck": "d" }
                },
                "q1": { "say": [\(Self.clip("q1"))], "ask": { "answers": [{ "any": true, "go": "a" }] } },
                "q2": { "say": [\(Self.clip("q2"))], "ask": { "answers": [{ "any": true, "go": "a" }] } },
                "q3": { "say": [\(Self.clip("q3"))], "ask": { "answers": [{ "any": true, "go": "a" }] } }
              }
            }
            """
        )
    }

    private func paths(_ t: Turn) -> [String] {
        t.steps.map {
            switch $0 {
            case .play(let p): p.path
            case .bed(let path, _, _): "bed:\(path ?? "null")"
            default: String(describing: $0)
            }
        }
    }

    @Test func resolvesStepsAsTheTurnPlays() throws {
        let s = Session(map) { _ in 1 }
        let first = try s.start()
        #expect(Array(paths(first).prefix(6)) == ["bed:music", "always", "first", "p1", "modeX", "bed:null"])
        #expect(s.vars["n"] == 1.0)
        #expect(s.vars["best"] == 1.0)
        let again = try s.answer("anything")
        #expect(paths(again).contains("later"))
        #expect(s.vars["best"] == 2.0)
    }

    @Test func decksDrawEachNodeOnceThenStartAgain() throws {
        let s = Session(map) { _ in 0 }
        var drawn = [try s.start().node]
        for _ in 0..<2 { drawn.append(try s.answer("go").node) }
        #expect(Set(drawn) == ["q1", "q2", "q3"])
        drawn.append(try s.answer("go").node)          // all three drawn: the deck starts again
        #expect(["q1", "q2", "q3"].contains(drawn.last!))
        let deck = try #require(s.vars["deck_d"]?.stringValue)
        #expect(deck.split(separator: ",", omittingEmptySubsequences: false).count == 1)
    }

    @Test func keepsDecksAndBestAcrossRestarts() throws {
        let s = Session(map) { _ in 0 }
        _ = try s.start()
        _ = try s.answer("go")
        let deck = try #require(s.vars["deck_d"]?.stringValue)
        _ = try s.restart()
        #expect(s.vars["n"] == 1.0)                       // a fresh play
        #expect(s.vars["best"] == 2.0)                    // kept from the first play (2), not beaten by 1
        #expect(try #require(s.vars["deck_d"]?.stringValue).hasPrefix(deck))
    }
}
