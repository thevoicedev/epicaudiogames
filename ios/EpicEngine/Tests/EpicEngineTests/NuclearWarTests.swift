// NuclearWarTest.kt (lines 1-358): Nuclear War played by a bot, thousands of seeded games with random answers.

import Foundation
import Testing

@testable import EpicEngine

/**
 * Nuclear War played by a bot: thousands of seeded games with random answers (the buttons, names, numbers, words it
 * doesn't know, silence). Every game must end, Don must only say lines from [Lines.all], every question must have a
 * reprompt, and a save must pick up where it was. With games/nuclear-war/clips.json made, every line has its clip.
 *
 * The games and the bot draw from Kotlin's Random(seed) (XorWowRandom), as NuclearWarTest does, so the full run
 * (EPIC_SLOW=1) plays the same games and prints what Kotlin's prints; with the real clips.json it's checked against
 * Kotlin's output. The quick loop plays fewer games.
 *
 * Kotlin notes the lines without a clip on the NuclearAudio all the games share; here each game notes its own (L9),
 * so a run gathers them from the game and from the one that picked its save up.
 */
struct NuclearWarTests {
    private let dir: URL
    private let clips: URL
    /// Whether games/nuclear-war/clips.json is there (else the placeholder audio).
    private let real: Bool
    private let audio: NuclearAudio
    private let all: Set<String>

    init() throws {
        dir = try TestRepo.games().appendingPathComponent(NuclearWar.id)
        clips = dir.appendingPathComponent("clips.json")
        real = Self.isFile(clips)
        audio = real ? try NuclearAudio.load(clips) : NuclearAudio.placeholder()
        all = Set(try Lines.all().map(\.text))
    }

    private static func isFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private let extras = ["yes", "no", "yeah", "nope", "shield", "research", "all of them", "next", "next round",
        "none", "3", "two", "twenty", "repeat", "banana", "france", "the uk", "america", "china", "russia", "paris",
        "new york", "moscow", "london", "shanghai", "st petersburg", ""]

    /// The games the quick loop plays (the full run plays Kotlin's 3000). Enough for every question to come up.
    private static let quickGames: Int32 = 300

    private struct Run {
        let turns: Int
        let end: String
        let states: Set<String>
        /// The lines asked for without a clip, by the game and by the one that picked it up (Kotlin's audio.missing).
        let missing: Set<String>
        /// What the game that picked the save up said (Kotlin's test looks only at the first game's lines).
        let pickedUp: Set<String>
    }

    private func play(_ seed: Int32, _ given: NuclearWar? = nil) throws -> Run {
        let game = given ?? NuclearWar(audio: audio, random: XorWowRandom(seed: seed))
        let r = XorWowRandom(seed: seed &* 7919 &+ 1)
        var states = Set<String>()
        var turn = try game.start()
        var n = 0
        while turn.end == nil {
            n += 1
            try #require(n < 600, "game \(seed) went on for \(n) turns (at \(turn.node))")
            let ask = try #require(turn.ask, "game \(seed): no question and no end at \(turn.node)")
            try #require(!ask.reprompt.isEmpty, "game \(seed): no reprompt at \(turn.node)")
            states.insert(turn.node)
            if n % 37 == 0 {
                // Leave and come back: the game is saved at every question.
                let saved = game.save()
                let again = NuclearWar(audio: audio, random: XorWowRandom(seed: seed &+ Int32(n)))
                try #require(again.canResume(saved))
                turn = try again.open(saved)
                // The question again (the skill's own "again" can move on, as from a city to its research).
                try #require(turn.ask != nil, "game \(seed): nothing to answer after picking up at \(saved.node)")
                let run = try playOn(again, turn, r, seed, n, &states)
                return Run(turns: run.turns, end: run.end, states: run.states,
                           missing: game.missing.union(run.missing), pickedUp: again.spoken)
            }
            turn = try step(game, turn, r)
        }
        let end = try #require(turn.end)
        return Run(turns: n, end: end.title, states: states, missing: game.missing, pickedUp: [])
    }

    private func playOn(
        _ game: NuclearWar, _ start: Turn, _ r: any KotlinRandom, _ seed: Int32, _ from: Int,
        _ states: inout Set<String>
    ) throws -> Run {
        var turn = start
        var n = from
        while turn.end == nil {
            n += 1
            try #require(n < 900, "game \(seed) went on for \(n) turns (at \(turn.node))")
            let reprompt = turn.ask?.reprompt ?? []
            try #require(!reprompt.isEmpty, "game \(seed): no reprompt at \(turn.node)")
            states.insert(turn.node)
            turn = try step(game, turn, r)
        }
        let end = try #require(turn.end)
        return Run(turns: n, end: end.title, states: states, missing: game.missing, pickedUp: game.spoken)
    }

    private func step(_ game: NuclearWar, _ turn: Turn, _ r: any KotlinRandom) throws -> Turn {
        let buttons = try #require(turn.ask).buttons
        // Kotlin's when, in order: silence, else (only when there are buttons) a button, else one of the extras.
        if try r.nextInt(until: 20) == 0 { return try game.silence() }
        if try !buttons.isEmpty && r.nextInt(until: 10) < 7 {
            return try game.answer(buttons[r.nextInt(until: buttons.count)].value)
        }
        return try game.answer(extras[r.nextInt(until: extras.count)])
    }

    /// `end.replace(Regex("came \\w+"), "came N")`.
    private static func cameN(_ end: String) throws -> String {
        let re = try NSRegularExpression(pattern: "came \\w+")
        return re.stringByReplacingMatches(
            in: end, range: NSRange(location: 0, length: (end as NSString).length), withTemplate: "came N")
    }

    /// What NuclearWarTest.kt printed for its 3000 games with the real clips.json (engine/build/test-results); the
    /// full run with the real clips.json prints the same. Take Kotlin's new output when its game changes.
    /// (Taken again after the Nuclear War fixes: bomb counts said with "not", the calls, ties, the environment's end.)
    private static let kotlinPrinted = [
        "Nuclear War: 3000 games, 228450 turns; ends {Your cities were destroyed=801, You came N=1734, "
            + "You won the war!=424, You came N first=41}",
        "  22 questions: [BOMB_INDIVIDUAL, BOMB_NUMBER_PROMPT, BOMB_PROMPT, CHOOSE_BOMB_CITY, CHOOSE_BOMB_COUNTRY, "
            + "CHOOSE_COUNTRY, CITY_PROMPT, CONFIRM_BOMB_PROMPT, COUNTRY_SELECT, ENVIRONMENT_PROMPT, NUCLEAR_PROMPT, "
            + "PHONE_COUNTRY, REMOVE_INDIVIDUAL_SANCTION, REMOVE_SANCTION, REMOVE_SANCTION_PROMPT, RESEARCH_PROMPT, "
            + "SANCTION, SANCTION_COUNTRY, SANCTION_SPECIFIC, SHIELD_PROMPT, UPGRADE_PROMPT, USE_BOMBS]",
        "  1130 of 2600 lines said",
    ]

    @Test(.tags(.slow))
    func gamesEndAndSayOnlyKnownLines() throws {
        let games: Int32 = TestRepo.slow ? 3000 : Self.quickGames
        var spoken = Set<String>()
        var pickedUp = Set<String>()
        var ends = LinkedMap<Int>()
        var states = Set<String>()
        var turns = 0
        for seed in 1...games {
            let game = NuclearWar(audio: audio, random: XorWowRandom(seed: seed))
            let run = try play(seed, game)
            // The game's own lines: after the save is picked up, another game speaks (as in Kotlin).
            spoken.formUnion(game.spoken)
            pickedUp.formUnion(run.pickedUp)
            let end = try Self.cameN(run.end)
            ends[end] = (ends[end] ?? 0) + 1
            states.formUnion(run.states)
            turns += run.turns
        }
        let printed = [
            "Nuclear War: \(games) games, \(turns) turns; ends {"
                + ends.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") + "}",
            "  \(states.count) questions: [\(states.sorted(by: Kt.utf16Less).joined(separator: ", "))]",
            "  \(spoken.count) of \(all.count) lines said",
        ]
        print(printed.joined(separator: "\n"))
        let unknown = spoken.subtracting(all)
        #expect(unknown.isEmpty, "lines not in Lines.all(): \(unknown.sorted(by: Kt.utf16Less).prefix(20))")
        // Every question the skill asks comes up.
        for q in ["CHOOSE_COUNTRY", "COUNTRY_SELECT", "NUCLEAR_PROMPT", "ENVIRONMENT_PROMPT", "CITY_PROMPT",
            "UPGRADE_PROMPT", "RESEARCH_PROMPT", "SHIELD_PROMPT", "SANCTION", "SANCTION_COUNTRY", "REMOVE_SANCTION_PROMPT",
            "PHONE_COUNTRY", "BOMB_PROMPT", "BOMB_NUMBER_PROMPT", "USE_BOMBS", "CHOOSE_BOMB_COUNTRY", "CHOOSE_BOMB_CITY",
            "CONFIRM_BOMB_PROMPT"]
        {
            #expect(states.contains(q), "never asked: \(q)")
        }
        #expect(ends.keys.contains { $0.hasPrefix("You") }, "no game was won or finished: \(ends)")
        // Not in Kotlin's test: the games picked up from a save say only known lines too.
        let unknownLater = pickedUp.subtracting(all)
        #expect(unknownLater.isEmpty,
            "lines not in Lines.all() after a save: \(unknownLater.sorted(by: Kt.utf16Less).prefix(20))")
        // Nor this: the same games as Kotlin's, so the same totals.
        if TestRepo.slow && real {
            for (swift, kotlin) in zip(printed, Self.kotlinPrinted) {
                #expect(swift == kotlin, "Swift printed\n\(swift)\nwhere Kotlin printed\n\(kotlin)")
            }
        }
    }

    @Test(.tags(.slow))
    func everyLineHasItsClip() throws {
        if !real { return }     // before tools/games/nuclearwar.py has made the audio
        let missing = all.filter { !audio.has($0) }.sorted(by: Kt.utf16Less)
        #expect(missing.isEmpty, "\(missing.count) lines without a clip, e.g. \(missing.prefix(10))")
        var asked = Set<String>()
        for seed in Int32(1)...300 { asked.formUnion(try play(seed).missing) }
        #expect(asked.isEmpty, "clips asked for but missing: \(asked.sorted(by: Kt.utf16Less).prefix(10))")
    }

    @Test func theLinesFileIsUpToDate() throws {
        let file = dir.appendingPathComponent("lines.json")
        if !Self.isFile(file) { return }
        let text = try String(contentsOf: file, encoding: .utf8)
        let re = try NSRegularExpression(pattern: #""text":"((?:[^"\\]|\\.)*)""#)
        let ns = text as NSString
        let texts = Set(re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
                .replacingOccurrences(of: "\\\"", with: "\"", options: .literal)
                .replacingOccurrences(of: "\\\\", with: "\\", options: .literal)
        })
        #expect(all == texts,
            "games/nuclear-war/lines.json is out of date: run gradlew :engine:run --args=\"--nuclear-lines\"")
    }

    @Test func moneyIsSaidAsTheSkillSaysIt() {
        #expect(World.formatMillions(0) == "0")
        #expect(World.formatMillions(300_000) == "300,000")
        #expect(World.formatMillions(500_000) == "half a million")
        #expect(World.formatMillions(12_000_000) == "12 million")
        #expect(World.formatMillions(12_500_000) == "12 and a half million")
        #expect(World.formatMillions(9_600_000) == "9.6 million")
        #expect(World.sayable(45_400_000) == 45_500_000)
        #expect(World.sayable(400_000_000) == 150_000_000)
        #expect(World.sayableAmounts().allSatisfy { all.contains(Lines.money($0)) })
    }

    @Test func aListIsSaidInPiecesThatJoin() {
        #expect(Lines.items(["Paris", "Lyon", "Moscow"], .end) == ["Paris,", "Lyon", "and Moscow."])
        #expect(Lines.items(["the UK", "you"], .comma) == ["The UK", "and you,"])
        #expect(Lines.items(["Paris"], .end) == ["Paris."])
    }

    // ----- Fixed, each from a save made by hand (as NuclearWarTest.kt plays them) -----

    private let quiet = NuclearAudio.placeholder()

    /// A France game at [q] in round 2 (10 million, nuclear tech), changed by [edit], opened in a new game.
    private func at(_ q: Q, seed: Int32 = 1, _ edit: (NuclearState) throws -> Void = { _ in }) throws -> NuclearWar {
        let first = NuclearWar(audio: quiet, random: XorWowRandom(seed: seed))
        _ = try first.start()
        _ = try first.answer("france")
        let st = try state(first)
        st.q = q
        st.round = 2
        st.rundown = true
        st.midGame = true
        try #require(st.us).tech = true
        try edit(st)
        let game = NuclearWar(audio: quiet, random: XorWowRandom(seed: seed))
        _ = try game.open(Saved(node: q.rawValue, vars: ["state": .string(st.toJSONString())], ended: false))
        return game
    }

    private func state(_ game: NuclearWar) throws -> NuclearState {
        let text = try #require(game.save().vars["state"]?.stringValue)
        return try NuclearState.fromJSON(JSONParser.parse(text).jsonObject())
    }

    private func us(_ game: NuclearWar) throws -> Nation { try #require(state(game).us) }

    private func said(_ turn: Turn) -> [String] {
        turn.steps.flatMap { step -> [String] in
            if case .play(let clip) = step { clip.lines.map(\.text) } else { [] }
        }
    }

    @Test func aSaveThatCantBeReadStartsAfresh() throws {
        // fixed: a state or settings that couldn't be read threw (and crashed Kotlin's app at every open)
        let settings = #"{"playedNuclear":true,"rundown":true,"completed":false}"#
        for bad in ["{}", "nope", #"{"q":"RENAMED","countries":[],"requestToBomb":[]}"#] {
            let saved = Saved(node: "CITY_PROMPT", vars: ["state": .string(bad), "settings": .string(settings)],
                              ended: false)
            let game = NuclearWar(audio: quiet, random: XorWowRandom(seed: 1))
            #expect(!game.canResume(saved), "\(bad)")
            let turn = try game.open(saved)
            #expect(turn.node == "CHOOSE_COUNTRY", "\(bad)")
            #expect(said(turn) == [Lines.welcomeBack], "\(bad)")      // its settings kept
        }
        for bad in ["nope", "[]", #"{"playedNuclear":1}"#] {
            let saved = Saved(node: "CHOOSE_COUNTRY", vars: ["settings": .string(bad)], ended: false)
            let turn = try NuclearWar(audio: quiet, random: XorWowRandom(seed: 1)).open(saved)
            #expect(turn.node == "CHOOSE_COUNTRY", "\(bad)")
        }
    }

    @Test func aNumberSaidWithNotIsANo() throws {
        // fixed: "not one" and "I don't want one" bought a bomb, and "one hundred" bought one
        for q in [Q.bombPrompt, .bombNumberPrompt] {
            for no in ["not one", "I don't want one", "no, not a single one", "never"] {
                let game = try at(q)
                _ = try game.answer(no)
                #expect(try us(game).balance == 10_000_000, "\(no) at \(q)")
                #expect(try state(game).q == .environmentPrompt, "\(no) at \(q)")
            }
            for many in ["one hundred", "a hundred", "two thousand"] {
                let game = try at(q)
                let turn = try game.answer(many)
                #expect(try us(game).balance == 10_000_000, "\(many) at \(q)")
                #expect(said(turn).contains(Lines.affordUpTo(3)), "\(many) at \(q): \(said(turn))")
            }
            let game = try at(q)
            _ = try game.answer("twenty-two")
            #expect(try us(game).balance == 10_000_000, "twenty-two at \(q)")
            _ = try game.answer("two")
            #expect(try us(game).bombs == 2)
        }
    }

    @Test func aYesWordWithNotIsANo() throws {
        // fixed: "absolutely not", "of course not" and "I do not" were a yes
        for no in ["absolutely not", "of course not", "I do not", "definitely not", "not at all"] {
            let game = try at(.nuclearPrompt) { try #require($0.us).tech = false }
            _ = try game.answer(no)
            #expect(try !us(game).tech, "\(no)")
        }
    }

    @Test func notSureIsNeitherYesNorNo() throws {
        // fixed: "I'm not sure" was a yes ("sure") and "I don't know" a no ("i don't"): the question is asked again
        for unsure in ["I'm not sure", "I don't know"] {
            let game = try at(.nuclearPrompt) { try #require($0.us).tech = false }
            #expect(try game.understands(unsure), "\(unsure)")     // heard, so the app doesn't swap it for "I'm sure"
            #expect(try game.answer(unsure).node == "NUCLEAR_PROMPT", "\(unsure)")
        }
    }

    @Test func usIsTheUsa() throws {
        // fixed: "US" and "U.S." weren't understood
        for said in ["US", "U.S.", "the U.S.", "us"] {
            let game = NuclearWar(audio: quiet, random: XorWowRandom(seed: 1))
            _ = try game.start()
            #expect(try game.answer(said).node == "COUNTRY_SELECT", "\(said)")
            #expect(try us(game).ref == "USA", "\(said)")
        }
        // "us" in a sentence is the pronoun: still a yes
        let game = try at(.nuclearPrompt) { try #require($0.us).tech = false }
        #expect(try game.answer("yes, tell us").node == "ENVIRONMENT_PROMPT")
    }

    @Test func theLastCityLeftIsAskedWithYesAndNo() throws {
        // fixed: "Would you like to attack Wuhan?" had only [Wuhan], and no way to say no
        let game = try at(.useBombs) { st in
            try #require(st.us).bombs = 1
            let china = try #require(st.countries.first { $0.ref == "China" })
            for city in china.cities.prefix(2) { city.destroyed = true }
        }
        let turn = try game.answer("china")
        #expect(turn.node == "CHOOSE_BOMB_CITY")
        #expect(turn.ask?.buttons.map(\.value) == ["yes", "no"])
        #expect(try game.answer("no").node == "CONFIRM_BOMB_PROMPT")
    }

    @Test func researchIsOfferedWithExactlyItsCost() throws {
        // fixed: with exactly 2 million after the environment, the cities were skipped
        let game = try at(.environmentPrompt) { try #require($0.us).balance = 2_000_000 }
        #expect(try game.answer("no").node == "CITY_PROMPT")
        let bought = try at(.environmentPrompt) { try #require($0.us).balance = 3_000_000 }
        #expect(try bought.answer("yes").node == "CITY_PROMPT")
    }

    @Test func theMoneyLeftIsSaidOnceAfterResearch() throws {
        // fixed: "You have 2 million left." was said twice
        let game = try at(.researchPrompt) { try #require($0.us).balance = 4_000_000 }
        let turn = try game.answer("yes")
        #expect(said(turn).count { $0 == Lines.youHave } == 1, "\(said(turn))")
        #expect(turn.node == "RESEARCH_PROMPT")      // the next city's
    }

    @Test func theEnvironmentTipIsSaidOnlyWhenItsAmountIsRight() throws {
        // fixed: "an extra 500K" was said at 115 percent too (1.5 million)
        func envTurn(_ tech: String) throws -> Turn {
            let game = NuclearWar(audio: quiet, random: XorWowRandom(seed: 1))
            _ = try game.start()
            _ = try game.answer("france")
            _ = try game.answer("no")
            _ = try game.answer(tech)
            return try game.answer("yes")
        }
        #expect(said(try envTurn("yes")).contains(Lines.envExtra))
        #expect(!said(try envTurn("no")).contains(Lines.envExtra))
    }

    @Test func aCalmCountryAfterThreeAngryOnesStillCalls() throws {
        // fixed: three angry countries in a row skipped the fourth's call, and Don said no one was calling
        let game = try at(.sanction) { st in
            // (no money, so no country buys bombs and calms down by using them)
            for (i, c) in st.countries.enumerated() {
                c.attackUs = i < 3 ? 1 : 0
                c.balance = 0
            }
        }
        let turn = try game.answer("no")
        #expect(!Lines.noCalls.contains { said(turn).contains($0) }, "\(said(turn))")
        #expect(turn.node == "PHONE_COUNTRY")
        #expect(try state(game).countryIndex == 3)
        // Three angry after one call: they're said, not "no one calls".
        let after = try at(.phoneCountry) { st in
            for (i, c) in st.countries.enumerated() { c.attackUs = i > 0 ? 1 : 0 }
        }
        let answered = try after.answer("yes")
        #expect(!Lines.noCalls.contains { said(answered).contains($0) }, "\(said(answered))")
        let last = try Lines.singleNoTalk(state(after).countries[3].ref)
        #expect(said(answered).contains { last.contains($0) }, "\(said(answered))")
    }

    @Test func nextRoundAtACallStillDoesWhatTheCallsWould() throws {
        // fixed: "next round" skipped the calls' effects (no anger at being bombed, no sanctions kept)
        let game = try at(.phoneCountry) { st in
            st.countries[0].sanctioned = true
            try #require(st.us).countriesBombed.append(st.countries[1].ref)
        }
        let turn = try game.answer("next round")
        #expect(turn.node != "PHONE_COUNTRY")
        let st = try state(game)
        #expect(st.countries[0].stillSanctioned)
        #expect(st.countries[1].attackUs == 1)
    }

    @Test func theEnvironmentsCollapseEndsWithEveryCountryDestroyed() throws {
        // fixed: it ended "Your cities were destroyed", with no city hit
        let game = try at(.sanction) { $0.environment = -150 }
        let turn = try game.answer("no")
        #expect(turn.end?.title == "Every country was destroyed")
        #expect(said(turn).contains(Lines.everyCountry))
    }

    @Test func everyoneTiedIsJointFirst() throws {
        // fixed: a single tied group was "last" (no triumph), while the title said "joint first"
        let game = try at(.sanction) { st in
            st.round = 5
            st.countries = Array(st.countries.prefix(1))
            for n in st.countries + [try #require(st.us)] {
                n.balance = 0
                n.score = 30
                n.contributions = 0
            }
        }
        let turn = try game.answer("no")
        #expect(turn.end?.title == "You came joint first")
        #expect(said(turn).contains(Lines.endTiePlacing("first")), "\(said(turn))")
    }
}
