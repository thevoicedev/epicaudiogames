package com.epicaudiogames.engine.golden

import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Match
import com.epicaudiogames.engine.Saved
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.Turn
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import kotlin.random.Random

/**
 * MapsTest's random walk, copied (MapsTest itself is left as it is) and made deterministic: each walk has its own
 * seeded Random, shared by the bot and the session's choices. Unlike MapsTest's, it leaves and comes back every
 * [REOPEN] turns, comes back after quitting (where MapsTest stops), and with [entries] (the chapter ends that lead
 * into a pack) every odd walk starts at one of them, so the walks get into the packs' chapters. README section 8.1 is
 * this code in words.
 */
class MapWalker(private val map: GameMap, private val entries: List<String> = emptyList()) {
    /** Walk [w]: each turn's line to [emit] (and the turn to [onTurn]); returns how many lines. */
    fun walk(w: Int, onTurn: (Turn) -> Unit = {}, emit: (String) -> Unit): Int {
        val rng = Random(seed(w))
        val choose = LoggingChooser(rng)
        val lines = Canon.Turns()
        var s = Session(map, choose)
        var n = 0
        fun record(input: List<Any?>, t: Turn) {
            check(t)
            onTurn(t)
            emit(lines.line(n++, input, choose.take(), t, s.save()))
        }
        val entry = if (entries.isNotEmpty() && w % 2 == 1) entries[(w / 2) % entries.size] else null
        var t: Turn
        if (entry != null) {
            // Back at a saved chapter end, as when a pack has just been bought there.
            t = s.resume(Saved(entry, emptyMap(), true))
            record(listOf("resume", entry), t)
        } else {
            t = s.start()
            record(listOf("start"), t)
        }
        var last: String? = null
        for (i in 0 until TURNS) {
            val input: List<Any?>
            val end = t.end
            if (t.quit) {
                // Where MapsTest stops, the player comes back to the game: the app stores the save after a quit
                // too (GameController.kt finishTurn), so a "leave" picks up again and a plain quit starts again
                // with the map's "keep" variables.
                val saved = s.save()
                s = Session(map, choose)
                t = s.open(saved)
                input = listOf("return")
            } else if ((i + 1) % REOPEN == 0) {
                // Leave and come back: the game as the app opens it again (Session.open).
                val saved = s.save()
                s = Session(map, choose)
                t = s.open(saved)
                input = listOf("reopen")
            } else if (end != null) {
                if (end.kind == "chapter" && end.next in map.nodes) {
                    t = s.nextChapter()
                    input = listOf("next")
                } else {
                    val at = playAgainAt(end)
                    t = s.restart(at)
                    input = listOf("restart", at)
                }
            } else {
                val options = inputs(t.ask!!)
                val taken = options.drop(3).ifEmpty { options }     // inputs() lists silence, nonsense, repeat first
                val said = when {
                    w % 2 == 1 && last in options && rng.nextBoolean() -> last
                    rng.nextInt(4) > 0 -> taken[rng.nextInt(taken.size)]
                    else -> options[rng.nextInt(options.size)]
                }
                last = said
                t = if (said == null) s.silence() else s.answer(said)
                input = if (said == null) listOf("silence") else listOf("answer", said)
            }
            record(input, t)
        }
        return n
    }

    private fun check(t: Turn) {
        if (!t.quit && t.end == null && t.ask == null) throw IllegalStateException("${map.id}: a turn at ${t.node} neither asks, ends nor quits")
    }

    /** The end screen's "play again" (or "try again" at a game over with a retry point): restart's argument. */
    private fun playAgainAt(end: End): String? = if (end.kind == "gameover" && end.retry != null) end.retry else null

    /** One answer of each kind the question takes, its buttons, nonsense, "repeat" and silence (null). */
    fun inputs(ask: Ask): List<String?> {
        val out = mutableListOf<String?>(null, "zzz", map.words.repeat.first().text)
        out += ask.buttons.map { it.value }
        for (a in ask.answers) {
            out += when (val m = a.match) {
                is Match.Yes -> "yes"
                is Match.No -> "no"
                is Match.Words -> m.phrases.first().text
                Match.Repeat -> map.words.repeat.first().text
                is Match.Seq -> m.seq.map { c -> map.symbols.getValue(m.table).getValue(c.toString()).first() }.joinToString(" ")
                is Match.Digits -> m.digits.toList().joinToString(" ")
                is Match.Re -> continue
                Match.AnyText -> "something else entirely"
            }
        }
        return out.filter { it == null || it.isNotBlank() }.distinct()
    }

    companion object {
        const val TURNS = 80
        const val REOPEN = 25

        fun seed(w: Int) = w + 1
    }
}

/**
 * NuclearWarTest's player, copied: buttons, the extra words and silence, chosen by its own seeded Random; it leaves
 * and comes back once, at turn 37, with a new game on Random(seed + 37). README section 8.2.
 */
class NuclearPlayer(private val audio: NuclearAudio) {
    class Game(val lines: Int, val end: String)

    /** Game [seed]: each turn's line to [emit], and the save after it to [saves]. */
    fun game(seed: Int, saves: (Saved) -> Unit = {}, emit: (String) -> Unit): Game {
        var rnd = LoggingRandom(Random(seed))
        var game = NuclearWar(audio, rnd)
        val r = Random(seed * 7919 + 1)
        val lines = Canon.Turns(freshAsks = true)
        var t = game.start()
        fun record(n: Int, input: List<Any?>) {
            val saved = game.save()
            emit(lines.line(n, input, rnd.take(), t, saved))
            saves(saved)
        }
        record(0, listOf("start"))
        var n = 0
        var reopened = false
        while (t.end == null) {
            n++
            check(n < if (reopened) 900 else 600) { "game $seed went on for $n turns (at ${t.node})" }
            val ask = t.ask ?: throw IllegalStateException("game $seed: no question and no end at ${t.node}")
            check(ask.reprompt.isNotEmpty()) { "game $seed: no reprompt at ${t.node}" }
            val input: List<Any?>
            if (!reopened && n % 37 == 0) {
                // Leave and come back: the game is saved at every question.
                val saved = game.save()
                rnd = LoggingRandom(Random(seed + n))
                game = NuclearWar(audio, rnd)
                check(game.canResume(saved))
                t = game.open(saved)
                check(t.ask != null) { "game $seed: nothing to answer after picking up at ${saved.node}" }
                reopened = true
                input = listOf("reopen")
            } else {
                val buttons = ask.buttons
                val said: String? = when {
                    r.nextInt(20) == 0 -> null
                    buttons.isNotEmpty() && r.nextInt(10) < 7 -> buttons[r.nextInt(buttons.size)].value
                    else -> EXTRAS[r.nextInt(EXTRAS.size)]
                }
                t = if (said == null) game.silence() else game.answer(said)
                input = if (said == null) listOf("silence") else listOf("answer", said)
            }
            record(n, input)
        }
        return Game(n + 1, t.end!!.title)
    }

    companion object {
        val EXTRAS = listOf("yes", "no", "yeah", "nope", "shield", "research", "all of them", "next", "next round",
            "none", "3", "two", "twenty", "repeat", "banana", "france", "the uk", "america", "china", "russia", "paris",
            "new york", "moscow", "london", "shanghai", "st petersburg", "")
    }
}
