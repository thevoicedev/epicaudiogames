package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import kotlin.random.Random

/** Every map in games/: loads, and a bot that tries every answer in every state reaches every node and every end. */
class MapsTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")

    private fun maps(): List<GameMap> {
        val files = gamesDir.listFiles().orEmpty().map { File(it, "map.json") }.filter { it.isFile }.sortedBy { it.path }
        assertTrue("no maps in ${gamesDir.absolutePath}", files.isNotEmpty())
        return files.map { GameMap.load(it) }
    }

    @Test
    fun botReachesEveryNodeAndEnd() {
        for (map in maps()) {
            val bot = Bot(map).apply {
                explore()
                walk(Random(7), 3000)
            }
            val never = map.nodes.keys - bot.visited
            assertTrue("${map.id}: never reached ${never.sorted()}", never.isEmpty())
            val ends = map.nodes.values.filter { it.end != null }.map { it.id }.toSet()
            assertEquals("${map.id}: ends never reached", emptySet<String>(), ends - bot.ends)
            println("${map.id}: ${bot.states} states${if (bot.capped) " (capped)" else ""} and ${bot.walks} random walks, " +
                "${bot.turns} turns, ${bot.visited.size} nodes, ${bot.ends.size} ends, ${bot.quits} ways out")
        }
    }

    @Test
    fun yesAndNoButtonsAlwaysAnswer() {
        for (map in maps()) {
            for (n in map.nodes.values) {
                val ask = n.ask ?: continue
                val vars = map.vars + mapOf("tries" to 0.0)
                val results = ask.buttons.map { it.label to Matcher.match(map, ask, vars, it.value) }
                if (ask.buttons.map { it.value } == listOf("yes", "no")) {
                    for ((label, r) in results) assertNotNull("${map.id} ${n.id}: the $label button isn't understood (${r.how})", r.index)
                } else if (ask.buttons.isNotEmpty()) {
                    assertTrue("${map.id} ${n.id}: no button is understood", results.any { it.second.index != null })
                }
            }
        }
    }

    /**
     * Explores the states (node and variables, decks aside) with every kind of answer and the first random branches,
     * up to a limit; then random walks reach what that missed (questions drawn from big decks, long streaks).
     */
    private class Bot(val map: GameMap) {
        val visited = mutableSetOf<String>()
        val ends = mutableSetOf<String>()
        var quits = 0
        var states = 0
        var turns = 0
        var walks = 0
        var capped = false

        private fun check(t: Turn) {
            turns++
            visited += t.visited
            if (t.quit) quits++
            if (t.end != null) ends += t.node
            if (!t.quit && t.end == null && t.ask == null) fail("${map.id}: a turn at ${t.node} neither asks, ends nor quits")
        }

        fun explore(limit: Int = 60_000) {
            val seen = HashSet<Saved>()
            val queue = ArrayDeque<Saved>()
            fun record(s: Session, t: Turn) {
                check(t)
                if (!t.quit) queue += s.save()
            }
            for (k in 0 until BRANCHES) {
                val s = Session(map) { n -> k % n }
                record(s, s.start())
            }
            while (queue.isNotEmpty()) {
                val state = queue.removeFirst()
                if (!seen.add(state.copy(vars = state.vars.filterKeys { !it.startsWith("deck_") }))) continue
                if (seen.size > limit) {
                    capped = true
                    break
                }
                states++
                if (state.ended) {
                    val end = map.node(state.node).end!!
                    val s = Session(map).apply { restore(state) }
                    record(s, if (end.kind == "chapter" && end.next in map.nodes) s.nextChapter() else playAgain(s, end))
                    continue
                }
                for (input in inputs(map.node(state.node).ask!!)) {
                    for (k in 0 until BRANCHES) {
                        val s = Session(map) { n -> k % n }
                        s.restore(state)
                        record(s, if (input == null) s.silence() else s.answer(input))
                    }
                }
            }
        }

        /** Plays [count] games from the start with random answers (and silences) and random draws. */
        fun walk(rng: Random, count: Int, turnsEach: Int = 80) {
            repeat(count) {
                walks++
                val s = Session(map) { n -> rng.nextInt(n) }
                var t = s.start()
                check(t)
                for (i in 0 until turnsEach) {
                    if (t.quit) break
                    val end = t.end
                    if (end != null) {
                        t = if (end.kind == "chapter" && end.next in map.nodes) s.nextChapter() else playAgain(s, end)
                    } else {
                        val options = inputs(t.ask!!)
                        val said = options[rng.nextInt(options.size)]
                        t = if (said == null) s.silence() else s.answer(said)
                    }
                    check(t)
                }
            }
        }

        /** The end screen's "play again" (or "try again" at a game over with a retry point). */
        private fun playAgain(s: Session, end: End) = if (end.kind == "gameover" && end.retry != null) s.restart(end.retry) else s.restart()

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
            const val BRANCHES = 4
        }
    }
}
