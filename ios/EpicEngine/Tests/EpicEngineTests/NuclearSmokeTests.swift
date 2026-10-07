// Smoke tests for the Nuclear War port (nuclear/*.kt): seeded games play to an end, saves read back, numbers said.
// The conformance tests against fixtures/engine/nuclear-war and the port of NuclearWarTest are separate.

import Foundation
import Testing

@testable import EpicEngine

struct NuclearSmokeTests {
    /// The real audio when games/nuclear-war/clips.json is there, else the placeholder.
    static func audio() throws -> (NuclearAudio, real: Bool) {
        guard let root = TestRepo.root else { return (NuclearAudio.placeholder(), false) }
        let clips = root.appendingPathComponent("games/nuclear-war/clips.json")
        guard FileManager.default.fileExists(atPath: clips.path) else { return (NuclearAudio.placeholder(), false) }
        return (try NuclearAudio.load(clips), true)
    }

    @Test func seededGamesPlayToAnEnd() throws {
        let (audio, real) = try Self.audio()
        let all = Set(try Lines.all().map(\.text))
        for seed in Int32(1)...5 {
            let game = NuclearWar(audio: audio, random: XorWowRandom(seed: seed))
            let player = XorWowRandom(seed: seed &* 31 &+ 7)
            var turn = try game.start()
            var n = 0
            while turn.end == nil {
                n += 1
                try #require(n < 600, "game \(seed) went on for \(n) turns (at \(turn.node))")
                let ask = try #require(turn.ask, "game \(seed): no question and no end at \(turn.node)")
                #expect(!ask.reprompt.isEmpty, "game \(seed): no reprompt at \(turn.node)")
                // Each save's state reads back to the same JSON.
                let state = try #require(game.save().vars["state"]?.stringValue)
                let back = try NuclearState.fromJSON(JSONParser.parse(state).jsonObject()).toJSONString()
                #expect(back == state)
                if try ask.buttons.isEmpty || player.nextInt(until: 10) == 0 {
                    turn = try game.answer("yes")
                } else {
                    turn = try game.answer(ask.buttons[try player.nextInt(until: ask.buttons.count)].value)
                }
            }
            #expect(turn.node == Q.gameOver.rawValue)
            #expect(game.save().ended)
            let unknown = game.spoken.subtracting(all)
            #expect(unknown.isEmpty, "said but not in Lines.all(): \(unknown)")
            if real { #expect(game.missing.isEmpty, "lines without a clip: \(game.missing.prefix(10))") }
        }
    }

    @Test func aSaveOpensAtTheSameQuestion() throws {
        let (audio, _) = try Self.audio()
        let game = NuclearWar(audio: audio, random: XorWowRandom(seed: 3))
        _ = try game.start()
        _ = try game.answer("france")
        _ = try game.answer("yes")
        let saved = game.save()
        #expect(saved.node == Q.countrySelect.rawValue)
        let again = NuclearWar(audio: audio, random: XorWowRandom(seed: 4))
        #expect(again.canResume(saved))
        let turn = try again.open(saved)
        #expect(turn.node == saved.node)
        #expect(turn.ask != nil)
        #expect(again.save().vars["state"] == saved.vars["state"])
    }

    @Test func stateReadsAreLenientOnlyForMissingValues() throws {
        let game = NuclearWar(audio: NuclearAudio.placeholder(), random: XorWowRandom(seed: 1))
        _ = try game.start()
        _ = try game.answer("the uk")
        let state = try JSONParser.parse(#require(game.save().vars["state"]?.stringValue)).jsonObject()
        // A missing Int or Boolean takes its default...
        #expect(try NuclearState.fromJSON(state.removing("round")).round == 0)
        #expect(try NuclearState.fromJSON(state.removing("midGame")).midGame == false)
        // ...but one that is there and isn't one fails, as kotlinx's int and boolean do.
        var bad = state
        bad["round"] = "two"
        #expect(throws: (any Error).self) { try NuclearState.fromJSON(bad) }
        bad = state
        bad["midGame"] = .literal("1")
        #expect(throws: (any Error).self) { try NuclearState.fromJSON(bad) }
        bad = state
        bad["q"] = "NOT_A_QUESTION"
        #expect(throws: (any Error).self) { try NuclearState.fromJSON(bad) }
        // fixed: settings that can't be read are left out (opening threw, and Kotlin's app crashed at every open).
        let other = NuclearWar(audio: NuclearAudio.placeholder(), random: XorWowRandom(seed: 2))
        let saved = Saved(node: "COUNTRY_SELECT", vars: ["settings": #"{"rundown":"often"}"#], ended: false)
        #expect(try other.open(saved).node == Q.chooseCountry.rawValue)
    }

    @Test func numbersSaid() {
        let game = NuclearWar(audio: NuclearAudio.placeholder(), random: XorWowRandom(seed: 1))
        #expect(game.number("3") == 3)
        #expect(game.number("three bombs") == 3)
        #expect(game.number("twenty-two") == 22)
        #expect(game.number("twenty") == 20)
        #expect(game.number("a couple") == 2)
        // fixed: "hundred" and "thousand" count, and a number said with "not" is 0 ("not one" bought a bomb).
        #expect(game.number("99999999999 thousand") == 1000)
        #expect(game.number("one hundred") == 100)
        #expect(game.number("a hundred") == 100)
        #expect(game.number("twenty two hundred") == 2200)
        #expect(game.number("2147483647 thousand") == 2_147_483_647)
        #expect(game.number("not one") == 0)
        #expect(game.number("I don't want one") == 0)
        #expect(game.number("one, not two") == 1)
        #expect(game.number("none") == nil)
    }

    @Test func moneyAsDonSaysIt() {
        #expect(World.formatMillions(0) == "0")
        #expect(World.formatMillions(300_000) == "300,000")
        #expect(World.formatMillions(500_000) == "half a million")
        #expect(World.formatMillions(12_500_000) == "12 and a half million")
        #expect(World.formatMillions(12_400_000) == "12.4 million")
        #expect(World.sayable(43_200_000) == 43_000_000)
        #expect(Lines.money(-5) == "0")
    }
}
