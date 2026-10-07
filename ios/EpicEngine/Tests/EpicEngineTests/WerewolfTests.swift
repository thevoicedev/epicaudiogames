// WerewolfTest.kt: The Werewolf plays as the skill does.

import Testing

@testable import EpicEngine

extension Turn {
    fileprivate func plays() -> [String] {
        steps.compactMap { if case .play(let p) = $0 { p.path } else { nil } }
    }

    fileprivate func said() -> [String] {
        steps.flatMap { step -> [String] in if case .play(let p) = step { p.lines.map(\.text) } else { [] } }
    }
}

/**
 * The Werewolf plays as the skill does (Games/the-werewolf/index.js, and the responses tools/capture.js recorded):
 * the story offer, the villagers one at a time, a wrong guess (jailed, and another villager eaten), the werewolves
 * found, and the lines that change with who is jailed or eaten. Random choices take the first option, so the
 * werewolf always eats the first villager in play who isn't a werewolf.
 */
struct WerewolfTests {
    private let map: GameMap

    init() throws {
        map = try TestRepo.load("the-werewolf")
    }

    /// Story 1, The Midnight Hunger, at "Want to talk to The Baker?". Its werewolves are the baker and the fisherman.
    private func storyOne() throws -> Session {
        let s = Session(map) { _ in 0 }
        #expect(try s.start().node == "intro")
        let offer = try s.answer("yes")
        #expect(
            offer.said() == [
                "Time to choose a mystery. How about this: The Midnight Hunger. Something in the village "
                    + "is eating well after dark. Do you want to play?"
            ])
        let start = try s.answer("yes")
        #expect(start.node == "prompt")
        #expect(start.said().contains("The Midnight Hunger."))
        #expect(
            start.said().last
                == "There are 8 villagers, each one has a different story of last night's events. Want to talk "
                + "to The Baker?")
        return s
    }

    @Test func aRoundOfVillagersThenTheGuess() throws {
        let s = try storyOne()
        let first = try s.answer("yes")
        #expect(first.node == "a1")
        #expect(Array(first.said().prefix(2)) == ["Here is Villager 1 of 8.", "The Baker."])
        #expect(first.plays().contains("audio/s1/baker/baker-1"))
        #expect(first.said().last == "Repeat, or next.")

        let again = try s.answer("repeat")
        #expect(again.node == "a1")
        #expect(!again.said().contains { $0.contains("Villager") }, "a repeat doesn't announce the villager again")
        #expect(again.plays().contains("audio/s1/baker/baker-1"))
        #expect(try s.answer("no").node == "a1", "no repeats too")

        var t = try s.answer("next")
        #expect(t.said().first == "Here is Villager 2 of 8.")
        #expect(t.plays().contains("audio/s1/fisherman/fish-1-1"))
        for _ in 0..<6 { t = try s.answer("next") }
        #expect(t.node == "a8")
        #expect(t.said().first == "Final Villager. The Blacksmith")

        let guess = try s.answer("next")
        #expect(guess.node == "ga")
        #expect(
            guess.said() == [
                "All the villagers have spoken.", "the baker,", "the fisherman,", "the barmaid,",
                "the mayor,", "the farmer,", "the butcher,", "the beggar,", "or the blacksmith.",
                "Who do you think is the werewolf?",
            ])

        // A villager who isn't a werewolf: jailed, and the werewolf eats the first villager left (the mayor).
        let jailed = try s.answer("it's the barmaid")
        #expect(jailed.node == "prompt")
        #expect(
            Set(jailed.said()).isSuperset(of: [
                "You chuck the barmaid in jail!", "the mayor was eaten.",
                "The werewolf is still around.", "Are you ready to talk to the villagers?",
            ]))
        #expect(s.vars["st_barmaid"] == 2.0)
        #expect(s.vars["st_mayor"] == 1.0)
        #expect(s.vars["first_jail"] == "barmaid")

        // Round two: six villagers, each on their second line, picked by what happened.
        let round2 = try s.answer("yes")
        #expect(Array(round2.said().prefix(2)) == ["Here is Villager 1 of 6.", "The Baker."])
        #expect(round2.plays().contains("audio/s1/baker/baker-2-2"), "the fisherman isn't in jail")
        let fisherman = try s.answer("next")
        #expect(fisherman.plays().contains("audio/s1/fisherman/fish-2-4"), "the barmaid was the first one jailed")
        let barmaidSkipped = try s.answer("next")
        #expect(
            barmaidSkipped.plays().contains("audio/s1/farmer/farmer-2-2"), "the barmaid and the mayor are out of play")
        #expect(barmaidSkipped.said().first == "Here is Villager 3 of 6.")
    }

    @Test func bothWerewolvesWinAndTheNextStoryIsOffered() throws {
        let s = try storyOne()
        let one = try s.answer("the fisherman")
        #expect(one.node == "prompt")
        #expect(
            Set(one.said()).isSuperset(of: [
                "You found the werewolf.", "The fisherwolf has shrunk back.",
                "You chuck him in jail!", "Grave News. The Barmaid was eaten!",
                "the fisherman wasn't the only werewolf. There is one more werewolf to find.",
            ]))
        #expect(s.vars["found"] == 1.0)

        let won = try s.answer("the baker")
        #expect(won.end?.kind == "ending")
        #expect(
            won.said().contains { $0.hasPrefix("You found the ") && $0.contains("where-baker") && $0.contains("fisherwolf") })
        #expect(s.vars["sv1"] == true)
        #expect(s.vars["plays"] == 1.0)

        // Play again: a new night, and story 1 is solved, so story 2 comes first.
        let next = try s.restart()
        #expect(next.said().contains("Another night. Lo' and behold, the werewolf strikes again."))
        #expect(
            next.said().last
                == "Time to choose a mystery. How about this: The Dark Forest Law. A new law sends everyone "
                + "through the woods at night. Do you want to play?")
    }

    @Test func waitingAroundLetsTheWerewolfWin() throws {
        let s = try storyOne()
        let waited = try s.answer("no")
        #expect(waited.node == "prompt")
        #expect(
            Set(waited.said()).isSuperset(of: [
                "You casually wait around.", "Well. Good job.", "The Barmaid got eaten.",
                "I hope you're happy. Can we talk to the villagers now please?",
            ]))
        #expect(try s.silence().said().single() == "Want to talk to the villagers?")
        var t = waited
        while t.end == nil { t = try s.answer("no") }
        #expect(t.end?.kind == "gameover")
        #expect(t.said().contains("Game over."))
        #expect(t.said().contains("the baker and the fisherman were werewolves."))
        #expect(
            map.vars.keys.filter { $0.hasPrefix("st_") && s.vars[$0] == 1.0 }.count == 5,
            "five villagers eaten (three are left), then the werewolves win")

        // Try again: story 1 has been played, so a story not played yet comes first.
        let retry = try s.restart(at: t.end?.retry)
        #expect(try regexFind(#"How about this: ([^.]+)\."#, retry.said().last ?? "")?[1] == "The Dark Forest Law")
    }

    @Test func aStoryByNumberAndNoForTheNextOne() throws {
        let s = Session(map) { _ in 0 }
        _ = try s.start()
        _ = try s.answer("yes")
        #expect(
            try s.answer("3").said().last
                == "The Villafish Feast. The fishing contest ends with more than fish missing. Do you want to play?")
        #expect(
            try s.answer("no").said().last
                == "The Full Moon Festival. The festival dances on while two villagers vanish. Do you want to play?")
        #expect(
            try #require(s.answer("one").said().last)
                .hasPrefix("Time to choose a mystery. How about this: The Midnight Hunger."))
        #expect(try s.answer("yes").node == "prompt", "story 1 starts")
        #expect(s.vars["story"] == 1.0)
    }

    @Test func namingAVillagerTooSoonAsksFirst() throws {
        let s = try storyOne()
        _ = try s.answer("yes")
        let sure = try s.answer("the mayor")
        #expect(try sure.said().single() == "You haven't listened to all the villagers yet. Are you sure it's The Mayor?")
        let back = try s.answer("no")
        #expect(back.node == "a1")
        #expect(back.plays().contains("audio/s1/baker/baker-1"), "no: the baker again")
        _ = try s.answer("the mayor")
        #expect(try s.answer("next").node == "a2", "next: on to villager 2")
        _ = try s.answer("the mayor")
        #expect(try s.answer("the butcher").said().single() == "Are you sure it's The Butcher?")
        let jailed = try s.answer("yes")
        #expect(jailed.said().contains("You chuck the butcher in jail!"))
    }

    @Test func theGuessTakesNumbersAndTheList() throws {
        let s = try storyOne()
        _ = try s.answer("the barmaid")                      // jailed; the mayor is eaten
        _ = try s.answer("yes")
        var t = try s.answer("next")
        while t.node != "ga" { t = try s.answer("next") }
        #expect(
            try s.answer("list villagers").said() == [
                "There are 6 villagers remaining.", "the baker,", "the fisherman,", "the farmer,",
                "the butcher,", "the beggar,", "or the blacksmith.", "Who do you think is the werewolf?",
            ])
        #expect(
            try s.answer("the mayor").said().single()
                == "The Mayor has already been killed by the werewolf! Guess the werewolf, or say: list villagers.")
        #expect(
            try s.answer("banana").said().single() == "You can't choose that. Guess the werewolf, or say: list villagers.")
        let third = try s.answer("3")
        #expect(third.said().first == "You chose villager 3, the farmer.")
        #expect(third.said().contains("You chuck the farmer in jail!"))
    }

    @Test func theGuessIsSaidOrTyped() throws {
        // reverted: no villager buttons; the villagers are listed in the chat and named by voice or typing
        let s = try storyOne()
        var t = try s.answer("yes")
        while t.node != "ga" { t = try s.answer("next") }
        #expect(try #require(t.ask).buttons.map(\.label) == ["List villagers"])
        #expect(try s.answer("the barmaid").said().contains("You chuck the barmaid in jail!"))
    }

    @Test func oneMoreTimeIsARepeatNotANumber() throws {
        // fixed: "one more time" was read as a 1: story 1 at the offer, the baker jailed at the guess
        let offer = Session(map) { _ in 0 }
        _ = try offer.start()
        _ = try offer.answer("yes")
        _ = try offer.answer("3")
        let again = try offer.answer("one more time")
        #expect(offer.vars["off"] == 3.0)
        #expect(!again.said().contains { $0.contains("The Midnight Hunger") })
        let s = try storyOne()
        var t = try s.answer("yes")
        while t.node != "ga" { t = try s.answer("next") }
        let guess = try s.answer("one more time")
        #expect(guess.node == "ga")
        #expect(!guess.said().contains { $0.contains("in jail") })
        #expect(try s.answer("1").said().first == "You chose villager 1, the baker.")
    }

    @Test func okayAndNotNowAtTheStart() throws {
        // fixed: "okay" and "not now" weren't understood
        let s = Session(map) { _ in 0 }
        _ = try s.start()
        #expect(try #require(s.answer("okay").said().last).hasPrefix("Time to choose a mystery."))
        let leave = Session(map) { _ in 0 }
        _ = try leave.start()
        #expect(try leave.answer("not now").quit)
    }
}
