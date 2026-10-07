package com.epicaudiogames.engine.golden

import com.epicaudiogames.engine.Answer
import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.Else
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Go
import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.Match
import com.epicaudiogames.engine.Node
import com.epicaudiogames.engine.Phrase
import com.epicaudiogames.engine.Saved
import com.epicaudiogames.engine.SetValue
import com.epicaudiogames.engine.Step
import com.epicaudiogames.engine.Turn
import java.io.File
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.floor

/**
 * The fixtures' canonical encoding (fixtures/engine/README.md, sections 2 to 7): compact JSON with a fixed key order,
 * doubles never as float text, FNV-1a hashes, and the canonical forms of maps and turns. Swift's Canon must match it
 * byte for byte.
 */
object Canon {
    const val FORMAT = 1

    /** Text that is already canonical JSON, written as it is. */
    class Raw(val text: String)

    // ----- JSON -----

    /** The canonical JSON of a value: null, String, Boolean, Int, Long, Double, Raw, List, or Map (in its order). */
    fun json(v: Any?): String = StringBuilder().also { write(it, v) }.toString()

    fun write(sb: StringBuilder, v: Any?) {
        when (v) {
            null -> sb.append("null")
            is String -> quote(sb, v)
            is Boolean -> sb.append(if (v) "true" else "false")
            is Int -> sb.append(v)
            is Long -> {
                require(abs(v) < TWO_53) { "integer $v too big for the fixtures" }
                sb.append(v)
            }
            is Double -> double(sb, v)
            is Raw -> sb.append(v.text)
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { i, e ->
                    if (i > 0) sb.append(',')
                    write(sb, e)
                }
                sb.append(']')
            }
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, e) in v) {
                    if (!first) sb.append(',')
                    first = false
                    quote(sb, k as String)
                    sb.append(':')
                    write(sb, e)
                }
                sb.append('}')
            }
            else -> throw IllegalArgumentException("can't write a ${v::class.simpleName} in a fixture")
        }
    }

    /** `"`, `\` and controls escaped (controls as \u00xx, lowercase); everything else as itself. */
    fun quote(sb: StringBuilder, s: String) {
        sb.append('"')
        for (i in s.indices) {
            val c = s[i]
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c < ' ' -> sb.append("\\u00").append(HEX[c.code shr 4]).append(HEX[c.code and 15])
                c.isHighSurrogate() -> {
                    require(i + 1 < s.length && s[i + 1].isLowSurrogate()) { "an unpaired surrogate in ${s.take(80)}" }
                    sb.append(c)
                }
                c.isLowSurrogate() -> {
                    require(i > 0 && s[i - 1].isHighSurrogate()) { "an unpaired surrogate in ${s.take(80)}" }
                    sb.append(c)
                }
                else -> sb.append(c)
            }
        }
        sb.append('"')
    }

    /** A whole double as an integer; anything else as "x" and its IEEE bits (every NaN as the canonical NaN). */
    fun double(sb: StringBuilder, d: Double) {
        if (d.isFinite() && d == floor(d) && abs(d) < TWO_53 && !(d == 0.0 && 1.0 / d < 0)) {
            sb.append(d.toLong())
        } else {
            sb.append("\"x").append(hex(java.lang.Double.doubleToLongBits(d))).append('"')
        }
    }

    private const val TWO_53 = 9007199254740992L
    private val HEX = "0123456789abcdef".toCharArray()

    // ----- Hashes -----

    const val FNV_START = -3750763034362895579L     // 0xcbf29ce484222325

    /** 64-bit FNV-1a over the UTF-16 code units, carried on from [h]. */
    fun fnv(s: String, h: Long = FNV_START): Long {
        var x = h
        for (ch in s) x = (x xor ch.code.toLong()) * 1099511628211L
        return x
    }

    fun hex(h: Long): String = java.lang.Long.toHexString(h).padStart(16, '0')

    /** The hash of a value: FNV-1a of its canonical JSON, as 16 hex digits. */
    fun hash(v: Any?): String = hex(fnv(json(v)))

    /** SHA-256 of the files under [dir] ending in [ext], as README section 4 defines it. */
    fun treeSha256(dir: File, ext: String): String {
        val files = mutableListOf<Pair<String, File>>()
        fun walk(d: File, prefix: String) {
            for (f in d.listFiles().orEmpty()) {
                if (f.name.startsWith(".")) continue
                if (f.isDirectory) walk(f, "$prefix${f.name}/")
                else if (f.isFile && f.name.endsWith(ext)) files += "$prefix${f.name}" to f
            }
        }
        walk(dir, "")
        require(files.isNotEmpty()) { "no $ext files in $dir" }
        val sha = MessageDigest.getInstance("SHA-256")
        for ((path, f) in files.sortedBy { it.first }) {
            val bytes = f.readBytes()
            sha.update(path.toByteArray(Charsets.UTF_8))
            sha.update(0)
            sha.update(bytes.size.toString().toByteArray(Charsets.US_ASCII))
            sha.update(0)
            sha.update(bytes)
        }
        return sha.digest().joinToString("") { "%02x".format(it) }
    }

    // ----- Values -----

    /** A variable's value: ["n", double], ["b", bool], ["s", text]; null when missing. */
    fun value(v: Any?): Any? = when (v) {
        null -> null
        is Double -> listOf("n", v)
        is Boolean -> listOf("b", v)
        is String -> listOf("s", v)
        else -> throw IllegalArgumentException("a variable holds a ${v::class.simpleName}: $v")
    }

    fun vars(vars: Map<String, Any?>): List<Any?> = vars.entries.map { (k, v) -> listOf(k, value(v)) }

    // ----- The map -----

    fun line(l: Line): List<Any?> = listOf(l.at, l.len, l.who, l.text, l.words, l.more)

    fun clip(p: Step.Play): List<Any?> = listOf(p.path, p.dur, p.sfx, p.lines.map(::line))

    private val clipHashes = HashMap<Step.Play, String>()

    fun clipHash(p: Step.Play): String = clipHashes.getOrPut(p) { hash(clip(p)) }

    fun step(s: Step): List<Any?> = when (s) {
        is Step.Play -> listOf("p", s.path, s.lines.joinToString("") { if (it.more) "1" else "0" }, clipHash(s))
        is Step.Num -> listOf("n", s.variable)
        is Step.Pause -> listOf("z", s.seconds)
        is Step.Bed -> listOf("b", s.path, s.volume, s.dur)
        is Step.When -> listOf("w", s.cond.source, steps(s.steps))
        is Step.Pick -> listOf("k", s.options.map(::steps))
        is Step.By -> listOf("y", s.variable, s.cases.entries.map { (k, v) -> listOf(k, steps(v)) }, steps(s.otherwise))
    }

    fun steps(list: List<Step>): List<Any?> = list.map(::step)

    fun go(g: Go?): List<Any?>? = when (g) {
        null -> null
        is Go.To -> listOf("to", g.node)
        is Go.Random -> listOf("random", g.targets.map(::go))
        is Go.If -> listOf("if", g.cases.map { (c, to) -> listOf(c.source, go(to)) }, go(g.otherwise))
        is Go.Restart -> listOf("restart", g.node)
        Go.Quit -> listOf("quit")
        Go.Leave -> listOf("leave")
        is Go.Draw -> listOf("draw", g.nodes, g.deck)
    }

    fun sets(set: Map<String, SetValue>): List<Any?> = set.entries.map { (k, v) ->
        listOf(k, when (v) {
            is SetValue.Assign -> listOf("=", value(v.value))
            is SetValue.Add -> listOf("+", v.amount)
            is SetValue.Rand -> listOf("rand", v.from, v.to)
            is SetValue.Calc -> listOf("calc", v.expr.source)
        })
    }

    fun phrase(p: Phrase): List<Any?> = listOf(p.text, p.exact)

    fun match(m: Match): List<Any?> = when (m) {
        is Match.Yes -> listOf("yes", m.extra.map(::phrase))
        is Match.No -> listOf("no", m.extra.map(::phrase))
        is Match.Words -> listOf("words", m.phrases.map(::phrase))
        Match.Repeat -> listOf("repeat")
        is Match.Seq -> listOf("seq", m.seq, m.table, m.exact, m.spelled, m.least)
        is Match.Digits -> listOf("digits", m.digits, m.exact, m.least)
        is Match.Re -> listOf("re", m.pattern)
        Match.AnyText -> listOf("any")
    }

    fun answer(a: Answer): List<Any?> = listOf(match(a.match), go(a.go), sets(a.set), a.whenCond?.source, a.opposite, a.rank)

    fun otherwise(e: Else?): List<Any?>? = e?.let { listOf(steps(it.say), sets(it.set), go(it.go)) }

    fun ask(a: Ask?): List<Any?>? = a?.let {
        listOf(steps(it.reprompt), it.answers.map(::answer), otherwise(it.otherwise), it.buttons.map { b -> listOf(b.label, b.value) })
    }

    fun end(e: End?): List<Any?>? = e?.let { listOf(it.kind, it.title, it.next, it.retry, it.locked) }

    fun node(n: Node): List<Any?> = listOf(
        n.id,
        n.redirect.map { (c, g) -> listOf(c.source, go(g)) },
        sets(n.set),
        steps(n.say),
        ask(n.ask),
        go(n.go),
        end(n.end),
    )

    fun mapHeader(m: GameMap): Map<String, Any?> = linkedMapOf(
        "id" to m.id,
        "title" to m.title,
        "start" to m.start,
        "vars" to vars(m.vars),
        "keep" to m.keep.toList(),
        "repeatSays" to m.repeatSays,
        "who" to m.who.entries.map { listOf(it.key, it.value) },
        "words" to linkedMapOf(
            "yes" to m.words.yes.map(::phrase),
            "no" to m.words.no.map(::phrase),
            "repeat" to m.words.repeat.map(::phrase),
            "mixed" to m.words.mixed?.let { linkedMapOf("yes" to it.yes, "no" to it.no, "filler" to it.filler) },
        ),
        "symbols" to m.symbols.entries.map { (t, table) -> listOf(t, table.entries.map { listOf(it.key, it.value) }) },
    )

    fun map(m: GameMap): List<Any?> = listOf(mapHeader(m), m.nodes.values.map(::node))

    // ----- Turns -----

    private val askHashes = java.util.IdentityHashMap<Ask, String>()

    /** The hash of an Ask's answers and else (its buttons and reprompt are written out). */
    fun askHash(a: Ask): String = askHashes.getOrPut(a) { hash(listOf(a.answers.map(::answer), otherwise(a.otherwise))) }

    private val freshAskHashes = HashMap<Pair<List<Answer>, Else?>, String>()

    /** An Ask made afresh every turn (Nuclear War's): cached by its answers' value, not its identity. */
    fun freshAskHash(a: Ask): String =
        freshAskHashes.getOrPut(a.answers to a.otherwise) { hash(listOf(a.answers.map(::answer), otherwise(a.otherwise))) }

    /** Turn lines of one walk or game: each line's save delta is against the line before. */
    class Turns(private val freshAsks: Boolean = false) {
        private var prev: Map<String, Any?> = emptyMap()

        fun line(t: Int, input: List<Any?>, rng: List<Any?>, turn: Turn, saved: Saved): String {
            val ask = turn.ask
            val o = linkedMapOf<String, Any?>(
                "t" to t,
                "in" to input,
                "rng" to rng,
                "node" to turn.node,
                "visited" to turn.visited,
                "quit" to turn.quit,
                "keep" to turn.keep,
                "end" to end(turn.end),
                "heard" to turn.heard?.let { listOf(it.said, it.answer, it.how) },
                "steps" to steps(turn.steps),
                "ask" to ask?.let {
                    linkedMapOf(
                        "b" to it.buttons.map { b -> listOf(b.label, b.value) },
                        "r" to steps(it.reprompt),
                        "a" to if (freshAsks) freshAskHash(it) else askHash(it),
                    )
                },
                "save" to linkedMapOf(
                    "node" to saved.node,
                    "ended" to saved.ended,
                    "vars" to hash(vars(saved.vars)),
                    "delta" to delta(prev, saved.vars),
                ),
            )
            prev = LinkedHashMap(saved.vars)
            return json(o)
        }
    }

    /** What changed: new or different values in the current order, then the gone ones (null) in the old order. */
    fun delta(prev: Map<String, Any?>, cur: Map<String, Any?>): List<Any?> {
        val out = mutableListOf<Any?>()
        // Boxed equality is the canonical one: java.lang.Double.equals compares doubleToLongBits (every NaN equal,
        // -0.0 and 0.0 not), and values of different types never equal.
        for ((k, v) in cur) {
            if (!prev.containsKey(k) || prev[k] != v) out.add(listOf(k, value(v)))
        }
        for (k in prev.keys) if (!cur.containsKey(k)) out.add(listOf(k, null))
        return out
    }

    // ----- JDK 17's Double.toString -----

    /**
     * Whether JDK 17's Double.toString has the shortest digits that read back as [d] (JDK-4511638: it doesn't
     * always). Swift's Kt.doubleString is Java's layout over the shortest digits, so values that fail are kept out.
     */
    fun javaTextIsShortest(d: Double): Boolean {
        if (!d.isFinite() || d == 0.0) return true
        return javaDigits(d.toString()) == shortestDigits(d)
    }

    private val shortest = HashMap<Double, String>()

    private fun shortestDigits(d: Double): String = shortest.getOrPut(d) {
        val exact = BigDecimal(d)
        for (p in 1..17) {
            val r = exact.round(MathContext(p, RoundingMode.HALF_EVEN))
            if (r.toDouble() == d) return@getOrPut r.unscaledValue().abs().toString().trimEnd('0')
        }
        throw IllegalStateException("no shortest digits for $d")
    }

    private fun javaDigits(s: String): String =
        s.removePrefix("-").substringBefore('E').replace(".", "").trimStart('0').trimEnd('0')

    private val JAVA_DOUBLE = Regex("""-?\d+\.\d+(?:E-?\d+)?""")

    /** Whether every Java double text inside [s] ("a2.5", "1.0E-5") is JDK 17's shortest. */
    fun textIsShortest(s: String): Boolean = JAVA_DOUBLE.findAll(s).all { m ->
        val d = m.value.toDouble()
        d.toString() != m.value || javaTextIsShortest(d)
    }

    // ----- Files -----

    /** The header every fixture starts with (README section 4). */
    fun header(gamesSha: String, engineSha: String): LinkedHashMap<String, Any?> =
        linkedMapOf("format" to FORMAT, "games_sha256" to gamesSha, "engine_sha256" to engineSha)

    /**
     * A .json fixture: one object whose array fields named in [spread] have a newline before each element (for
     * readable diffs); everything else compact.
     */
    fun jsonFile(fields: Map<String, Any?>, spread: Set<String>): String {
        val sb = StringBuilder("{")
        var first = true
        for ((k, v) in fields) {
            if (!first) sb.append(',')
            first = false
            quote(sb, k)
            sb.append(':')
            if (k in spread && v is List<*> && v.isNotEmpty()) {
                sb.append('[')
                v.forEachIndexed { i, e ->
                    if (i > 0) sb.append(',')
                    sb.append('\n')
                    write(sb, e)
                }
                sb.append("\n]")
            } else {
                write(sb, v)
            }
        }
        return sb.append("}\n").toString()
    }
}
