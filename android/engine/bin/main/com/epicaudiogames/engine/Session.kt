package com.epicaudiogames.engine

import kotlin.random.Random

/**
 * What the app does after each call: play [steps] in order, then wait for an answer to [ask], show the end screen
 * for [end], or leave the game ([quit]; with [keep], the place is kept). [visited] lists the nodes this turn went
 * through.
 */
data class Turn(
    val steps: List<Step>,
    val ask: Ask?,
    val end: End?,
    val quit: Boolean,
    val node: String,
    val visited: List<String>,
    val heard: Heard? = null,
    val keep: Boolean = false,
)

/** How an answer was understood: the index of the answer taken (null: not understood) and why. */
data class Heard(val said: String, val answer: Int?, val how: String)

/** What the app saves to pick a game up again. */
data class Saved(val node: String, val vars: Map<String, Any>, val ended: Boolean)

/**
 * One play of a game. Start it with [start] (or [resume]), then pass each answer to [answer], or call [silence]
 * when the player says nothing. [choose] picks the index for a random go (tests use it to try every branch).
 */
class Session(
    val map: GameMap,
    private val choose: (Int) -> Int = { n -> Random.nextInt(n) },
) : Play {
    override val who: Map<String, String> get() = map.who

    var node: String = map.start
        private set
    val vars: MutableMap<String, Any> = map.vars.toMutableMap()
    var end: End? = null
        private set
    var quit: Boolean = false
        private set
    /** Left with the place kept (`{ "end": "leave" }`): the game is at the question it left from. */
    var keep: Boolean = false
        private set
    private var asked: String? = null

    /** The question waiting for an answer, if there is one. */
    override val ask: Ask? get() = if (end == null && !quit) map.nodes[node]?.ask else null

    override fun start(): Turn {
        end = null
        quit = false
        keep = false
        vars.clear()
        vars.putAll(map.vars)
        return play(Go.To(map.start))
    }

    /**
     * Back at a saved place: the end screen, or the node's say again and its question. A question whose node says
     * nothing itself (the turn before it did the talking) plays its reprompt.
     */
    override fun canResume(saved: Saved): Boolean = !saved.ended && map.nodes[saved.node]?.ask != null

    override fun resume(saved: Saved): Turn {
        val n = map.nodes[saved.node]
        if (n == null || (n.ask == null && n.end == null)) return start()
        restore(saved)
        if (saved.ended) return turn(emptyList(), emptyList())
        val again = resolve(n.say).ifEmpty { resolve(n.ask?.reprompt.orEmpty()) }
        return turn(again, listOf(n.id))
    }

    /** Puts the game at a saved place without playing anything. */
    fun restore(saved: Saved) {
        val n = map.node(saved.node)
        node = saved.node
        vars.clear()
        vars.putAll(map.vars)
        vars.putAll(saved.vars)
        end = if (saved.ended) n.end else null
        quit = false
        keep = false
    }

    override fun save() = Saved(node, vars.toMap(), end != null)

    override fun answer(said: String): Turn {
        val ask = this.ask ?: throw IllegalStateException("the game isn't waiting for an answer (at $node)")
        asked = node
        val result = Matcher.match(map, ask, vars, said)
        val heard = Heard(said, result.index, result.how)
        val out = mutableListOf<Step>()
        val visited = mutableListOf<String>()
        when {
            result.index != null -> {
                val a = ask.answers[result.index]
                apply(a.set)
                if (a.go != null) run(a.go, out, visited, 0) else otherwise(ask, out, visited)
            }
            result.repeat -> out += resolve(if (map.repeatSays) map.node(node).say else ask.reprompt)
            else -> otherwise(ask, out, visited)
        }
        return turn(out, visited, heard)
    }

    /** The player said nothing: the reprompt, and the same question again. */
    override fun silence(): Turn {
        val ask = this.ask ?: throw IllegalStateException("the game isn't waiting for an answer (at $node)")
        return turn(resolve(ask.reprompt), emptyList())
    }

    /** Starts again, at [at] (or the start), with the starting variables except the map's "keep". */
    override fun restart(at: String?): Turn = play(Go.Restart(at ?: map.start))

    /** After a chapter's end: its next chapter, with the variables kept. */
    override fun hasChapter(next: String): Boolean = next in map.nodes

    override fun understands(said: String): Boolean {
        val a = ask ?: return false
        return Matcher.match(map, a, vars, said).let { it.index != null || it.repeat }
    }

    override fun nextChapter(): Turn {
        val e = end ?: throw IllegalStateException("not at an end")
        val next = e.next ?: throw IllegalStateException("${e.title}: no next chapter")
        if (next !in map.nodes) throw IllegalStateException("$next isn't in this map (pack ${e.locked})")
        end = null
        return play(Go.To(next))
    }

    private fun play(go: Go): Turn {
        val out = mutableListOf<Step>()
        val visited = mutableListOf<String>()
        run(go, out, visited, 0)
        return turn(out, visited)
    }

    private fun turn(steps: List<Step>, visited: List<String>, heard: Heard? = null) =
        Turn(steps.toList(), ask, end, quit, node, visited.toList(), heard, keep)

    private fun otherwise(ask: Ask, out: MutableList<Step>, visited: MutableList<String>) {
        val e = ask.otherwise
        if (e == null) {
            out += resolve(ask.reprompt)
            return
        }
        apply(e.set)
        if (e.go != null) run(e.go, out, visited, 0) else out += resolve(e.say.ifEmpty { ask.reprompt })
    }

    private fun run(go: Go, out: MutableList<Step>, visited: MutableList<String>, hops: Int) {
        if (hops > 500) throw MapException("the game went round in a loop at $node")
        when (go) {
            is Go.To -> enter(go.node, out, visited, hops)
            is Go.Random -> run(go.targets[choose(go.targets.size).coerceIn(0, go.targets.size - 1)], out, visited, hops + 1)
            is Go.If -> run(go.cases.firstOrNull { it.first.test(vars) }?.second ?: go.otherwise, out, visited, hops + 1)
            is Go.Restart -> {
                val kept = map.keep.mapNotNull { k -> vars[k]?.let { k to it } }
                vars.clear()
                vars.putAll(map.vars)
                vars.putAll(kept)
                end = null
                quit = false
                keep = false
                enter(go.node, out, visited, hops)
            }
            Go.Quit -> quit = true
            Go.Leave -> {
                quit = true
                keep = true
                asked?.let { node = it }
            }
            is Go.Draw -> {
                val deck = "deck_${go.deck}"
                val drawn = (vars[deck] as? String).orEmpty().split(',').filter { it.isNotEmpty() }.toSet()
                val left = go.nodes.filter { it !in drawn }
                val (from, kept) = if (left.isEmpty()) go.nodes to emptySet() else left to drawn
                val pick = from[choose(from.size).coerceIn(0, from.size - 1)]
                vars[deck] = (kept + pick).joinToString(",")
                enter(pick, out, visited, hops + 1)
            }
        }
    }

    /** The steps as they play now: [Step.When], [Step.Pick] and [Step.By] resolved with the current variables. */
    fun resolve(steps: List<Step>): List<Step> = steps.flatMap { s ->
        when (s) {
            is Step.When -> if (s.cond.test(vars)) resolve(s.steps) else emptyList()
            is Step.Pick -> if (s.options.isEmpty()) emptyList()
                else resolve(s.options[choose(s.options.size).coerceIn(0, s.options.size - 1)])
            is Step.By -> resolve(s.cases[Expr.key(vars[s.variable])] ?: s.otherwise)
            else -> listOf(s)
        }
    }

    private fun enter(id: String, out: MutableList<Step>, visited: MutableList<String>, hops: Int) {
        val n = map.node(id)
        n.redirect.firstOrNull { it.first.test(vars) }?.let { return run(it.second, out, visited, hops + 1) }
        node = id
        visited += id
        apply(n.set)
        out += resolve(n.say)
        when {
            n.go != null -> run(n.go, out, visited, hops + 1)
            n.end != null -> end = n.end
        }
    }

    private fun apply(set: Map<String, SetValue>) {
        for ((name, v) in set) {
            vars[name] = when (v) {
                is SetValue.Assign -> v.value
                is SetValue.Add -> ((vars[name] as? Number)?.toDouble() ?: 0.0) + v.amount
                is SetValue.Rand -> (v.from + choose(v.to - v.from + 1).coerceIn(0, v.to - v.from)).toDouble()
                is SetValue.Calc -> v.expr.eval(vars) ?: 0.0
            }
        }
    }
}
