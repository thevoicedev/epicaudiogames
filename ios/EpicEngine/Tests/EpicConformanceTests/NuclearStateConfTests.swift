// nuclear/State.kt's JSON, against the states Kotlin saved in nuclear-war/games.jsonl and fanout.jsonl.

import EpicConformance
import EpicEngine
import Testing

@Suite struct NuclearStateConfTests {
    /// Every "state" and "settings" Kotlin saved in the Tier 1 games and the fanout's saves, in order, once each.
    static func saved() throws -> (states: [String], settings: [String]) {
        var states: [String] = []
        var settings: [String] = []
        var seen = Set<String>()
        func add(_ name: String, _ v: Value?) {
            guard case .string(let s)? = v, seen.insert(name + "\u{0}" + s).inserted else { return }
            if name == "state" { states.append(s) } else if name == "settings" { settings.append(s) }
        }
        for g in try NuclearFixtures.games.get() {
            for line in g.lines {
                for pair in try JSONParser.parse(line).fx("save").fx("delta").fxArray() {
                    let p = try pair.fxArray()
                    add(try p[0].fxString(), try p[1].fxValue())
                }
            }
        }
        for f in try NuclearFixtures.fanout.get().saves {
            add("state", f.saved.vars["state"])
            add("settings", f.saved.vars["settings"])
        }
        return (states, settings)
    }

    /// Each state reads back and is written again byte for byte (kotlinx's key order, numbers and escaping).
    @Test func statesRoundTrip() throws {
        let (states, _) = try NuclearStateConfTests.saved()
        #expect(states.count > 500)
        var diffs = Diffs()
        for (i, s) in states.enumerated() {
            do {
                let back = try NuclearState.fromJSON(JSONParser.parse(s).jsonObject()).toJSONString()
                if !same(back, s) { diffs.add("state \(i): \(difference(s, back))") }
            } catch {
                diffs.add("state \(i): \(error)\n    \(Kt.take(s, 300))")
            }
        }
        diffs.report("Kotlin's states read and written again (\(states.count))")
    }

    /// Each save's settings, taken by a new state and written again.
    @Test func settingsRoundTrip() throws {
        let (_, settings) = try NuclearStateConfTests.saved()
        #expect(settings.count >= 2)
        for s in settings {
            let st = NuclearState()
            try st.takeSettings(JSONParser.parse(s).jsonObject())
            #expect(same(JSONWriter.write(.object(st.settingsJSON())), s))
        }
    }

    // ----- Saves made by hand, against what Kotlin does with them -----
    //
    // The hashes below were made by the Kotlin engine (State.fromJson(...).toJson().toString(), and
    // NuclearWar(audio, Random(1)).open(saved)'s turn line as Canon.kt writes it, with games/nuclear-war/clips.json):
    // a missing value takes its default and a value of the wrong kind fails (State.kt:212-215); a game opened from a
    // state or settings that can't be read starts afresh, keeping the settings it can read (NuclearWar.kt open).
    // If State.kt or the opening of a game changes, make them again from Kotlin. Text only kotlinx reads ("round":007)
    // is left out: Swift's JSON parser keeps to RFC 8259 (fixtures/engine/README.md, section 12).

    /**
     * Each state edited by hand, read and written again: Kotlin's text (by its hash), or a failure where Kotlin
     * throws (NuclearWar's open then starts afresh).
     */
    @Test func craftedStates() throws {
        var diffs = Diffs()
        let edited = try NuclearStateConfTests.states.map { name, edits, want in
            (name, try NuclearStateConfTests.edited(edits), want)
        }
        let cases = edited + NuclearStateConfTests.texts
        for (name, text, want) in cases {
            let got = Result { try NuclearState.fromJSON(JSONParser.parse(text).jsonObject()).toJSONString() }
            switch (want, got) {
            case (nil, .failure): break
            case (nil, .success(let s)): diffs.add("\(name): kotlin fails, swift reads it: \(Kt.take(s, 300))")
            case (let h?, .failure(let e)): diffs.add("\(name): kotlin reads it (\(h)), swift fails: \(e)")
            case (let h?, .success(let s)):
                if !same(FNV.hex(FNV.hash(s)), h) {
                    diffs.add("\(name): kotlin's text hashes to \(h), swift's is \(s)")
                }
            }
        }
        diffs.report("states edited by hand (\(cases.count))")
    }

    /**
     * Each save made by hand opened in a new game on Random(1), as a Play: the opening turn line Kotlin wrote (by its
     * hash), or a failure where Kotlin throws. A state or settings that can't be read start a new game.
     */
    @Test func craftedOpens() throws {
        let audio = try NuclearFixtures.audio.get()
        let encoder = Canon.Encoder()
        var diffs = Diffs()
        for (name, crafted, want) in NuclearStateConfTests.opens {
            let rnd = LoggingRandom(XorWowRandom(seed: 1))
            let game: any Play = NuclearWar(audio: audio, random: rnd)
            let got = Result {
                let turn = try game.open(crafted?.saved())
                return Canon.Turns.nuclear(encoder).line(0, ["open"], .list(rnd.take().map(\.canon)), turn, game.save())
            }
            switch (want, got) {
            case (nil, .failure): break
            case (nil, .success(let line)): diffs.add("\(name): kotlin fails, swift opens it: \(Kt.take(line, 300))")
            case (let h?, .failure(let e)): diffs.add("\(name): kotlin opens it (\(h)), swift fails: \(e)")
            case (let h?, .success(let line)):
                if !same(FNV.hex(FNV.hash(line)), h) {
                    diffs.add("\(name): kotlin's line hashes to \(h), swift's is \(Kt.take(line, 1500))")
                }
            }
        }
        diffs.report("saves made by hand, opened (\(NuclearStateConfTests.opens.count))")
    }

    /// [base] with each edit made in turn (the first match replaced).
    static func edited(_ edits: [(String, String)]) throws -> String {
        var text = base
        for (old, new) in edits {
            guard let r = text.range(of: old) else { throw ConformanceError("no \(old) in the state") }
            text.replaceSubrange(r, with: new)
        }
        return text
    }

    /// The edit that changes [base]'s question.
    static func q(_ name: String) -> (String, String) { (#""q":"UPGRADE_PROMPT""#, "\"q\":\"\(name)\"") }

    /// The state Kotlin saved at seed 1, t 17 of games.jsonl (UPGRADE_PROMPT, with "us"), in pieces.
    static let base = [
        #"{"q":"UPGRADE_PROMPT","countries":[{"ref":"USA","balance":10000000,"motivator":"ENVIRONMENT","strike"#,
        #"sToUse":0,"contributions":0,"bombs":0,"bombedBy":[],"sanctionedBy":[],"countriesBombed":[],"tech":fa"#,
        #"lse,"cities":[{"name":"New York","shield":0,"research":0,"destroyed":false},{"name":"Houston","shiel"#,
        #"d":0,"research":0,"destroyed":false},{"name":"Los Angeles","shield":0,"research":0,"destroyed":false"#,
        #"}],"bombify":[],"score":0,"sanctioned":false,"wasSanctioned":false,"stillSanctioned":false,"destroye"#,
        #"d":false,"attackUs":0,"hasAttackedUs":false,"hasMet":true,"used":{},"done":[]},{"ref":"Russia","bala"#,
        #"nce":10000000,"motivator":"DEFENSE","strikesToUse":0,"contributions":0,"bombs":0,"bombedBy":[],"sanc"#,
        #"tionedBy":[],"countriesBombed":[],"tech":false,"cities":[{"name":"St Petersburg","shield":0,"researc"#,
        #"h":0,"destroyed":false},{"name":"Sochi","shield":0,"research":0,"destroyed":false},{"name":"Moscow","#,
        #""shield":0,"research":0,"destroyed":false}],"bombify":[],"score":0,"sanctioned":false,"wasSanctioned"#,
        #"":false,"stillSanctioned":false,"destroyed":false,"attackUs":0,"hasAttackedUs":false,"hasMet":false,"#,
        #""used":{},"done":[]},{"ref":"France","balance":10000000,"motivator":"NUCLEAR","strikesToUse":0,"cont"#,
        #"ributions":0,"bombs":0,"bombedBy":[],"sanctionedBy":[],"countriesBombed":[],"tech":false,"cities":[{"#,
        #""name":"Lyon","shield":0,"research":0,"destroyed":false},{"name":"Paris","shield":0,"research":0,"de"#,
        #"stroyed":false},{"name":"Marseille","shield":0,"research":0,"destroyed":false}],"bombify":[],"score""#,
        #":0,"sanctioned":false,"wasSanctioned":false,"stillSanctioned":false,"destroyed":false,"attackUs":0,""#,
        #"hasAttackedUs":false,"hasMet":false,"used":{},"done":[]},{"ref":"UK","balance":10000000,"motivator":"#,
        #""FRIENDLY","strikesToUse":0,"contributions":0,"bombs":0,"bombedBy":[],"sanctionedBy":[],"countriesBo"#,
        #"mbed":[],"tech":false,"cities":[{"name":"Edinburgh","shield":0,"research":0,"destroyed":false},{"nam"#,
        #"e":"Cardiff","shield":0,"research":0,"destroyed":false},{"name":"London","shield":0,"research":0,"de"#,
        #"stroyed":false}],"bombify":[],"score":0,"sanctioned":false,"wasSanctioned":false,"stillSanctioned":f"#,
        #"alse,"destroyed":false,"attackUs":0,"hasAttackedUs":false,"hasMet":false,"used":{},"done":[]}],"us":"#,
        #"{"ref":"China","balance":6000000,"motivator":"","strikesToUse":0,"contributions":1,"bombs":0,"bombed"#,
        #"By":[],"sanctionedBy":[],"countriesBombed":[],"tech":false,"cities":[{"name":"Wuhan","shield":1,"res"#,
        #"earch":0,"destroyed":false},{"name":"Shanghai","shield":0,"research":0,"destroyed":false},{"name":"B"#,
        #"eijing","shield":0,"research":0,"destroyed":false}],"bombify":[],"score":0,"sanctioned":false,"wasSa"#,
        #"nctioned":false,"stillSanctioned":false,"destroyed":false,"attackUs":0,"hasAttackedUs":false,"hasMet"#,
        #"":false,"used":{},"done":["shield-0"]},"environment":15,"prevEnvironment":0,"round":1,"citiesToBomb""#,
        #":[],"cityIndex":2,"countryIndex":1,"requestToBomb":[],"doneLongCall":false,"midGame":false,"countryT"#,
        #"oBomb":null,"cityBombIndex":0,"playedNuclear":true,"rundown":false,"completed":false}"#,
    ].joined()

    /// (name, edits to [base] (each replaces the first match), the hash of what Kotlin writes back, nil: it throws)
    static let states: [(String, [(String, String)], String?)] = [
        ("as saved", [], "b6a68638c4d35990"),
        ("no q", [(#""q":"UPGRADE_PROMPT","#, "")], nil),
        ("q unknown", [q("NOPE")], nil),
        ("q a number", [(#""q":"UPGRADE_PROMPT""#, #""q":5"#)], nil),
        ("q lower case", [q("upgrade_prompt")], nil),
        ("q null", [(#""q":"UPGRADE_PROMPT""#, #""q":null"#)], nil),
        ("countries an object", [(#""countries":[{"#, #""countries":{},"x":[{"#)], nil),
        ("countries null", [(#""countries":[{"#, #""countries":null,"x":[{"#)], nil),
        ("no countries", [(#""countries":[{"#, #""x":[{"#)], nil),
        ("us null", [(#""us":{"ref":"China","#, #""us":null,"x":{"ref":"China","#)], "03dd55ddfff43dbe"),
        ("us a string", [(#""us":{"ref":"China","#, #""us":"China","x":{"ref":"China","#)], "03dd55ddfff43dbe"),
        ("us an empty object", [(#""us":{"ref":"China","#, #""us":{},"x":{"ref":"China","#)], nil),
        ("no us", [(#""us":{"ref":"China","#, #""x":{"ref":"China","#)], "03dd55ddfff43dbe"),
        ("round a string", [(#""round":1,"#, #""round":"7","#)], "353b37f61a988156"),
        ("round padded string", [(#""round":1,"#, #""round":" 7","#)], "353b37f61a988156"),
        ("round plus", [(#""round":1,"#, #""round":"+7","#)], nil),
        ("round 7.0", [(#""round":1,"#, #""round":7.0,"#)], nil),
        ("round 7.5", [(#""round":1,"#, #""round":7.5,"#)], nil),
        ("round 1e2", [(#""round":1,"#, #""round":1e2,"#)], "fd544e54a1c50428"),
        ("round 1E2", [(#""round":1,"#, #""round":1E2,"#)], "fd544e54a1c50428"),
        ("round 1e-2", [(#""round":1,"#, #""round":1e-2,"#)], nil),
        ("round -0", [(#""round":1,"#, #""round":-0,"#)], "f81c584b597debdf"),
        ("round big", [(#""round":1,"#, #""round":2147483648,"#)], nil),
        ("round max", [(#""round":1,"#, #""round":2147483647,"#)], "143c363e5bf4503b"),
        ("round min", [(#""round":1,"#, #""round":-2147483648,"#)], "5c0b52fd52dacd79"),
        ("round null", [(#""round":1,"#, #""round":null,"#)], nil),
        ("round true", [(#""round":1,"#, #""round":true,"#)], nil),
        ("round a list", [(#""round":1,"#, #""round":[1],"#)], "f81c584b597debdf"),
        ("round an object", [(#""round":1,"#, #""round":{"a":1},"#)], "f81c584b597debdf"),
        ("round x", [(#""round":1,"#, #""round":"x","#)], nil),
        ("round empty", [(#""round":1,"#, #""round":"","#)], nil),
        ("round string 1e2", [(#""round":1,"#, #""round":"1e2","#)], "fd544e54a1c50428"),
        ("no round", [(#""round":1,"#, "")], "f81c584b597debdf"),
        ("midGame string true", [(#""midGame":false,"#, #""midGame":"true","#)], "d3c961cc5802729d"),
        ("midGame TRUE", [(#""midGame":false,"#, #""midGame":"TRUE","#)], "d3c961cc5802729d"),
        ("midGame True", [(#""midGame":false,"#, #""midGame":"True","#)], "d3c961cc5802729d"),
        ("midGame 1", [(#""midGame":false,"#, #""midGame":1,"#)], nil),
        ("midGame null", [(#""midGame":false,"#, #""midGame":null,"#)], nil),
        ("midGame an object", [(#""midGame":false,"#, #""midGame":{},"#)], "b6a68638c4d35990"),
        ("midGame yes", [(#""midGame":false,"#, #""midGame":"yes","#)], nil),
        ("no midGame", [(#""midGame":false,"#, "")], "b6a68638c4d35990"),
        ("countryToBomb a number", [(#""countryToBomb":null,"#, #""countryToBomb":5,"#)], "b6a68638c4d35990"),
        ("countryToBomb text", [(#""countryToBomb":null,"#, #""countryToBomb":"USA","#)], "0c37918c7a08fbc0"),
        ("countryToBomb an object", [(#""countryToBomb":null,"#, #""countryToBomb":{"a":1},"#)], "b6a68638c4d35990"),
        ("countryToBomb true", [(#""countryToBomb":null,"#, #""countryToBomb":true,"#)], "b6a68638c4d35990"),
        ("countryToBomb a string null", [(#""countryToBomb":null,"#, #""countryToBomb":"null","#)], "01393df2d377e4aa"),
        ("no countryToBomb", [(#""countryToBomb":null,"#, "")], "b6a68638c4d35990"),
        (
            "requestToBomb pairs",
            [(#""requestToBomb":[],"#, #""requestToBomb":[["USA","UK"],["France","China"]],"#)],
            "661be93693d51571"
        ),
        ("requestToBomb short", [(#""requestToBomb":[],"#, #""requestToBomb":[["USA"]],"#)], nil),
        (
            "requestToBomb long",
            [(#""requestToBomb":[],"#, #""requestToBomb":[["USA","UK","x"]],"#)],
            "bd2dc007ff26a143"
        ),
        ("requestToBomb numbers", [(#""requestToBomb":[],"#, #""requestToBomb":[[1,2.50]],"#)], "959b89d52d86c57c"),
        (
            "requestToBomb null inside",
            [(#""requestToBomb":[],"#, #""requestToBomb":[[null,"UK"]],"#)],
            "16d3433658b8d4ef"
        ),
        ("requestToBomb an object inside", [(#""requestToBomb":[],"#, #""requestToBomb":[[{},"UK"]],"#)], nil),
        ("requestToBomb not a list", [(#""requestToBomb":[],"#, #""requestToBomb":"x","#)], nil),
        ("requestToBomb inner not a list", [(#""requestToBomb":[],"#, #""requestToBomb":["x"],"#)], nil),
        ("requestToBomb an empty pair", [(#""requestToBomb":[],"#, #""requestToBomb":[[]],"#)], nil),
        ("no requestToBomb", [(#""requestToBomb":[],"#, "")], nil),
        (
            "citiesToBomb mixed",
            [(#""citiesToBomb":[],"#, #""citiesToBomb":[1,"a",null,true,2.50,-0.0,1E5],"#)],
            "3c55f03a5bed3f82"
        ),
        ("citiesToBomb an object inside", [(#""citiesToBomb":[],"#, #""citiesToBomb":[{}],"#)], nil),
        ("citiesToBomb not a list", [(#""citiesToBomb":[],"#, #""citiesToBomb":"Paris","#)], "b6a68638c4d35990"),
        (
            "citiesToBomb escapes",
            [(#""citiesToBomb":[],"#, #""citiesToBomb":["\u00e9\n\t\u0001\"\\\/\u007f\u2028\ud83d\ude00\b\f\r"],"#)],
            "f8091c2b02bb833c"
        ),
        (
            "citiesToBomb raw text",
            [(#""citiesToBomb":[],"#, "\"citiesToBomb\":[\"\u{e9}\u{1f600}\u{7f}\u{2028}\"],")],
            "c1738deef420202d"
        ),
        ("balance a string", [(#""balance":6000000,"#, #""balance":"123","#)], "fdcea11681e3b682"),
        ("balance 1.5", [(#""balance":6000000,"#, #""balance":1.5,"#)], nil),
        ("balance long max", [(#""balance":6000000,"#, #""balance":9223372036854775807,"#)], "caa1f87c7f2a18c2"),
        ("balance long min", [(#""balance":6000000,"#, #""balance":-9223372036854775808,"#)], "7b7dacf80b4b8cd8"),
        ("balance too big", [(#""balance":6000000,"#, #""balance":9223372036854775808,"#)], nil),
        ("balance negative", [(#""balance":6000000,"#, #""balance":-42,"#)], "09db648c980fd035"),
        ("balance null", [(#""balance":6000000,"#, #""balance":null,"#)], nil),
        ("balance 6e6", [(#""balance":6000000,"#, #""balance":6e6,"#)], "b6a68638c4d35990"),
        ("no balance", [(#""balance":6000000,"#, "")], nil),
        ("no ref", [(#""ref":"China","#, "")], nil),
        ("ref null", [(#""ref":"China","#, #""ref":null,"#)], "8e60017165be361e"),
        ("ref a number", [(#""ref":"China","#, #""ref":7,"#)], "fb01d4b8c2dc4692"),
        ("ref a list", [(#""ref":"China","#, #""ref":[],"#)], nil),
        ("motivator null", [(#""motivator":"""#, #""motivator":null"#)], "119de9c1759c160b"),
        ("motivator missing", [(#""motivator":"","#, "")], nil),
        (
            "city minimal",
            [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#, #"{"name":"Wuhan"}"#)],
            "39eed870ac7d1f7b"
        ),
        ("city no name", [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#, #"{"shield":1}"#)], nil),
        (
            "city name null",
            [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#, #"{"name":null}"#)],
            "e8af0b17ae349de7"
        ),
        (
            "city shield a string",
            [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#,
               #"{"name":"Wuhan","shield":"2","research":"x"}"#)],
            nil
        ),
        (
            "city destroyed TRUE",
            [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#,
               #"{"name":"Wuhan","destroyed":"TRUE"}"#)],
            "16f9cddc64b57bb0"
        ),
        ("city not an object", [(#"{"name":"Wuhan","shield":1,"research":0,"destroyed":false}"#, #""Wuhan""#)], nil),
        ("no cities", [(#""cities":[{"name":"Wuhan""#, #""x":[{"name":"Wuhan""#)], nil),
        ("cities an object", [(#""cities":[{"name":"Wuhan""#, #""cities":{},"x":[{"name":"Wuhan""#)], nil),
        (
            "used lists",
            [(#""used":{},"done":["shield-0"]"#, #""used":{"general":[0,2],"defense":[1]},"done":["shield-0"]"#)],
            "52b1bb9c4078835f"
        ),
        ("used a list", [(#""used":{},"done":["shield-0"]"#, #""used":[],"done":["shield-0"]"#)], nil),
        ("used null", [(#""used":{},"done":["shield-0"]"#, #""used":null,"done":["shield-0"]"#)], nil),
        (
            "used inner not a list",
            [(#""used":{},"done":["shield-0"]"#, #""used":{"general":"x"},"done":["shield-0"]"#)],
            nil
        ),
        (
            "used inner strings",
            [(#""used":{},"done":["shield-0"]"#, #""used":{"general":["1","x"]},"done":["shield-0"]"#)],
            nil
        ),
        (
            "used inner string numbers",
            [(#""used":{},"done":["shield-0"]"#, #""used":{"general":["1"," 2"]},"done":["shield-0"]"#)],
            "5e127143ccfe536f"
        ),
        (
            "used repeated kinds",
            [(#""used":{},"done":["shield-0"]"#,
               #""used":{"general":[0],"defense":[1],"general":[2]},"done":["shield-0"]"#)],
            "24446f74f7e3f93b"
        ),
        ("no used", [(#""used":{},"done":["shield-0"]"#, #""done":["shield-0"]"#)], "b6a68638c4d35990"),
        (
            "done repeated",
            [(#""done":["shield-0"]"#, #""done":["shield-0","research-1","shield-0"]"#)],
            "b5cb7ac975997f41"
        ),
        ("done mixed", [(#""done":["shield-0"]"#, #""done":[1,null,"x"]"#)], "f9b83b4ea1bc6054"),
        ("done not a list", [(#""done":["shield-0"]"#, #""done":"shield-0""#)], "6582122b989dd7ac"),
        ("no done", [(#""used":{},"done":["shield-0"]"#, #""used":{}"#)], "6582122b989dd7ac"),
        ("bombedBy repeated", [(#""bombedBy":[]"#, #""bombedBy":["USA","USA"]"#)], "83b7e51e6038bc62"),
        ("strikesToUse 0.0", [(#""strikesToUse":0"#, #""strikesToUse":0.0"#)], nil),
        ("duplicate round", [(#""round":1,"#, #""round":1,"round":4,"#)], "e047b2eab3985513"),
        ("duplicate q", [(#""q":"UPGRADE_PROMPT""#, #""q":"NOPE","q":"SANCTION""#)], "590ee8720169a32e"),
        ("extra key", [(#""round":1,"#, #""round":1,"zzz":[1,{"a":null}],"#)], "b6a68638c4d35990"),
        ("playedNuclear a string", [(#""playedNuclear":true"#, #""playedNuclear":"false""#)], "ba8e32593ec6c10b"),
        ("no rundown", [(#""rundown":false,"#, "")], "b6a68638c4d35990"),
        ("completed null", [(#""completed":false"#, #""completed":null"#)], nil),
        ("environment negative", [(#""environment":15"#, #""environment":-15"#)], "7e413d829bd7d96f"),
        ("whitespace", [(#""round":1,"#, " \"round\" : 1 ,\u{a}\u{9}")], "b6a68638c4d35990"),
    ]

    /// (name, text, the hash of what Kotlin writes back, nil: it throws)
    static let texts: [(String, String, String?)] = [
        ("not an object", "[1,2]", nil),
        ("minimal", #"{"q":"CHOOSE_COUNTRY","countries":[],"requestToBomb":[]}"#, "332036c02a3591ac"),
    ]

    /// (name, the save (nil: none), the hash of the opening turn line on Random(1), nil: it throws)
    static let opens: [(String, CraftedSave?, String?)] = [
        ("nothing saved", nil, "636aef4ffd6b7f5f"),
        (
            "settings only",
            CraftedSave("CHOOSE_COUNTRY", ended: false,
                        state: nil,
                        settings: .text(#"{"playedNuclear":true,"rundown":true,"completed":false}"#)),
            "ff58e04aadc42cb0"
        ),
        (
            "settings empty",
            CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .text("{}")),
            "636aef4ffd6b7f5f"
        ),
        (
            "settings TRUE strings",
            CraftedSave("CHOOSE_COUNTRY", ended: false,
                        state: nil,
                        settings: .text(#"{"playedNuclear":"TRUE","rundown":"false","completed":"True"}"#)),
            "03c8f6037b546784"
        ),
        (
            "settings a number inside",
            CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .text(#"{"playedNuclear":1}"#)),
            "636aef4ffd6b7f5f"
        ),
        (
            "settings null inside",
            CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .text(#"{"playedNuclear":null}"#)),
            "636aef4ffd6b7f5f"
        ),
        ("settings not JSON", CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .text("nope")), "636aef4ffd6b7f5f"),
        ("settings a list", CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .text("[]")), "636aef4ffd6b7f5f"),
        (
            "settings a number value",
            CraftedSave("CHOOSE_COUNTRY", ended: false, state: nil, settings: .number(7.0)),
            "636aef4ffd6b7f5f"
        ),
        (
            "state at the saved node",
            CraftedSave("UPGRADE_PROMPT", ended: false,
                        state: .base([]),
                        settings: .text(#"{"playedNuclear":true,"rundown":false,"completed":false}"#)),
            "e9381c20907e7e2b"
        ),
        (
            "state, no settings",
            CraftedSave("UPGRADE_PROMPT", ended: false, state: .base([]), settings: nil),
            "e9381c20907e7e2b"
        ),
        (
            "state, other settings",
            CraftedSave("UPGRADE_PROMPT", ended: false,
                        state: .base([]),
                        settings: .text(#"{"playedNuclear":false,"rundown":true,"completed":true}"#)),
            "e9381c20907e7e2b"
        ),
        (
            "state at GAME_OVER node",
            CraftedSave("GAME_OVER", ended: false,
                        state: .base([]),
                        settings: .text(#"{"playedNuclear":true,"rundown":true,"completed":true}"#)),
            "ca7d85d2fb8d6745"
        ),
        (
            "state ended",
            CraftedSave("UPGRADE_PROMPT", ended: true,
                        state: .base([]),
                        settings: .text(#"{"playedNuclear":true,"rundown":true,"completed":false}"#)),
            "ff58e04aadc42cb0"
        ),
        (
            "state, another node",
            CraftedSave("BOGUS", ended: false, state: .base([]), settings: nil),
            "e9381c20907e7e2b"
        ),
        (
            "state a number value",
            CraftedSave("UPGRADE_PROMPT", ended: false, state: .number(3.0), settings: nil),
            "636aef4ffd6b7f5f"
        ),
        ("state empty object", CraftedSave("UPGRADE_PROMPT", ended: false, state: .text("{}"), settings: nil), "636aef4ffd6b7f5f"),
        ("state not JSON", CraftedSave("UPGRADE_PROMPT", ended: false, state: .text("nope"), settings: nil), "636aef4ffd6b7f5f"),
        (
            "state q GAME_OVER",
            CraftedSave("CHOOSE_COUNTRY", ended: false, state: .base([q("GAME_OVER")]), settings: nil),
            "62fad146cabbdeaf"
        ),
        (
            "state no us, NUCLEAR_PROMPT",
            CraftedSave("NUCLEAR_PROMPT", ended: false,
                        state: .base([q("NUCLEAR_PROMPT"),
                                      (#""us":{"ref":"China","#, #""us":null,"x":{"ref":"China","#)]),
                        settings: nil),
            "8da0bda90d40ee55"
        ),
        (
            "state no us, BOMB_NUMBER_PROMPT",
            CraftedSave("BOMB_NUMBER_PROMPT", ended: false,
                        state: .base([q("BOMB_NUMBER_PROMPT"),
                                      (#""us":{"ref":"China","#, #""us":null,"x":{"ref":"China","#)]),
                        settings: nil),
            nil
        ),
        (
            "state no us, PHONE_COUNTRY",
            CraftedSave("PHONE_COUNTRY", ended: false,
                        state: .base([q("PHONE_COUNTRY"),
                                      (#""us":{"ref":"China","#, #""us":null,"x":{"ref":"China","#)]),
                        settings: nil),
            "f2dcd97e63ad929c"
        ),
        (
            "state PHONE_COUNTRY past the last country",
            CraftedSave("PHONE_COUNTRY", ended: false,
                        state: .base([q("PHONE_COUNTRY"), (#""countryIndex":1"#, #""countryIndex":9"#)]),
                        settings: nil),
            "4b49a06589cf4bcc"
        ),
        (
            "state CONFIRM_BOMB_PROMPT, no country",
            CraftedSave("CONFIRM_BOMB_PROMPT", ended: false, state: .base([q("CONFIRM_BOMB_PROMPT")]), settings: nil),
            "a2015b0fb9af6995"
        ),
        (
            "state CHOOSE_BOMB_CITY, unknown country",
            CraftedSave("CHOOSE_BOMB_CITY", ended: false,
                        state: .base([q("CHOOSE_BOMB_CITY"), (#""countryToBomb":null"#, #""countryToBomb":"Mars""#)]),
                        settings: nil),
            "58f1f91ad9320537"
        ),
        (
            "state COUNTRY_SELECT, index past the end",
            CraftedSave("COUNTRY_SELECT", ended: false,
                        state: .base([q("COUNTRY_SELECT"), (#""countryIndex":1"#, #""countryIndex":7"#)]),
                        settings: nil),
            nil
        ),
        (
            "state no countries, SANCTION_COUNTRY",
            CraftedSave("SANCTION_COUNTRY", ended: false,
                        state: .base([q("SANCTION_COUNTRY"), (#""countries":[{"#, #""countries":[],"x":[{"#)]),
                        settings: nil),
            "610175248e65997e"
        ),
        (
            "state BOMB_PROMPT",
            CraftedSave("BOMB_PROMPT", ended: false, state: .base([q("BOMB_PROMPT")]), settings: nil),
            "acc30d98b65049ea"
        ),
        (
            "state ENVIRONMENT_PROMPT",
            CraftedSave("ENVIRONMENT_PROMPT", ended: false, state: .base([q("ENVIRONMENT_PROMPT")]), settings: nil),
            "8c54ff125a3b6099"
        ),
        (
            "state CITY_PROMPT",
            CraftedSave("CITY_PROMPT", ended: false, state: .base([q("CITY_PROMPT")]), settings: nil),
            "c7854f5871d2ef79"
        ),
        (
            "state REMOVE_INDIVIDUAL_SANCTION",
            CraftedSave("REMOVE_INDIVIDUAL_SANCTION", ended: false,
                        state: .base([q("REMOVE_INDIVIDUAL_SANCTION")]),
                        settings: nil),
            "d640f5a2fa21452a"
        ),
        (
            "state BOMB_INDIVIDUAL",
            CraftedSave("BOMB_INDIVIDUAL", ended: false, state: .base([q("BOMB_INDIVIDUAL")]), settings: nil),
            "a2015b0fb9af6995"
        ),
        (
            "state SANCTION_SPECIFIC",
            CraftedSave("SANCTION_SPECIFIC", ended: false, state: .base([q("SANCTION_SPECIFIC")]), settings: nil),
            "5cb4810108b871c7"
        ),
    ]
}

/// A save made by hand: its node, whether it ended, and its "state" and "settings" (nil: not there).
struct CraftedSave: Sendable {
    enum Var: Sendable {
        /// NuclearStateConfTests.base, edited.
        case base([(String, String)])
        case text(String)
        /// Not text, so not a state or settings at all.
        case number(Double)
    }

    let node: String
    let ended: Bool
    let state: Var?
    let settings: Var?

    init(_ node: String, ended: Bool, state: Var?, settings: Var?) {
        self.node = node
        self.ended = ended
        self.state = state
        self.settings = settings
    }

    func saved() throws -> Saved {
        var vars = VarStore()
        for (name, v) in [("state", state), ("settings", settings)] {
            switch v {
            case nil: break
            case .base(let edits)?: vars[name] = .string(try NuclearStateConfTests.edited(edits))
            case .text(let s)?: vars[name] = .string(s)
            case .number(let d)?: vars[name] = .number(d)
            }
        }
        return Saved(node: node, vars: vars, ended: ended)
    }
}
