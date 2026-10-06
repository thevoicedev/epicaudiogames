package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

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
            val bot = Bot(map).apply { explore() }
            val never = map.nodes.keys - bot.visited
            assertTrue("${map.id}: never reached ${never.sorted()}", never.isEmpty())
            val ends = map.nodes.values.filter { it.end != null }.map { it.id }.toSet()
            assertEquals("${map.id}: ends never reached", emptySet<String>(), ends - bot.ends)
            println("${map.id}: ${bot.states} states, ${bot.turns} turns, ${bot.visited.size} nodes, ${bot.ends.size} ends, ${bot.quits} ways out")
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

    /** Explores every state (node and variables) with every kind of answer, and every random branch. */
    private class Bot(val map: GameMap) {
        val visited = mutableSetOf<String>()
        val ends = mutableSetOf<String>()
        var quits = 0
        var states = 0
        var turns = 0

        fun explore(limit: Int = 100_000) {
            val seen = HashSet<Saved>()
            val queue = ArrayDeque<Saved>()
            fun record(s: Session, t: Turn) {
                turns++
                visited += t.visited
                when {
                    t.quit -> quits++
                    t.end != null -> {
                        ends += t.node
                        queue += s.save()
                    }
                    t.ask != null -> queue += s.save()
                    else -> fail("${map.id}: a turn at ${t.node} neither asks, ends nor quits")
                }
            }
            for (k in 0 until BRANCHES) {
                val s = Session(map) { n -> k % n }
                record(s, s.start())
            }
            while (queue.isNotEmpty()) {
                val state = queue.removeFirst()
                if (!seen.add(state)) continue
                if (seen.size > limit) fail("${map.id}: more than $limit states")
                states++
                if (state.ended) {
                    val end = map.node(state.node).end!!
                    if (end.kind == "chapter" && end.next in map.nodes) {
                        val s = Session(map).apply { restore(state) }
                        record(s, s.nextChapter())
                    }
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
