package com.epicaudiogames.engine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

// A game map, as described in docs/MAP_FORMAT.md. Variables hold Boolean, Double or String values.

class MapException(message: String) : Exception(message)

/** One spoken line of a clip's transcript: when it starts, how long it takes, who says it and what. */
data class Line(val at: Double, val len: Double, val who: String, val text: String, val words: List<Double>? = null)

sealed interface Step {
    /**
     * A clip of the game's audio (path relative to the game's content folder, without an extension). [sfx]: music or
     * sound effects, with no transcript.
     */
    data class Play(val path: String, val dur: Double, val lines: List<Line>, val sfx: Boolean = false) : Step

    /** A number variable, read out with the shared number clips. */
    data class Num(val variable: String) : Step

    data class Pause(val seconds: Double) : Step

    /**
     * A sound under the rest of the turn (music, or an effect that overlaps what follows): it starts here, plays
     * once at [volume] (0 to 1), and stops when the turn's audio ends. A [path] of null stops every bed.
     */
    data class Bed(val path: String?, val volume: Double, val dur: Double) : Step

    /** The steps play only when [cond] holds (when the turn is played). */
    data class When(val cond: Condition, val steps: List<Step>) : Step

    /** One of these step lists, at random. */
    data class Pick(val options: List<List<Step>>) : Step

    /** The steps for a variable's value ("10", "hide", "true"), or [otherwise]. */
    data class By(val variable: String, val cases: Map<String, List<Step>>, val otherwise: List<Step>) : Step
}

sealed interface Go {
    data class To(val node: String) : Go
    data class Random(val targets: List<Go>) : Go
    data class If(val cases: List<Pair<Condition, Go>>, val otherwise: Go) : Go
    data class Restart(val node: String) : Go
    data object Quit : Go

    /**
     * One of [nodes] that this [deck] hasn't drawn yet, at random; when all have been drawn, the deck starts again.
     * The deck's draws are kept in the variable "deck_<deck>".
     */
    data class Draw(val nodes: List<String>, val deck: String) : Go
}

sealed interface SetValue {
    data class Assign(val value: Any) : SetValue
    data class Add(val amount: Double) : SetValue
    data class Rand(val from: Int, val to: Int) : SetValue
    /** A computed value: "=streak * 10". */
    data class Calc(val expr: Expr) : SetValue
}

/** A phrase to listen for, normalised. An exact phrase ("=fine" in a map) must be the whole answer. */
data class Phrase(val text: String, val exact: Boolean)

sealed interface Match {
    data class Yes(val extra: List<Phrase>) : Match
    data class No(val extra: List<Phrase>) : Match
    data class Words(val phrases: List<Phrase>) : Match
    data object Repeat : Match
    data class Seq(val seq: String, val table: String, val exact: Boolean, val spelled: Boolean, val least: Int?) : Match
    data class Digits(val digits: String, val exact: Boolean, val least: Int?) : Match
    data class Re(val pattern: String) : Match {
        val regex = Regex(pattern)
    }
    data object AnyText : Match
}

data class Answer(
    val match: Match,
    val go: Go?,
    val set: Map<String, SetValue>,
    val whenCond: Condition?,
    val opposite: Int?,
    /** Answers of a higher rank are tried first (default 0). */
    val rank: Int = 0,
)

data class Button(val label: String, val value: String)

data class Else(val say: List<Step>, val set: Map<String, SetValue>, val go: Go?)

data class Ask(val reprompt: List<Step>, val answers: List<Answer>, val otherwise: Else?, val buttons: List<Button>)

data class End(val kind: String, val title: String, val next: String?, val retry: String?, val locked: String?)

data class Node(
    val id: String,
    val redirect: List<Pair<Condition, Go>>,
    val set: Map<String, SetValue>,
    val say: List<Step>,
    val ask: Ask?,
    val go: Go?,
    val end: End?,
)

/** [mixed]: answers made only of these yes words, no words and fillers count as their last yes or no word. */
data class Mixed(val yes: List<String>, val no: List<String>, val filler: List<String>)

data class WordLists(val yes: List<Phrase>, val no: List<Phrase>, val repeat: List<Phrase>, val mixed: Mixed? = null)

class GameMap(
    val id: String,
    val title: String,
    val start: String,
    val vars: Map<String, Any>,
    val keep: Set<String>,
    /** "repeat" at a question plays the node's say again (true) or its reprompt (false). */
    val repeatSays: Boolean,
    val who: Map<String, String>,
    val words: WordLists,
    /** Symbol tables for seq answers, in the map's order: symbol to the words that mean it. */
    val symbols: Map<String, Map<String, List<String>>>,
    val nodes: Map<String, Node>,
) {
    fun node(id: String): Node = nodes[id] ?: throw MapException("$id: no such node")

    companion object {
        fun load(file: File): GameMap = parse(file.readText())

        fun parse(text: String): GameMap = MapParser(Json.parseToJsonElement(text).jsonObject).map()

        private val DEFAULT_WORDS = mapOf(
            "yes" to listOf("yes", "yeah", "yep", "sure", "ok", "okay"),
            "no" to listOf("no", "nope", "nah"),
            "repeat" to listOf("repeat", "say that again", "say it again"),
        )
    }

    private class MapParser(val root: JsonObject) {
        fun map(): GameMap {
            if (root["format"]?.jsonPrimitive?.content != "1") throw MapException("format ${root["format"]}: only format 1 is supported")
            val words = root["words"]?.jsonObject
            fun list(name: String) = phrases(words?.get(name) ?: JsonArray(DEFAULT_WORDS.getValue(name).map { JsonPrimitive(it) }), name)
            val nodes = root.obj("nodes").mapValues { (id, n) -> node(id, n.jsonObject) }
            return GameMap(
                id = root.str("id"),
                title = root.str("title"),
                start = root.str("start"),
                vars = (root["vars"] as? JsonObject)?.mapValues { (k, v) -> value(v, "vars.$k") } ?: emptyMap(),
                keep = (root["keep"] as? JsonArray)?.map { it.jsonPrimitive.content }?.toSet() ?: emptySet(),
                repeatSays = when (val r = (root["repeat"] as? JsonPrimitive)?.content ?: "reprompt") {
                    "say" -> true
                    "reprompt" -> false
                    else -> throw MapException("repeat: $r isn't say or reprompt")
                },
                who = (root["who"] as? JsonObject)?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap(),
                words = WordLists(list("yes"), list("no"), list("repeat"), (words?.get("mixed") as? JsonObject)?.let { m ->
                    fun of(name: String) = (m[name] as? JsonArray)?.map { Text.normalise(it.jsonPrimitive.content) } ?: emptyList()
                    Mixed(of("yes"), of("no"), of("filler"))
                }),
                symbols = (root["symbols"] as? JsonObject)?.mapValues { (_, table) ->
                    table.jsonObject.mapValues { (_, ws) -> ws.jsonArray.map { Text.normalise(it.jsonPrimitive.content) } }
                } ?: emptyMap(),
                nodes = nodes,
            )
        }

        fun node(id: String, n: JsonObject): Node = Node(
            id = id,
            redirect = (n["redirect"] as? JsonArray)?.map { case(it.jsonObject, "$id redirect") } ?: emptyList(),
            set = sets(n["set"], id),
            say = steps(n["say"], id),
            ask = (n["ask"] as? JsonObject)?.let { ask(it, id) },
            go = n["go"]?.let { go(it, "$id go") },
            end = (n["end"] as? JsonObject)?.let { e ->
                End(
                    kind = e.str("kind"), title = e.str("title"), next = e.optStr("next"),
                    retry = e.optStr("retry"), locked = e.optStr("locked"),
                )
            },
        ).also {
            if (listOfNotNull(it.ask, it.go, it.end).size != 1) throw MapException("$id: needs exactly one of ask, go and end")
        }

        fun ask(a: JsonObject, id: String) = Ask(
            reprompt = steps(a["reprompt"], "$id reprompt"),
            answers = (a["answers"] as? JsonArray ?: throw MapException("$id: a question without answers"))
                .mapIndexed { i, ans -> answer(ans.jsonObject, "$id answer ${i + 1}") },
            otherwise = a["else"]?.let { e ->
                if (e is JsonObject) Else(steps(e["say"], "$id else"), sets(e["set"], "$id else"), e["go"]?.let { go(it, "$id else") })
                else Else(emptyList(), emptyMap(), go(e, "$id else"))
            },
            buttons = (a["buttons"] as? JsonArray)?.map { b ->
                val o = b.jsonObject
                Button(o.str("label"), o.optStr("value") ?: o.str("label"))
            } ?: emptyList(),
        )

        fun answer(a: JsonObject, where: String): Answer {
            fun flag(name: String) = (a[name] as? JsonPrimitive)?.booleanOrNull == true
            val extra = a["words"]?.let { phrases(it, where) } ?: emptyList()
            val matches = buildList {
                if (flag("yes")) add(Match.Yes(extra))
                if (flag("no")) add(Match.No(extra))
                if (!flag("yes") && !flag("no") && a["words"] != null) add(Match.Words(extra))
                if (flag("repeat")) add(Match.Repeat)
                val least = (a["least"] as? JsonPrimitive)?.content?.toInt()
                a.optStr("seq")?.let {
                    val table = a.optStr("symbols") ?: throw MapException("$where: seq without symbols")
                    add(Match.Seq(it, table, flag("exact"), flag("spelled"), least))
                }
                a.optStr("digits")?.let { add(Match.Digits(it, flag("exact"), least)) }
                a.optStr("re")?.let { add(Match.Re(it)) }
                if (flag("any")) add(Match.AnyText)
            }
            if (matches.size != 1) throw MapException("$where: needs exactly one way to match")
            return Answer(
                match = matches[0],
                go = a["go"]?.let { go(it, where) },
                set = sets(a["set"], where),
                whenCond = a.optStr("when")?.let { Condition.parse(it) },
                opposite = (a["opposite"] as? JsonPrimitive)?.content?.toInt(),
                rank = (a["rank"] as? JsonPrimitive)?.content?.toInt() ?: 0,
            )
        }

        fun go(e: JsonElement, where: String): Go = when {
            e is JsonPrimitive && e.isString -> Go.To(e.content)
            e is JsonObject && "random" in e -> Go.Random(e.getValue("random").jsonArray.map { go(it, where) })
            e is JsonObject && "if" in e -> Go.If(
                e.getValue("if").jsonArray.map { case(it.jsonObject, where) },
                go(e["else"] ?: throw MapException("$where: an if without an else"), where),
            )
            e is JsonObject && "restart" in e -> Go.Restart(e.str("restart"))
            e is JsonObject && "draw" in e -> Go.Draw(e.getValue("draw").jsonArray.map { it.jsonPrimitive.content },
                e.optStr("deck") ?: throw MapException("$where: a draw without a deck"))
            e is JsonObject && e.optStr("end") == "quit" -> Go.Quit
            else -> throw MapException("$where: can't read the go $e")
        }

        fun case(c: JsonObject, where: String) =
            Condition.parse(c.str("when")) to go(c["go"] ?: throw MapException("$where: a case without a go"), where)

        fun steps(e: JsonElement?, where: String): List<Step> = (e as? JsonArray)?.map { step(it.jsonObject, where) } ?: emptyList()

        fun step(o: JsonObject, where: String): Step {
            o.optStr("when")?.let { cond ->
                return Step.When(Condition.parse(cond), listOf(step(JsonObject(o - "when"), where)))
            }
            return when {
                "play" in o -> Step.Play(
                    path = o.str("play"),
                    dur = o.num("dur"),
                    lines = (o["lines"] as? JsonArray)?.map { l ->
                        val lo = l.jsonObject
                        Line(
                            at = lo.num("at"), len = (lo["len"] as? JsonPrimitive)?.doubleOrNull ?: 0.0,
                            who = lo.str("who"), text = lo.str("text"),
                            words = (lo["w"] as? JsonArray)?.map { it.jsonPrimitive.content.toDouble() },
                        )
                    } ?: emptyList(),
                    sfx = (o["sfx"] as? JsonPrimitive)?.booleanOrNull == true,
                )
                "bed" in o -> Step.Bed(
                    path = (o["bed"] as? JsonPrimitive)?.takeIf { it.isString }?.content,
                    volume = (o["volume"] as? JsonPrimitive)?.doubleOrNull ?: 1.0,
                    dur = (o["dur"] as? JsonPrimitive)?.doubleOrNull ?: 0.0,
                )
                "pick" in o -> Step.Pick(o.getValue("pick").jsonArray.map { steps(it, "$where pick") })
                "by" in o -> Step.By(
                    variable = o.str("by"),
                    cases = (o["cases"] as? JsonObject)?.mapValues { (_, v) -> steps(v, "$where by") } ?: emptyMap(),
                    otherwise = steps(o["else"], "$where by else"),
                )
                "num" in o -> Step.Num(o.str("num"))
                "pause" in o -> Step.Pause(o.num("pause"))
                else -> throw MapException("$where: unknown step $o")
            }
        }

        fun sets(e: JsonElement?, where: String): Map<String, SetValue> =
            (e as? JsonObject)?.mapValues { (name, v) -> setValue(v, "$where set $name") } ?: emptyMap()

        fun setValue(v: JsonElement, where: String): SetValue {
            val p = v as? JsonPrimitive ?: throw MapException("$where: not a value")
            if (p.isString) {
                if (p.content.startsWith("=")) return SetValue.Calc(Expr.parse(p.content.substring(1)))
                ADD.matchEntire(p.content)?.let { return SetValue.Add(p.content.toDouble()) }
                RAND.matchEntire(p.content)?.let { return SetValue.Rand(it.groupValues[1].toInt(), it.groupValues[2].toInt()) }
            }
            return SetValue.Assign(value(p, where))
        }

        fun value(v: JsonElement, where: String): Any {
            val p = v as? JsonPrimitive ?: throw MapException("$where: not a value")
            if (p.isString) return p.content
            return p.booleanOrNull ?: p.doubleOrNull ?: throw MapException("$where: can't read $p")
        }

        fun phrases(e: JsonElement, where: String): List<Phrase> =
            (e as? JsonArray ?: throw MapException("$where: expected a list of phrases")).map {
                val raw = it.jsonPrimitive.content
                val exact = raw.startsWith("=")
                Phrase(Text.normalise(if (exact) raw.substring(1) else raw), exact)
            }.filter { it.text.isNotEmpty() }

        fun JsonObject.str(key: String): String =
            (this[key] as? JsonPrimitive)?.content ?: throw MapException("missing \"$key\" in ${toString().take(120)}")

        fun JsonObject.optStr(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

        fun JsonObject.num(key: String): Double =
            (this[key] as? JsonPrimitive)?.doubleOrNull ?: throw MapException("missing number \"$key\" in ${toString().take(120)}")

        fun JsonObject.obj(key: String): JsonObject = this[key] as? JsonObject ?: throw MapException("missing \"$key\"")

        companion object {
            val ADD = Regex("""[+-]\d+(\.\d+)?""")
            val RAND = Regex("""rand\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)""")
        }
    }
}
