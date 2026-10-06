package com.epicaudiogames.engine

import com.epicaudiogames.engine.nuclear.Lines
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import com.epicaudiogames.engine.nuclear.World
import org.junit.Assert.assertEquals
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
}
