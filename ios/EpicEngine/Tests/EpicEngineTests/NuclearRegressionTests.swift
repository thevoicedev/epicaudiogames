// Regression tests for Kotlin-vs-Swift differences in Nuclear War found in review (nuclear/NuclearWar.kt, State.kt):
// each save below was made by hand and played on the Kotlin engine (with games/nuclear-war/clips.json, its turns
// written by golden/Canon.kt), and the expected values are its. If NuclearWar.kt changes, make them again from Kotlin.

import EpicConformance
import Foundation
import Testing

@testable import EpicEngine

/**
 * A save made by hand: [NuclearRegressionTests.base] with [edits] (a path such as "us.balance" or
 * "countries.0.bombs", and the JSON put there), opened in a new game on Random([seed]) and answered with [answers].
 * Then what Kotlin did: its turn lines (Canon.kt, fixtures/engine/README.md section 7) by their hashes, the opening
 * first; whether it threw on the turn after those; its end; the question its last save opens at in a new game; a line
 * it said; and text its last save holds.
 */
struct Crafted: Sendable, CustomTestStringConvertible {
    let name: String
    let seed: Int32
    let answers: [String]
    let edits: [(String, String)]
    let kotlin: [String]
    let fails: Bool
    let end: String?
    let reopens: String?
    let says: String?
    let holds: String?

    init(
        _ name: String, seed: Int32, answers: [String], edits: [(String, String)], kotlin: [String],
        fails: Bool = false, end: String? = nil, reopens: String? = nil, says: String? = nil, holds: String? = nil
    ) {
        self.name = name
        self.seed = seed
        self.answers = answers
        self.edits = edits
        self.kotlin = kotlin
        self.fails = fails
        self.end = end
        self.reopens = reopens
        self.says = says
        self.holds = holds
    }

    var testDescription: String { name }
}

@Suite struct NuclearRegressionTests {
    /// A balance is a Kotlin Long: buying, earning and losing wrap at its ends, and nothing traps.
    @Test(arguments: balances) func balancesWrapAsKotlinLongsDo(_ c: Crafted) throws { try play(c) }

    /// Counts (the environment, the round, scores, bombs and the rest) are Kotlin Ints: they wrap at 32 bits, and the
    /// save they're written to can be read again.
    @Test(arguments: counts) func countsWrapAsKotlinIntsDo(_ c: Crafted) throws { try play(c) }

    /// Names, refs and flags from a save are the same only when their UTF-16 units are (Kotlin's String.equals):
    /// "é" and "e" + U+0301, U+212A KELVIN SIGN and "K", are different text.
    @Test(arguments: texts) func textIsComparedAsKotlinComparesIt(_ c: Crafted) throws { try play(c) }

    /// Plays [c] and checks each turn against Kotlin's.
    private func play(_ c: Crafted) throws {
        let audio = try NuclearRegressionTests.audio.get()
        var state = try JSONParser.parse(NuclearRegressionTests.base)
        for (path, value) in c.edits {
            let keys = path.split(separator: ".").map(String.init)
            try NuclearRegressionTests.put(&state, keys[...], JSONParser.parse(value))
        }
        guard case .object(let o) = state, case .string(let q)? = o["q"] else { throw PlayError("no q") }
        let saved = Saved(node: q, vars: [
            "state": .string(JSONWriter.write(state)), "settings": .string(NuclearRegressionTests.settings),
        ], ended: false)
        let rnd = LoggingRandom(XorWowRandom(seed: c.seed))
        let game = NuclearWar(audio: audio, random: rnd)
        let turns = Canon.Turns.nuclear(Canon.Encoder())
        var said: [String] = []
        var end: End?
        for t in 0...c.answers.count {
            let input: CanonValue = t == 0 ? ["open"] : ["answer", .string(c.answers[t - 1])]
            let turn: Turn
            do {
                turn = t == 0 ? try game.open(saved) : try game.answer(c.answers[t - 1])
            } catch {
                #expect(c.fails && t == c.kotlin.count, "turn \(t) fails, as Kotlin's doesn't: \(error)")
                return
            }
            let line = turns.line(t, input, .list(rnd.take().map(\.canon)), turn, game.save())
            let texts = turn.steps.flatMap { step -> [String] in
                if case .play(let clip) = step { clip.lines.map(\.text) } else { [] }
            }
            guard t < c.kotlin.count else {
                Issue.record("Kotlin fails on turn \(t); Swift plays it: \(texts)")
                return
            }
            let hash = FNV.hex(FNV.hash(line))
            #expect(hash == c.kotlin[t], "turn \(t) isn't Kotlin's: Swift said \(texts)\n\(Kt.take(line, 3000))")
            said += texts
            end = turn.end ?? end
        }
        #expect(end?.title == c.end)
        if let says = c.says { #expect(said.contains { Kt.utf16Equal($0, says) }, "Kotlin says \"\(says)\"") }
        let after = game.save()
        guard case .string(let last)? = after.vars["state"] else { throw PlayError("no state saved") }
        if let holds = c.holds { #expect(Kt.contains(last, holds), "Kotlin's save holds \(holds): \(last)") }
        // The save opens again, at the question Kotlin's does.
        if let reopens = c.reopens {
            let again = NuclearWar(audio: audio, random: XorWowRandom(seed: c.seed &+ 1))
            let opened = Result { try again.open(after) }
            #expect((try? opened.get())?.node == reopens, "Kotlin's save opens at \(reopens): \(opened)")
        }
    }

    /// games/nuclear-war/clips.json, which Kotlin's turns were made with.
    static let audio = Result { () throws -> NuclearAudio in
        guard let root = TestRepo.root else { throw PlayError("no games/catalog.json above this file") }
        return try NuclearAudio.load(root.appendingPathComponent("games/nuclear-war/clips.json"))
    }

    /// [json] with the value at [path] (keys and list indexes) set to [value].
    static func put(_ json: inout JSON, _ path: ArraySlice<String>, _ value: JSON) throws {
        guard let key = path.first else {
            json = value
            return
        }
        switch json {
        case .object(var o):
            guard var child = o[key] else { throw PlayError("no \(key) in the state") }
            try put(&child, path.dropFirst(), value)
            o[key] = child
            json = .object(o)
        case .array(var list):
            guard let i = Int(key), list.indices.contains(i) else { throw PlayError("no item \(key) in the state") }
            try put(&list[i], path.dropFirst(), value)
            json = .array(list)
        default:
            throw PlayError("\(key): the state has no list or object there")
        }
    }

    /// The save's settings.
    static let settings = #"{"playedNuclear":true,"rundown":true,"completed":false}"#

    /// Fanout.jsonl save 50 as Kotlin saved it (USE_BOMBS in round 4; you are France), in pieces.
    static let base = [
        #"{"q":"USE_BOMBS","countries":[{"ref":"Russia","balance":26400000,"motivator":"ENVIRONMENT","strikesToUse"#,
        #"":0,"contributions":3,"bombs":0,"bombedBy":["UK","UK","UK"],"sanctionedBy":[],"countriesBombed":[],"tech"#,
        #"":false,"cities":[{"name":"Moscow","shield":1,"research":0,"destroyed":false},{"name":"St Petersburg","s"#,
        #"hield":1,"research":1,"destroyed":false},{"name":"Sochi","shield":0,"research":1,"destroyed":false}],"bo"#,
        #"mbify":[],"score":73,"sanctioned":true,"wasSanctioned":false,"stillSanctioned":true,"destroyed":false,"a"#,
        #"ttackUs":0,"hasAttackedUs":false,"hasMet":true,"used":{},"done":[]},{"ref":"China","balance":26200000,"m"#,
        #"otivator":"DEFENSE","strikesToUse":0,"contributions":3,"bombs":0,"bombedBy":[],"sanctionedBy":[],"countr"#,
        #"iesBombed":[],"tech":true,"cities":[{"name":"Shanghai","shield":1,"research":1,"destroyed":false},{"name"#,
        #"":"Beijing","shield":1,"research":1,"destroyed":false},{"name":"Wuhan","shield":1,"research":1,"destroye"#,
        #"d":false}],"bombify":[],"score":74,"sanctioned":true,"wasSanctioned":false,"stillSanctioned":true,"destr"#,
        #"oyed":false,"attackUs":2,"hasAttackedUs":false,"hasMet":true,"used":{},"done":[]},{"ref":"USA","balance""#,
        #":24000000,"motivator":"FRIENDLY","strikesToUse":0,"contributions":3,"bombs":0,"bombedBy":["UK"],"sanctio"#,
        #"nedBy":[],"countriesBombed":[],"tech":true,"cities":[{"name":"Los Angeles","shield":1,"research":1,"dest"#,
        #"royed":false},{"name":"Houston","shield":1,"research":1,"destroyed":false},{"name":"New York","shield":1"#,
        #","research":1,"destroyed":false}],"bombify":[],"score":78,"sanctioned":false,"wasSanctioned":true,"still"#,
        #"Sanctioned":false,"destroyed":false,"attackUs":2,"hasAttackedUs":false,"hasMet":false,"used":{},"done":["#,
        #"]},{"ref":"UK","balance":14800000,"motivator":"NUCLEAR","strikesToUse":1,"contributions":1,"bombs":1,"bo"#,
        #"mbedBy":[],"sanctionedBy":[],"countriesBombed":[],"tech":true,"cities":[{"name":"Cardiff","shield":1,"re"#,
        #"search":0,"destroyed":false},{"name":"Edinburgh","shield":0,"research":1,"destroyed":false},{"name":"Lon"#,
        #"don","shield":0,"research":0,"destroyed":false}],"bombify":[],"score":55,"sanctioned":true,"wasSanctione"#,
        #"d":false,"stillSanctioned":false,"destroyed":false,"attackUs":0,"hasAttackedUs":true,"hasMet":false,"use"#,
        #"d":{},"done":[]}],"us":{"ref":"France","balance":26200000,"motivator":"","strikesToUse":0,"contributions"#,
        #"":1,"bombs":2,"bombedBy":[],"sanctionedBy":["Russia"],"countriesBombed":[],"tech":true,"cities":[{"name""#,
        #":"Paris","shield":0,"research":0,"destroyed":true},{"name":"Lyon","shield":1,"research":1,"destroyed":fa"#,
        #"lse},{"name":"Marseille","shield":1,"research":1,"destroyed":false}],"bombify":[],"score":58,"sanctioned"#,
        #"":true,"wasSanctioned":false,"stillSanctioned":false,"destroyed":false,"attackUs":0,"hasAttackedUs":fals"#,
        #"e,"hasMet":false,"used":{},"done":["shield-1","research-1","research-2","shield-2"]},"environment":60,"p"#,
        #"revEnvironment":55,"round":4,"citiesToBomb":[],"cityIndex":2,"countryIndex":0,"requestToBomb":[],"doneLo"#,
        #"ngCall":true,"midGame":true,"countryToBomb":null,"cityBombIndex":0,"playedNuclear":true,"rundown":true,""#,
        #"completed":false}"#,
    ].joined()

    /// Balances near Long.MIN_VALUE: the purchases, the round's earnings, a country's bombs.
    static let balances: [Crafted] = [
        Crafted(
            "tech bought at Long.MIN", seed: 1, answers: ["yes"],
            edits: [("q", "\"NUCLEAR_PROMPT\""), ("us.balance", "-9223372036854775808")],
            kotlin: ["d7911907ee8f540d", "da6b1786eaaf8318"],
            reopens: "ENVIRONMENT_PROMPT", says: "150 million", holds: "\"balance\":9223372036849775808"
        ),
        Crafted(
            "environment bought near Long.MIN", seed: 1, answers: ["yes"],
            edits: [("q", "\"ENVIRONMENT_PROMPT\""), ("us.balance", "-9223372036853775809")],
            kotlin: ["19df827f1ba2eea3", "1a35585b934a54b5"],
            reopens: "REMOVE_SANCTION_PROMPT", says: "150 million", holds: "\"balance\":9223372036854775807"
        ),
        Crafted(
            "research bought near Long.MIN", seed: 1, answers: ["yes"],
            edits: [("q", "\"RESEARCH_PROMPT\""), ("us.balance", "-9223372036852775809")],
            kotlin: ["a85aec2b314743c4", "4935d72a9a1ef5b0"],
            reopens: "REMOVE_SANCTION_PROMPT", says: "150 million", holds: "\"balance\":9223372036854775807"
        ),
        Crafted(
            "shield bought near Long.MIN", seed: 1, answers: ["yes"],
            edits: [("q", "\"SHIELD_PROMPT\""), ("us.balance", "-9223372036851775809")],
            kotlin: ["1e5c23cb1d01adec", "63857c5f3985f25b"],
            reopens: "REMOVE_SANCTION_PROMPT", says: "150 million", holds: "\"balance\":9223372036854775807"
        ),
        Crafted(
            "a bomb bought at Long.MIN", seed: 1, answers: ["1"],
            edits: [("q", "\"BOMB_NUMBER_PROMPT\""), ("us.balance", "-9223372036854775808")],
            kotlin: ["89ea2e8985c48ac6", "5f479bffc4e1edc6"],
            reopens: "ENVIRONMENT_PROMPT", says: "150 million", holds: "\"balance\":9223372036851775808"
        ),
        Crafted(
            "earnings from Long.MIN", seed: 50, answers: ["no"],
            edits: [("us.balance", "-9223372036854775808")],
            kotlin: ["b709cdb3fead2628", "f38eda013fd553b1"],
            reopens: "USE_BOMBS", says: "You lost"
        ),
        Crafted(
            "a country's bombs bought at Long.MIN", seed: 50, answers: ["no"],
            edits: [
                ("countries.0.balance", "-9223372036854775808"),
                ("countries.0.tech", "true"),
                ("countries.0.bombs", "0"),
            ],
            kotlin: ["92040ed0acc67b70", "7b47584a07d1e7f3"],
            reopens: "BOMB_PROMPT", says: "Russia is nuking", holds: "\"balance\":9223372036845575808"
        ),
    ]

    /// Counts at Int.MAX_VALUE or Int.MIN_VALUE, and those that pass them.
    static let counts: [Crafted] = [
        // fixed: the environment's collapse ends "Every country was destroyed" (it was "Your cities were destroyed")
        Crafted(
            "environment bought at Int.MAX", seed: 1, answers: ["yes", "no", "no", "no", "no"],
            edits: [("q", "\"ENVIRONMENT_PROMPT\""), ("environment", "2147483647")],
            kotlin: [
                "c81f02a73b1a7b52",
                "26e705fb1424712c",
                "5702180ae5947c4c",
                "389bb683b643984b",
                "bad3185535b20532",
                "69e21878bee09b6a",
            ],
            end: "Every country was destroyed", reopens: "CHOOSE_COUNTRY", says: "The environment is at 0 percent.",
            holds: "\"environment\":-2147483619"
        ),
        Crafted(
            "contributions at Int.MAX", seed: 1, answers: ["yes"],
            edits: [("q", "\"ENVIRONMENT_PROMPT\""), ("us.contributions", "2147483647")],
            kotlin: ["b1271efa0a47f30e", "77fb8aa82d6e497d"],
            reopens: "REMOVE_SANCTION_PROMPT", holds: "\"contributions\":-2147483648"
        ),
        Crafted(
            "tech bought at Int.MIN environment", seed: 1, answers: ["yes"],
            edits: [("q", "\"NUCLEAR_PROMPT\""), ("environment", "-2147483648")],
            kotlin: ["39a1616598fc4117", "95a7cc61ed83e66d"],
            reopens: "ENVIRONMENT_PROMPT", holds: "\"environment\":2147483638"
        ),
        Crafted(
            "round Int.MAX ends", seed: 1, answers: ["no"],
            edits: [("round", "2147483647")],
            kotlin: ["1ebcc9d7e1009ac3", "3bb8d450859c3e68"],
            reopens: "PHONE_COUNTRY", says: "Round 2147483647 of 5 complete.", holds: "\"round\":-2147483648"
        ),
        // fixed: the environment's collapse ends "Every country was destroyed" (it was "Your cities were destroyed")
        Crafted(
            "environment Int.MAX collapses", seed: 1, answers: ["no"],
            edits: [("environment", "2147483647")],
            kotlin: ["2c00a15dcc29a5dd", "9f009f73e8876700"],
            end: "Every country was destroyed", reopens: "CHOOSE_COUNTRY",
            says: "The war was stopped due to the environment being so heavily damaged.",
            holds: "\"prevEnvironment\":2147483647"
        ),
        Crafted(
            "score Int.MAX in the last round", seed: 1, answers: ["no"],
            edits: [("round", "5"), ("us.score", "2147483647")],
            kotlin: ["2c56826935e6ec52", "8aff5d99f109f255"],
            end: "You came last", reopens: "CHOOSE_COUNTRY", says: "You came last with",
            holds: "\"score\":-2147483630"
        ),
        Crafted(
            "bombs Int.MIN, one dropped", seed: 7, answers: ["no"],
            edits: [
                ("countries.0.attackUs", "1"),
                ("countries.0.bombify", "[]"),
                ("countries.0.strikesToUse", "1"),
                ("countries.0.bombs", "-2147483648"),
                ("countries.0.tech", "false"),
                ("countries.0.balance", "0"),
            ],
            kotlin: ["1a22e7e235b03fb3", "5b8676f8c0454c17"],
            reopens: "BOMB_PROMPT", holds: "\"bombs\":2147483647"
        ),
        Crafted(
            "attackUs Int.MIN, one dropped", seed: 7, answers: ["no"],
            edits: [
                ("countries.0.attackUs", "-2147483648"),
                ("countries.0.bombify", "[]"),
                ("countries.0.strikesToUse", "1"),
                ("countries.0.bombs", "1"),
                ("countries.0.tech", "false"),
                ("countries.0.balance", "0"),
            ],
            kotlin: ["73b8852b5aaf5dd5", "f93eb535ede11b1a"],
            reopens: "BOMB_PROMPT", holds: "\"attackUs\":2147483647"
        ),
        Crafted(
            "a billion bombs bought", seed: 1, answers: ["1000000000"],
            edits: [("q", "\"BOMB_NUMBER_PROMPT\""), ("us.balance", "3000000000000000")],
            kotlin: ["4af3d9115daf59d5", "238f513a017ad46d"],
            reopens: "REMOVE_SANCTION_PROMPT", holds: "\"environment\":-705032644"
        ),
        Crafted(
            "strikesToUse Int.MAX, bombs bought", seed: 50, answers: ["no"],
            edits: [("countries.0.tech", "true"), ("countries.0.strikesToUse", "2147483647")],
            kotlin: ["32bb390ae294ea02", "00315f2a8e7e3598"],
            reopens: "BOMB_PROMPT", holds: "\"strikesToUse\":-2147483644"
        ),
        Crafted(
            "contributions near Int.MAX lead the fudge", seed: 50, answers: ["no"],
            edits: [("countries.1.contributions", "2147483637")],
            kotlin: ["195f7659f728945c", "66c7f428c56d13fe"],
            reopens: "BOMB_PROMPT", says: "China are in last with", holds: "\"score\":-2147483556"
        ),
    ]

    /// Refs, names and flags that are canonically equal to others, or to the five countries.
    static let texts: [Crafted] = [
        Crafted(
            "bombify a Kelvin-sign UK", seed: 7, answers: ["no"],
            edits: [
                ("countries.0.attackUs", "0"),
                ("countries.0.strikesToUse", "2"),
                ("countries.0.bombs", "2"),
                ("countries.0.bombify", "[\"U\\u212a\"]"),
            ],
            kotlin: ["5e2df76ff4a1d5f0", "8b66a7d50fbe8d25"],
            reopens: "BOMB_PROMPT", says: "London."
        ),
        Crafted(
            "a decomposed city to bomb", seed: 51, answers: ["no"],
            edits: [("countries.3.cities.2.name", "\"Caf\\u00e9\""), ("citiesToBomb", "[\"Cafe\\u0301\"]")],
            kotlin: ["d0fb445593940509", "b5ad8c5e305366f2"],
            reopens: "BOMB_PROMPT", holds: "{\"name\":\"Caf\u{E9}\",\"shield\":0,\"research\":0,\"destroyed\":false}"
        ),
        Crafted(
            "a Kelvin-sign UK bombs", seed: 50, answers: ["no"],
            edits: [("countries.3.ref", "\"U\\u212a\"")],
            kotlin: ["17e70d0e0c5e97a5"],
            fails: true
        ),
        Crafted(
            "UK said, a Kelvin-sign UK in the war", seed: 1, answers: ["UK"],
            edits: [("q", "\"SANCTION_COUNTRY\""), ("countries.3.ref", "\"U\\u212a\"")],
            kotlin: ["d0b9d4a31d80c2c4", "14c20658e1eec431"],
            reopens: "SANCTION_SPECIFIC", says: "You can't sanction the UK."
        ),
        Crafted(
            "done flags that are canonically equal", seed: 1, answers: ["yes"],
            edits: [
                ("q", "\"RESEARCH_PROMPT\""),
                ("cityIndex", "1"),
                ("us.done", "[\"Caf\\u00e9\",\"Cafe\\u0301\"]"),
            ],
            kotlin: ["a83550aff95c8466", "1a32401e01c6f610"],
            reopens: "SHIELD_PROMPT", holds: "\"done\":[\"Caf\u{E9}\",\"Cafe\u{301}\",\"research-1\"]"
        ),
    ]
}
