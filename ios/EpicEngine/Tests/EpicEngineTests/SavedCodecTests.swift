// Tests for SavedCodec: a game's place in the JSON the Android app keeps (Library.kt's Saves).

import Testing

@testable import EpicEngine

struct SavedCodecTests {
    @Test func writesAsOrgJSONDoes() throws {
        let saved = Saved(
            node: "q/3",
            vars: ["n": 2, "half": 0.5, "mode": "x \"y\"", "won": true, "neg": .number(-0.0), "big": 1e20, "tiny": 2.5e-7],
            ended: false
        )
        let text = try SavedCodec.encode(saved)
        #expect(text == #"{"node":"q\/3","vars":{"n":2,"half":0.5,"mode":"x \"y\"","won":true,"neg":-0,"big":1.0E20,"tiny":2.5E-7},"ended":false}"#)
    }

    @Test func readsBackWhatItWrites() throws {
        let saved = Saved(
            node: "Page2", vars: ["nana": false, "tries": 3, "deck_d": "q1,q3", "best": 12.25, "line": "a\nb\u{2028}é😀"],
            ended: true
        )
        let back = try #require(SavedCodec.decode(SavedCodec.encode(saved)))
        #expect(back == saved)
        #expect(back.vars.keys == saved.vars.keys)
        #expect(SavedCodec.decode(try SavedCodec.encodeData(saved)) == saved)
    }

    @Test func readsTheAndroidAppsSaves() throws {
        // As org.json writes them on Android: integers without ".0", "/" escaped.
        let android = #"{"node":"ai-p1","vars":{"tries":1,"episode1Choice":"hide","path":"a\/b","score":-2.5,"unlocked":true},"ended":false}"#
        let saved = try #require(SavedCodec.decode(android))
        #expect(saved.node == "ai-p1")
        #expect(saved.vars.keys == ["tries", "episode1Choice", "path", "score", "unlocked"])
        #expect(saved.vars["tries"] == .number(1))
        #expect(saved.vars["path"] == "a/b")
        #expect(saved.vars["score"] == -2.5)
        #expect(saved.vars["unlocked"] == true)
        #expect(saved.ended == false)
    }

    @Test func readsNumbersAsJSONTokenerDoes() throws {
        // Without a ".", a number is read as an Integer or Long: "-0" comes back as 0.0.
        let saved = try #require(SavedCodec.decode(#"{"node":"a","vars":{"z":-0,"w":-0.0,"e":1e3,"l":9007199254740993,"f":1.5E-7},"ended":false}"#))
        #expect(saved.vars["z"] == .number(0))
        #expect(saved.vars["w"] == .number(-0.0))
        #expect(saved.vars["e"] == 1000)
        #expect(saved.vars["l"] == .number(9007199254740992))
        #expect(saved.vars["f"] == 1.5e-7)
    }

    @Test func readsEndedAsOptBooleanDoes() {
        func ended(_ value: String) -> Bool? { SavedCodec.decode(#"{"node":"a","vars":{}"# + value + "}")?.ended }
        #expect(ended("") == false)
        #expect(ended(#","ended":true"#) == true)
        #expect(ended(#","ended":"TRUE""#) == true)
        #expect(ended(#","ended":"false""#) == false)
        #expect(ended(#","ended":1"#) == false)
        #expect(ended(#","ended":null"#) == false)
    }

    @Test func readsTheNodeAsGetStringDoes() {
        func node(_ value: String) -> String? { SavedCodec.decode(#"{"node":"# + value + #","vars":{}}"#)?.node }
        #expect(node("\"x\"") == "x")
        #expect(node("5") == "5")
        #expect(node("5.0") == "5.0")
        #expect(node("true") == "true")
        #expect(node("null") == "null")
    }

    @Test func aBrokenSaveIsNil() {
        for bad in [
            "", "not json", "[]", "{}", #"{"node":"a"}"#, #"{"vars":{}}"#, #"{"node":"a","vars":5}"#,
            #"{"node":"a","vars":{"x":null}}"#, #"{"node":"a","vars":{"x":[1]}}"#, #"{"node":"a","vars":{"x":{}}}"#,
            #"{"node":"a","vars":{},"ended":false"#,
        ] {
            #expect(SavedCodec.decode(bad) == nil, "\(bad)")
        }
    }

    @Test func refusesNumbersJSONCantHold() {
        // org.json refuses NaN and infinities; Android ends up with no save, and so does the caller here.
        for d in [Double.nan, .infinity, -.infinity] {
            #expect(throws: SavedCodec.EncodeError.self) {
                try SavedCodec.encode(Saved(node: "a", vars: ["x": .number(d)], ended: false))
            }
        }
    }

    @Test func aSessionPicksUpFromItsSave() throws {
        let map = try GameMap.parse("""
            {"format":1,"id":"t","title":"T","start":"a","vars":{"n":0,"deck_d":""},"who":{"H":""},
             "nodes":{
              "a":{"set":{"n":"+1"},"say":[{"play":"a","dur":1,"lines":[{"at":0,"len":1,"who":"H","text":"A"}]}],
                   "ask":{"answers":[{"any":true,"go":"b"}]}},
              "b":{"say":[{"play":"b","dur":1,"lines":[]}],"ask":{"reprompt":[{"play":"r","dur":1}],"answers":[{"any":true,"go":"a"}]}}}}
            """)
        let s = Session(map) { _ in 0 }
        _ = try s.start()
        _ = try s.answer("go")
        let text = try SavedCodec.encode(s.save())
        #expect(text == #"{"node":"b","vars":{"n":1,"deck_d":""},"ended":false}"#)
        let saved = try #require(SavedCodec.decode(text))
        let back = Session(map) { _ in 0 }
        let turn = try back.open(saved)
        #expect(turn.node == "b")
        #expect(back.vars == s.vars)
        guard case .play(let clip) = turn.steps.first else {
            Issue.record("expected the node's say again")
            return
        }
        #expect(clip.path == "b")
    }
}
