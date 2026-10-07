package com.epicaudiogames.engine

import com.epicaudiogames.engine.nuclear.Lines
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import com.epicaudiogames.engine.nuclear.Q
import com.epicaudiogames.engine.nuclear.State
import com.epicaudiogames.engine.nuclear.World
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

/**
 * Nuclear War played by a bot: thousands of seeded games with random answers (the buttons, names, numbers, words it
 * doesn't know, silence). Every game must end, Don must only say lines from [Lines.all], every question must have a
 * reprompt, and a save must pick up where it was. With games/nuclear-war/clips.json made, every line has its clip.
 */
class NuclearWarTest {
    private val dir = File(System.getProperty("games.dir") ?: "../../games", NuclearWar.ID)
    private val clips = File(dir, "clips.json")
    private val audio by lazy { if (clips.isFile) NuclearAudio.load(clips) else NuclearAudio.placeholder() }
    private val all by lazy { Lines.all().map { it.text }.toSet() }

    private val extras = listOf("yes", "no", "yeah", "nope", "shield", "research", "all of them", "next", "next round",
        "none", "3", "two", "twenty", "repeat", "banana", "france", "the uk", "america", "china", "russia", "paris",
        "new york", "moscow", "london", "shanghai", "st petersburg", "")

    private data class Run(val turns: Int, val end: String, val states: Set<String>)

    private fun play(seed: Int, game: NuclearWar = NuclearWar(audio, Random(seed))): Run {
        val r = Random(seed * 7919 + 1)
        val states = mutableSetOf<String>()
        var turn = game.start()
        var n = 0
        while (turn.end == null) {
            n++
            assertTrue("game $seed went on for $n turns (at ${turn.node})", n < 600)
            val ask = turn.ask
            assertNotNull("game $seed: no question and no end at ${turn.node}", ask)
            assertTrue("game $seed: no reprompt at ${turn.node}", ask!!.reprompt.isNotEmpty())
            states += turn.node
            if (n % 37 == 0) {
                // Leave and come back: the game is saved at every question.
                val saved = game.save()
                val again = NuclearWar(audio, Random(seed + n))
                assertTrue(again.canResume(saved))
                turn = again.open(saved)
                // The question again (the skill's own "again" can move on, as from a city to its research).
                assertTrue("game $seed: nothing to answer after picking up at ${saved.node}", turn.ask != null)
                return playOn(again, turn, r, seed, n, states)
            }
            turn = step(game, turn, r)
        }
        return Run(n, turn.end!!.title, states)
    }

    private fun playOn(game: NuclearWar, start: Turn, r: Random, seed: Int, from: Int, states: MutableSet<String>): Run {
        var turn = start
        var n = from
        while (turn.end == null) {
            n++
            assertTrue("game $seed went on for $n turns (at ${turn.node})", n < 900)
            assertTrue("game $seed: no reprompt at ${turn.node}", turn.ask?.reprompt.orEmpty().isNotEmpty())
            states += turn.node
            turn = step(game, turn, r)
        }
        return Run(n, turn.end!!.title, states)
    }

    private fun step(game: NuclearWar, turn: Turn, r: Random): Turn {
        val buttons = turn.ask!!.buttons
        return when {
            r.nextInt(20) == 0 -> game.silence()
            buttons.isNotEmpty() && r.nextInt(10) < 7 -> game.answer(buttons[r.nextInt(buttons.size)].value)
            else -> game.answer(extras[r.nextInt(extras.size)])
        }
    }

    @Test
    fun gamesEndAndSayOnlyKnownLines() {
        val spoken = mutableSetOf<String>()
        val ends = mutableMapOf<String, Int>()
        val states = mutableSetOf<String>()
        var turns = 0
        for (seed in 1..3000) {
            val game = NuclearWar(audio, Random(seed))
            val run = play(seed, game)
            spoken += game.spoken
            ends.merge(run.end.replace(Regex("came \\w+"), "came N"), 1, Int::plus)
            states += run.states
            turns += run.turns
        }
        println("Nuclear War: 3000 games, $turns turns; ends $ends")
        println("  ${states.size} questions: ${states.sorted()}")
        println("  ${spoken.size} of ${all.size} lines said")
        val unknown = spoken - all
        assertTrue("lines not in Lines.all(): ${unknown.take(20)}", unknown.isEmpty())
        // Every question the skill asks comes up.
        for (q in listOf("CHOOSE_COUNTRY", "COUNTRY_SELECT", "NUCLEAR_PROMPT", "ENVIRONMENT_PROMPT", "CITY_PROMPT",
            "UPGRADE_PROMPT", "RESEARCH_PROMPT", "SHIELD_PROMPT", "SANCTION", "SANCTION_COUNTRY", "REMOVE_SANCTION_PROMPT",
            "PHONE_COUNTRY", "BOMB_PROMPT", "BOMB_NUMBER_PROMPT", "USE_BOMBS", "CHOOSE_BOMB_COUNTRY", "CHOOSE_BOMB_CITY",
            "CONFIRM_BOMB_PROMPT")) {
            assertTrue("never asked: $q", q in states)
        }
        assertTrue("no game was won or finished: $ends", ends.keys.any { it.startsWith("You") })
    }

    @Test
    fun everyLineHasItsClip() {
        if (!clips.isFile) return     // before tools/games/nuclearwar.py has made the audio
        val missing = all.filter { !audio.has(it) }
        assertTrue("${missing.size} lines without a clip, e.g. ${missing.take(10)}", missing.isEmpty())
        for (seed in 1..300) play(seed)
        assertTrue("clips asked for but missing: ${audio.missing.take(10)}", audio.missing.isEmpty())
    }

    @Test
    fun theLinesFileIsUpToDate() {
        val file = File(dir, "lines.json")
        if (!file.isFile) return
        val texts = Regex("\"text\":\"((?:[^\"\\\\]|\\\\.)*)\"").findAll(file.readText()).map {
            it.groupValues[1].replace("\\\"", "\"").replace("\\\\", "\\")
        }.toSet()
        assertEquals("games/nuclear-war/lines.json is out of date: run gradlew :engine:run --args=\"--nuclear-lines\"",
            all, texts)
    }

    @Test
    fun moneyIsSaidAsTheSkillSaysIt() {
        assertEquals("0", World.formatMillions(0))
        assertEquals("300,000", World.formatMillions(300_000))
        assertEquals("half a million", World.formatMillions(500_000))
        assertEquals("12 million", World.formatMillions(12_000_000))
        assertEquals("12 and a half million", World.formatMillions(12_500_000))
        assertEquals("9.6 million", World.formatMillions(9_600_000))
        assertEquals(45_500_000L, World.sayable(45_400_000))
        assertEquals(150_000_000L, World.sayable(400_000_000))
        assertTrue(World.sayableAmounts().all { Lines.money(it) in all })
    }

    @Test
    fun aListIsSaidInPiecesThatJoin() {
        assertEquals(listOf("Paris,", "Lyon", "and Moscow."), Lines.items(listOf("Paris", "Lyon", "Moscow"), Lines.Last.END))
        assertEquals(listOf("The UK", "and you,"), Lines.items(listOf("the UK", "you"), Lines.Last.COMMA))
        assertEquals(listOf("Paris."), Lines.items(listOf("Paris"), Lines.Last.END))
    }

    // ----- Fixed, each from a save made by hand (NuclearWarTests.swift plays the same) -----

    private val quiet = NuclearAudio.placeholder()

    /** A France game at [q] in round 2 (10 million, nuclear tech), changed by [edit], opened in a new game. */
    private fun at(q: Q, seed: Int = 1, edit: (State) -> Unit = {}): NuclearWar {
        val first = NuclearWar(quiet, Random(seed))
        first.start()
        first.answer("france")
        val st = state(first)
        st.q = q
        st.round = 2
        st.rundown = true
        st.midGame = true
        st.us!!.tech = true
        edit(st)
        val game = NuclearWar(quiet, Random(seed))
        game.open(Saved(q.name, mapOf("state" to st.toJson().toString()), false))
        return game
    }

    private fun state(game: NuclearWar) =
        State.fromJson(Json.parseToJsonElement(game.save().vars["state"] as String).jsonObject)

    private fun said(turn: Turn) = turn.steps.filterIsInstance<Step.Play>().flatMap { it.lines }.map { it.text }

    @Test
    fun aSaveThatCantBeReadStartsAfresh() {
        // fixed: a state or settings that couldn't be read threw (and crashed the app at every open)
        val settings = """{"playedNuclear":true,"rundown":true,"completed":false}"""
        for (bad in listOf("{}", "nope", """{"q":"RENAMED","countries":[],"requestToBomb":[]}""")) {
            val saved = Saved("CITY_PROMPT", mapOf("state" to bad, "settings" to settings), false)
            val game = NuclearWar(quiet, Random(1))
            assertFalse(bad, game.canResume(saved))
            val turn = game.open(saved)
            assertEquals(bad, "CHOOSE_COUNTRY", turn.node)
            assertEquals(bad, listOf(Lines.WELCOME_BACK), said(turn))      // its settings kept
        }
        for (bad in listOf("nope", "[]", """{"playedNuclear":1}""")) {
            val turn = NuclearWar(quiet, Random(1)).open(Saved("CHOOSE_COUNTRY", mapOf("settings" to bad), false))
            assertEquals(bad, "CHOOSE_COUNTRY", turn.node)
        }
    }

    @Test
    fun aNumberSaidWithNotIsANo() {
        // fixed: "not one" and "I don't want one" bought a bomb, and "one hundred" bought one
        for (q in listOf(Q.BOMB_PROMPT, Q.BOMB_NUMBER_PROMPT)) {
            for (no in listOf("not one", "I don't want one", "no, not a single one", "never")) {
                val game = at(q)
                game.answer(no)
                assertEquals("$no at $q", 10_000_000L, state(game).us!!.balance)
                assertEquals("$no at $q", "ENVIRONMENT_PROMPT", state(game).q.name)
            }
            for (many in listOf("one hundred", "a hundred", "two thousand")) {
                val game = at(q)
                val turn = game.answer(many)
                assertEquals("$many at $q", 10_000_000L, state(game).us!!.balance)
                assertTrue("$many at $q: ${said(turn)}", Lines.affordUpTo(3) in said(turn))
            }
            val game = at(q)
            game.answer("twenty-two")
            assertEquals("twenty-two at $q", 10_000_000L, state(game).us!!.balance)
            game.answer("two")
            assertEquals(2, state(game).us!!.bombs)
        }
    }

    @Test
    fun aYesWordWithNotIsANo() {
        // fixed: "absolutely not", "of course not" and "I do not" were a yes
        for (no in listOf("absolutely not", "of course not", "I do not", "definitely not", "not at all")) {
            val game = at(Q.NUCLEAR_PROMPT) { it.us!!.tech = false }
            game.answer(no)
            assertFalse(no, state(game).us!!.tech)
        }
    }

    @Test
    fun notSureIsNeitherYesNorNo() {
        // fixed: "I'm not sure" was a yes ("sure") and "I don't know" a no ("i don't"): the question is asked again
        for (unsure in listOf("I'm not sure", "I don't know")) {
            val game = at(Q.NUCLEAR_PROMPT) { it.us!!.tech = false }
            assertTrue(unsure, game.understands(unsure))     // heard, so the app doesn't swap it for "I'm sure"
            assertEquals(unsure, "NUCLEAR_PROMPT", game.answer(unsure).node)
        }
    }

    @Test
    fun usIsTheUsa() {
        // fixed: "US" and "U.S." weren't understood
        for (us in listOf("US", "U.S.", "the U.S.", "us")) {
            val game = NuclearWar(quiet, Random(1))
            game.start()
            assertEquals(us, "COUNTRY_SELECT", game.answer(us).node)
            assertEquals(us, "USA", state(game).us!!.ref)
        }
        // "us" in a sentence is the pronoun: still a yes
        val game = at(Q.NUCLEAR_PROMPT) { it.us!!.tech = false }
        assertEquals("ENVIRONMENT_PROMPT", game.answer("yes, tell us").node)
    }

    @Test
    fun theLastCityLeftIsAskedWithYesAndNo() {
        // fixed: "Would you like to attack Wuhan?" had only [Wuhan], and no way to say no
        val game = at(Q.USE_BOMBS) { st ->
            st.us!!.bombs = 1
            st.countries.first { it.ref == "China" }.cities.take(2).forEach { it.destroyed = true }
        }
        val turn = game.answer("china")
        assertEquals("CHOOSE_BOMB_CITY", turn.node)
        assertEquals(listOf("yes", "no"), turn.ask!!.buttons.map { it.value })
        assertEquals("CONFIRM_BOMB_PROMPT", game.answer("no").node)
    }

    @Test
    fun researchIsOfferedWithExactlyItsCost() {
        // fixed: with exactly 2 million after the environment, the cities were skipped
        val game = at(Q.ENVIRONMENT_PROMPT) { it.us!!.balance = 2_000_000 }
        assertEquals("CITY_PROMPT", game.answer("no").node)
        val bought = at(Q.ENVIRONMENT_PROMPT) { it.us!!.balance = 3_000_000 }
        assertEquals("CITY_PROMPT", bought.answer("yes").node)
    }

    @Test
    fun theMoneyLeftIsSaidOnceAfterResearch() {
        // fixed: "You have 2 million left." was said twice
        val game = at(Q.RESEARCH_PROMPT) { it.us!!.balance = 4_000_000 }
        val turn = game.answer("yes")
        assertEquals(said(turn).toString(), 1, said(turn).count { it == Lines.YOU_HAVE })
        assertEquals("RESEARCH_PROMPT", turn.node)      // the next city's
    }

    @Test
    fun theEnvironmentTipIsSaidOnlyWhenItsAmountIsRight() {
        // fixed: "an extra 500K" was said at 115 percent too (1.5 million)
        fun envTurn(tech: String): Turn {
            val game = NuclearWar(quiet, Random(1))
            game.start()
            game.answer("france")
            game.answer("no")
            game.answer(tech)
            return game.answer("yes")
        }
        assertTrue(Lines.ENV_EXTRA in said(envTurn("yes")))
        assertFalse(Lines.ENV_EXTRA in said(envTurn("no")))
    }

    @Test
    fun aCalmCountryAfterThreeAngryOnesStillCalls() {
        // fixed: three angry countries in a row skipped the fourth's call, and Don said no one was calling
        val game = at(Q.SANCTION) { st ->
            // (no money, so no country buys bombs and calms down by using them)
            st.countries.forEachIndexed { i, c -> c.attackUs = if (i < 3) 1 else 0; c.balance = 0 }
        }
        val turn = game.answer("no")
        assertTrue(said(turn).toString(), Lines.NO_CALLS.none { it in said(turn) })
        assertEquals("PHONE_COUNTRY", turn.node)
        assertEquals(3, state(game).countryIndex)
        // Three angry after one call: they're said, not "no one calls".
        val after = at(Q.PHONE_COUNTRY) { st ->
            st.countries.forEachIndexed { i, c -> c.attackUs = if (i > 0) 1 else 0 }
        }
        val answered = after.answer("yes")
        assertTrue(said(answered).toString(), Lines.NO_CALLS.none { it in said(answered) })
        val last = state(after).countries[3].ref
        assertTrue(said(answered).toString(), said(answered).any { it in Lines.singleNoTalk(last) })
    }

    @Test
    fun nextRoundAtACallStillDoesWhatTheCallsWould() {
        // fixed: "next round" skipped the calls' effects (no anger at being bombed, no sanctions kept)
        val game = at(Q.PHONE_COUNTRY) { st ->
            st.countries[0].sanctioned = true
            st.us!!.countriesBombed += st.countries[1].ref
        }
        val turn = game.answer("next round")
        assertFalse(turn.node == "PHONE_COUNTRY")
        val st = state(game)
        assertTrue(st.countries[0].stillSanctioned)
        assertEquals(1, st.countries[1].attackUs)
    }

    @Test
    fun theEnvironmentsCollapseEndsWithEveryCountryDestroyed() {
        // fixed: it ended "Your cities were destroyed", with no city hit
        val game = at(Q.SANCTION) { it.environment = -150 }
        val turn = game.answer("no")
        assertEquals("Every country was destroyed", turn.end?.title)
        assertTrue(Lines.EVERY_COUNTRY in said(turn))
    }

    @Test
    fun everyoneTiedIsJointFirst() {
        // fixed: a single tied group was "last" (no triumph), while the title said "joint first"
        val game = at(Q.SANCTION) { st ->
            st.round = 5
            st.countries = st.countries.take(1).toMutableList()
            for (n in st.countries + st.us!!) {
                n.balance = 0
                n.score = 30
                n.contributions = 0
            }
        }
        val turn = game.answer("no")
        assertEquals("You came joint first", turn.end?.title)
        assertTrue(said(turn).toString(), Lines.endTiePlacing("first") in said(turn))
    }
}
