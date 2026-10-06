package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The Werewolf plays as the skill does (Games/the-werewolf/index.js, and the responses tools/capture.js recorded):
 * the story offer, the villagers one at a time, a wrong guess (jailed, and another villager eaten), the werewolves
 * found, and the lines that change with who is jailed or eaten. Random choices take the first option, so the
 * werewolf always eats the first villager in play who isn't a werewolf.
 */
class WerewolfTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val map = GameMap.load(File(gamesDir, "the-werewolf/map.json"))

    private fun Turn.plays() = steps.mapNotNull { (it as? Step.Play)?.path }

    private fun Turn.said() = steps.filterIsInstance<Step.Play>().flatMap { p -> p.lines.map { it.text } }

    /** Story 1, The Midnight Hunger, at "Want to talk to The Baker?". Its werewolves are the baker and the fisherman. */
    private fun storyOne(): Session {
        val s = Session(map) { 0 }
        assertEquals("intro", s.start().node)
        val offer = s.answer("yes")
        assertEquals(listOf("Time to choose a mystery. How about this: The Midnight Hunger. Something in the village " +
            "is eating well after dark. Do you want to play?"), offer.said())
        val start = s.answer("yes")
        assertEquals("prompt", start.node)
        assertTrue(start.said().contains("The Midnight Hunger."))
        assertEquals("There are 8 villagers, each one has a different story of last night's events. Want to talk " +
            "to The Baker?", start.said().last())
        return s
    }

    @Test
    fun aRoundOfVillagersThenTheGuess() {
        val s = storyOne()
        val first = s.answer("yes")
        assertEquals("a1", first.node)
        assertEquals(listOf("Here is Villager 1 of 8.", "The Baker."), first.said().take(2))
        assertTrue(first.plays().contains("audio/s1/baker/baker-1"))
        assertEquals("Repeat, or next.", first.said().last())

        val again = s.answer("repeat")
        assertEquals("a1", again.node)
        assertFalse("a repeat doesn't announce the villager again", again.said().any { it.contains("Villager") })
        assertTrue(again.plays().contains("audio/s1/baker/baker-1"))
        assertEquals("no repeats too", "a1", s.answer("no").node)

        var t = s.answer("next")
        assertEquals("Here is Villager 2 of 8.", t.said().first())
        assertTrue(t.plays().contains("audio/s1/fisherman/fish-1-1"))
        repeat(6) { t = s.answer("next") }
        assertEquals("a8", t.node)
        assertEquals("Final Villager. The Blacksmith", t.said().first())

        val guess = s.answer("next")
        assertEquals("ga", guess.node)
        assertEquals(listOf("All the villagers have spoken.", "the baker,", "the fisherman,", "the barmaid,",
            "the mayor,", "the farmer,", "the butcher,", "the beggar,", "or the blacksmith.",
            "Who do you think is the werewolf?"), guess.said())

        // A villager who isn't a werewolf: jailed, and the werewolf eats the first villager left (the mayor).
        val jailed = s.answer("it's the barmaid")
        assertEquals("prompt", jailed.node)
        assertTrue(jailed.said().containsAll(listOf("You chuck the barmaid in jail!", "the mayor was eaten.",
            "The werewolf is still around.", "Are you ready to talk to the villagers?")))
        assertEquals(2.0, s.vars["st_barmaid"])
        assertEquals(1.0, s.vars["st_mayor"])
        assertEquals("barmaid", s.vars["first_jail"])

        // Round two: six villagers, each on their second line, picked by what happened.
        val round2 = s.answer("yes")
        assertEquals(listOf("Here is Villager 1 of 6.", "The Baker."), round2.said().take(2))
        assertTrue("the fisherman isn't in jail", round2.plays().contains("audio/s1/baker/baker-2-2"))
        val fisherman = s.answer("next")
        assertTrue("the barmaid was the first one jailed", fisherman.plays().contains("audio/s1/fisherman/fish-2-4"))
        val barmaidSkipped = s.answer("next")
        assertTrue("the barmaid and the mayor are out of play", barmaidSkipped.plays().contains("audio/s1/farmer/farmer-2-2"))
        assertEquals("Here is Villager 3 of 6.", barmaidSkipped.said().first())
    }

    @Test
    fun bothWerewolvesWinAndTheNextStoryIsOffered() {
        val s = storyOne()
        val one = s.answer("the fisherman")
        assertEquals("prompt", one.node)
        assertTrue(one.said().containsAll(listOf("You found the werewolf.", "The fisherwolf has shrunk back.",
            "You chuck him in jail!", "Grave News. The Barmaid was eaten!",
            "the fisherman wasn't the only werewolf. There is one more werewolf to find.")))
        assertEquals(1.0, s.vars["found"])

        val won = s.answer("the baker")
        assertEquals("ending", won.end?.kind)
        assertTrue(won.said().any { it.startsWith("You found the ") && it.contains("where-baker") && it.contains("fisherwolf") })
        assertEquals(true, s.vars["sv1"])
        assertEquals(1.0, s.vars["plays"])

        // Play again: a new night, and story 1 is solved, so story 2 comes first.
        val next = s.restart()
        assertTrue(next.said().contains("Another night. Lo' and behold, the werewolf strikes again."))
        assertEquals("Time to choose a mystery. How about this: The Dark Forest Law. A new law sends everyone " +
            "through the woods at night. Do you want to play?", next.said().last())
    }

    @Test
    fun waitingAroundLetsTheWerewolfWin() {
        val s = storyOne()
        val waited = s.answer("no")
        assertEquals("prompt", waited.node)
        assertTrue(waited.said().containsAll(listOf("You casually wait around.", "Well. Good job.", "The Barmaid got eaten.",
            "I hope you're happy. Can we talk to the villagers now please?")))
        assertEquals("Want to talk to the villagers?", s.silence().said().single())
        var t = waited
        while (t.end == null) t = s.answer("no")
        assertEquals("gameover", t.end?.kind)
        assertTrue(t.said().contains("Game over."))
        assertTrue(t.said().contains("the baker and the fisherman were werewolves."))
        assertEquals("five villagers eaten (three are left), then the werewolves win", 5,
            map.vars.keys.count { it.startsWith("st_") && s.vars[it] == 1.0 })

        // Try again: story 1 has been played, so a story not played yet comes first.
        val retry = s.restart(t.end?.retry)
        assertEquals("The Dark Forest Law", Regex("""How about this: ([^.]+)\.""").find(retry.said().last())?.groupValues?.get(1))
    }

    @Test
    fun aStoryByNumberAndNoForTheNextOne() {
        val s = Session(map) { 0 }
        s.start()
        s.answer("yes")
        assertEquals("The Villafish Feast. The fishing contest ends with more than fish missing. Do you want to play?",
            s.answer("3").said().last())
        assertEquals("The Full Moon Festival. The festival dances on while two villagers vanish. Do you want to play?",
            s.answer("no").said().last())
        assertTrue(s.answer("one").said().last().startsWith("Time to choose a mystery. How about this: The Midnight Hunger."))
        assertEquals("story 1 starts", "prompt", s.answer("yes").node)
        assertEquals(1.0, s.vars["story"])
    }

    @Test
    fun namingAVillagerTooSoonAsksFirst() {
        val s = storyOne()
        s.answer("yes")
        val sure = s.answer("the mayor")
        assertEquals("You haven't listened to all the villagers yet. Are you sure it's The Mayor?", sure.said().single())
        val back = s.answer("no")
        assertEquals("a1", back.node)
        assertTrue("no: the baker again", back.plays().contains("audio/s1/baker/baker-1"))
        s.answer("the mayor")
        assertEquals("next: on to villager 2", "a2", s.answer("next").node)
        s.answer("the mayor")
        assertEquals("Are you sure it's The Butcher?", s.answer("the butcher").said().single())
        val jailed = s.answer("yes")
        assertTrue(jailed.said().contains("You chuck the butcher in jail!"))
    }

    @Test
    fun theGuessTakesNumbersAndTheList() {
        val s = storyOne()
        s.answer("the barmaid")                      // jailed; the mayor is eaten
        s.answer("yes")
        var t = s.answer("next")
        while (t.node != "ga") t = s.answer("next")
        assertEquals(listOf("There are 6 villagers remaining.", "the baker,", "the fisherman,", "the farmer,",
            "the butcher,", "the beggar,", "or the blacksmith.", "Who do you think is the werewolf?"),
            s.answer("list villagers").said())
        assertEquals("The Mayor has already been killed by the werewolf! Guess the werewolf, or say: list villagers.",
            s.answer("the mayor").said().single())
        assertEquals("You can't choose that. Guess the werewolf, or say: list villagers.", s.answer("banana").said().single())
        val third = s.answer("3")
        assertEquals("You chose villager 3, the farmer.", third.said().first())
        assertTrue(third.said().contains("You chuck the farmer in jail!"))
    }
}
