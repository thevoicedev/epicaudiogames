package com.epicaudiogames.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import kotlin.random.Random

/**
 * Every map in games/, on its own and with its packs (games/<id>/packs/): loads, and a bot that tries every answer
 * in every state reaches every node and every end.
 */
class MapsTest {
    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")

    /** Each game's free map, and the game with all its packs merged in, by a name for the messages. */
    private fun named(): List<Pair<String, GameMap>> {
        val dirs = gamesDir.listFiles().orEmpty().filter { File(it, "map.json").isFile }.sortedBy { it.name }
        assertTrue("no maps in ${gamesDir.absolutePath}", dirs.isNotEmpty())
        return dirs.flatMap { dir ->
            val map = File(dir, "map.json")
            val packs = File(dir, "packs").listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }
            listOf(dir.name to GameMap.load(map)) +
                (if (packs.isEmpty()) emptyList() else listOf("${dir.name} + packs" to GameMap.load(map, packs)))
        }
    }

    private fun maps() = named().map { it.second }

    @Test
    fun botReachesEveryNodeAndEnd() {
        for ((name, map) in named()) {
            val bot = Bot(map).apply {
                explore()
                walk(Random(7), 3000)
            }
            val never = map.nodes.keys - bot.visited
            assertTrue("$name: never reached ${never.sorted()}", never.isEmpty())
            val ends = map.nodes.values.filter { it.end != null }.map { it.id }.toSet()
            assertEquals("$name: ends never reached", emptySet<String>(), ends - bot.ends)
            println("$name: ${bot.states} states${if (bot.capped) " (capped)" else ""} and ${bot.walks} random walks, " +
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

        fun explore(limit: Int = minOf(60_000, 2_000_000 / maxOf(1, map.vars.size))) {
            // States are kept as a 64-bit hash of the node and variables (decks aside), and queued only when new, so
            // a big map's frontier fits in memory; a hash collision only skips a state.
            val seen = HashSet<Long>()
            val queue = ArrayDeque<Saved>()
            fun record(s: Session, t: Turn) {
                check(t)
                if (t.quit) return
                val state = s.save()
                if (seen.size >= limit) {
                    capped = true
                    return
                }
                if (seen.add(hash(state))) queue += state
            }
            for (choose in choosers()) {
                val s = Session(map, choose)
                record(s, s.start())
            }
            while (queue.isNotEmpty()) {
                val state = queue.removeFirst()
                states++
                if (state.ended) {
                    val end = map.node(state.node).end!!
                    val s = Session(map).apply { restore(state) }
                    record(s, if (end.kind == "chapter" && end.next in map.nodes) s.nextChapter() else playAgain(s, end))
                    continue
                }
                for (input in inputs(map.node(state.node).ask!!)) {
                    for (choose in choosers()) {
                        val s = Session(map, choose)
                        s.restore(state)
                        record(s, if (input == null) s.silence() else s.answer(input))
                    }
                }
            }
        }

        /**
         * Plays [count] games from the start with random answers and random draws. Three answers in four are ones
         * the question takes (the rest: silence, nonsense or "repeat"), so a game gets deep into a long story; and in
         * every other game, half the time the bot says what it said last, as players do ("next" through all the
         * villagers).
         */
        fun walk(rng: Random, count: Int, turnsEach: Int = 80) {
            repeat(count) { game ->
                walks++
                val s = Session(map) { n -> rng.nextInt(n) }
                var t = s.start()
                var last: String? = null
                check(t)
                for (i in 0 until turnsEach) {
                    if (t.quit) break
                    val end = t.end
                    if (end != null) {
                        t = if (end.kind == "chapter" && end.next in map.nodes) s.nextChapter() else playAgain(s, end)
                    } else {
                        val options = inputs(t.ask!!)
                        val taken = options.drop(3).ifEmpty { options }     // inputs() lists silence, nonsense, repeat first
                        val said = when {
                            game % 2 == 1 && last in options && rng.nextBoolean() -> last
                            rng.nextInt(4) > 0 -> taken[rng.nextInt(taken.size)]
                            else -> options[rng.nextInt(options.size)]
                        }
                        last = said
                        t = if (said == null) s.silence() else s.answer(said)
                    }
                    check(t)
                }
            }
        }

        /**
         * The random choices tried from each state: the first few options every time, and the lowest and highest in
         * turn (so a dice game can be lost again and again, as in Pirate Quest's empty coin pouch).
         */
        private fun choosers(): List<(Int) -> Int> {
            var i = 0
            return (0 until BRANCHES).map { k -> { n: Int -> k % n } } + { n: Int -> if (i++ % 2 == 0) 0 else n - 1 }
        }

        /** A 64-bit FNV-1a hash of a state: its node, whether it has ended, and its variables (decks aside). */
        private fun hash(s: Saved): Long {
            var h = -3750763034362895579L                      // 0xcbf29ce484222325
            fun mix(text: String) {
                for (ch in text) h = (h xor ch.code.toLong()) * 1099511628211L
            }
            mix(s.node)
            mix(if (s.ended) "|ended|" else "|")
            for ((k, v) in s.vars.toSortedMap()) if (!k.startsWith("deck_")) mix("$k=$v;")
            return h
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
