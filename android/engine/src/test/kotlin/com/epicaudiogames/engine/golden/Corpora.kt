package com.epicaudiogames.engine.golden

import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Match
import com.epicaudiogames.engine.Phrase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import kotlin.random.Random

/** The inputs the fixtures are made from: text, expressions, matcher inputs, broken maps, utterances, numbers. */
object Corpora {
    // ----- Text -----

    /** TextTest's inputs and the edge cases: overflowing numbers, apostrophes, accents, case mappings, controls. */
    val TEXT = listOf(
        "Don’t FOLLOW it!", "  C, A... C?  ", "?!", "four two two one one", "4 2 2 1 1", "four twenty-two eleven",
        "forty two thousand two hundred and eleven", "three one four", "to too won one", "ten", "one hundred",
        "a hundred", "no idea", "see a see", "c ac", "left, right, write, lift!", "don't follow it",
        "i really don't want to follow", "let's not hide", "follow it", "don't you want to go on and follow",
        "99999999999 thousand", "twenty to", "one's", "‘quoted’", "“double”", "`tick`", "café", "naïve", "Zoë",
        "İstanbul", "\u212Aelvin", "\u212B", "ǅ", "Straße", "ﬁne", "１２３", "٣", "Ⅻ", "😀 yes", "yes😀", "", " ", "\t\n",
        "STOP", "Stop!", "cancel.", "stop it", "pause", "a-b-c", "twenty-one", "ninety nine", "nineteen ninety nine",
        "one thousand", "thousand", "hundred thousand", "two hundred thousand and five", "9223372036854775807 hundred",
        "99999999999999999999 thousand", "99999999999999999999", "9223372036854775807 thousand thousand", "1 2 3",
        "007", "0", "oh oh seven", "fourty four", "for to won", "fore", "twenty twenty", "twenty one two", "eleventy",
        "1,000", "1.5", "-5", "+3", "3rd", "1st", "3 hundred", "three hundred and thirty three thousand", "a b c",
        "o'clock", "rock 'n' roll", "''", "'", "it's", "don't", "dont", "DON'T", "do n't", "Ü", "ÀÉÎÕÜ", "ΣΑΣ ΣΑΣ",
        "Привет", "你好", "\u0000x", "x\u001fy", "tab\there", "back\\slash", "quote\"d", "line\nbreak", "\u2028",
        "\u00a0nbsp\u00a0", "e\u0301", "zero zero zero", "oh", "twenty-two-eleven", "four hundred hundred",
        "thousand thousand", "one thousand thousand", "seventy seven thousand", "sixty six six", "thirty thirty",
        "forty zero", "ninety nine thousand nine hundred ninety nine",
        // "to", "for", "won" and "oh" are numbers only next to another number.
        "I want to play", "go for it", "I need to listen to it again", "oh yes I won", "won won to to for",
        "for to to one one", "one for", "to one", "one to", "four for", "two hundred to",
    )

    /** Every raw phrase, button label and value and symbol word in a map or pack file, in file order. */
    fun rawStrings(file: File): List<String> {
        val out = mutableListOf<String>()
        fun all(e: JsonElement) {
            when (e) {
                is JsonPrimitive -> if (e.isString) out += e.content
                is JsonArray -> e.forEach(::all)
                is JsonObject -> e.values.forEach(::all)
            }
        }
        fun walk(e: JsonElement) {
            when (e) {
                is JsonArray -> e.forEach(::walk)
                is JsonObject -> for ((k, v) in e) {
                    when (k) {
                        "words", "symbols" -> all(v)
                        "buttons" -> (v as? JsonArray)?.forEach { b ->
                            (b as? JsonObject)?.let { o -> listOf("label", "value").forEach { f -> (o[f] as? JsonPrimitive)?.let { all(it) } } }
                        }
                        else -> walk(v)
                    }
                }
                else -> Unit
            }
        }
        walk(Json.parseToJsonElement(file.readText()))
        return out
    }

    /** Texts to try a phrase in (Text.phraseLength, Text.longest, Text.negated). */
    fun phraseTexts(p: String): List<String> = listOf(
        p, "i think $p now", "${p}s", "not $p", "dont $p", "never $p", "don't really $p", "i don't really want $p",
        "don't a b c $p", "don't a b c d $p", "$p not", "i won't $p", "$p $p", "x$p", "notreally $p",
    )

    // ----- Expressions -----

    /** Hand-written expressions: operators, same(), comparisons, NaN and -0.0, whitespace oddities. */
    val EXPRS = listOf(
        "1 + 2 * 3", "(1 + 2) * 3", "7 % 4", "-7 % 4", "7 % -4", "-7 % -4", "7.5 % 2", "1 % 0", "0 % 0", "1 / 0",
        "-1 / 0", "0 / 0", "0.1 + 0.2", "1 / 3", "2 / 3", "10 / 4", "\"a\" + 1", "1 + \"a\"", "\"a\" + 0.5",
        "\"a\" + a", "a + b", "a + \"\"", "\"\" + 1.5 * 3", "\"x\" + 1 / 3", "\"x\" + 1 / 1000", "\"x\" + 100000000 * 100",
        "\"x\" + 0 / 0", "\"x\" + 1 / 0", "\"x\" + -0", "\"x\" + true", "\"x\" + missing",
        "\"10\" == 10", "10 == \"10\"", "true == 1", "false == 0", "a == \"\"", "a == false", "a == 0", "\"\" == a",
        "a == b", "a != b", "a == a", "\"b\" > \"a\"", "\"B\" < \"a\"", "\"é\" > \"z\"", "\"10\" < \"9\"", "\"10\" < 9",
        "true > false", "a < 1", "a <= b", "!a", "!!a", "-a", "--a", "- -a", "!0", "!\"\"", "!\"0\"", "a && b",
        "a || b", "a ? b : c", "a ? b : c ? d : e", "a && b || c", "a || b && c", "max(a, b)", "min(a, b)",
        "max(a, b, c)", "floor(a)", "floor(-2.5)", "floor(a, b)", "max(0 / 0, 1)", "max(1, 0 / 0)", "min(-0, 0)",
        "max(-0, 0)", "min(0, -0)", "floor(-0.5)", "-0", "0 * -1", "max(\"3\", 2)", "a % 3 == 1", "(a - 3) % 4",
        "a * 1", "a + 0", "a - 0", "1 - 1", "a / 1", "x1 + x2 + x3", "a\u00a0+ 1", "a\u2003+\u20031", "a\t+\n1",
        "  a  ", "\"tab\there\"", "a\u001c+1", "12345678901234567890", "0.1 * 3", "1.5", "007", "1.50", "2.5 * a",
        "a * 0.1", "100000000 * 100", "0.001 * a", "1 / 1000", "1 / 10000", "\"1e5\" * 1", "\" 2 \" * 1",
        "\"0x1p3\" * 1", "\"NaN\" * 1", "\"1d\" + 0", "-\"3\"", "a - \"2.5\"",
    )

    /** Expressions that don't parse (their MapException message). */
    val BAD_EXPRS = listOf(
        "a >> 2", "(a", "max(", "a +", "foo(1)", "a = 2", "1e3", "a ? b", "a ? b :", "", "   ", "é", "a # b", "max()",
        "floor()", "\"unterminated", "a b", "1..2", "a && && b", "()", ")", "a ! b", "1 2", "a\u00a0b", "max(1,)",
        "a ?: b", "!", "-", "a[0]", "a.b", "'x'", "a == = b", "tries >> 2", "1 +* 2", "max(1 2)", "(a))", "a ? : b",
        "true(1)", "_x(1)", "a\u001cb",
    )

    /** The `numbers` var set's values, given to the names in turn. */
    val NUMBERS = listOf(Double.NaN, -0.0, 1e7, Double.NEGATIVE_INFINITY, 2.5, 1e-5, 0.1)

    /** The `mixed` var set's values. */
    val MIXED = listOf<Any>(true, false, "", "abc", "12")

    /**
     * Every distinct `when` and computed value (`=…`) in a map or pack file: (kind, source), in a depth-first walk in
     * key order.
     */
    fun expressions(file: File, into: LinkedHashSet<Pair<String, String>>) {
        fun walk(e: JsonElement) {
            when (e) {
                is JsonArray -> e.forEach(::walk)
                is JsonObject -> for ((k, v) in e) {
                    if (k == "when" && v is JsonPrimitive && v.isString) into += "when" to v.content
                    if (k == "set" && v is JsonObject) {
                        for (x in v.values) if (x is JsonPrimitive && x.isString && x.content.startsWith("=")) into += "calc" to x.content.substring(1)
                    }
                    walk(v)
                }
                else -> Unit
            }
        }
        walk(Json.parseToJsonElement(file.readText()))
    }

    // ----- The matcher -----

    /** About 25 things to say to a question: buttons, the bot's inputs, other phrases and their variants. */
    fun matcherInputs(map: GameMap, ask: Ask, walkInputs: List<String?>): List<String> {
        val out = LinkedHashSet<String>()
        for (b in ask.buttons) {
            out += b.value
            out += b.label
        }
        walkInputs.forEach { if (it != null) out += it }
        out += listOf("", "yeah no", "no yes", "um yes", "Say that AGAIN?", "stop")
        fun more(list: List<Phrase>) = list.drop(1).take(2).forEach { out += it.text }
        for (a in ask.answers) {
            when (val m = a.match) {
                is Match.Yes -> {
                    out += "Yes!"
                    more(map.words.yes + m.extra)
                }
                is Match.No -> {
                    out += "NO."
                    more(map.words.no + m.extra)
                }
                is Match.Words -> {
                    more(m.phrases)
                    m.phrases.firstOrNull()?.let { p ->
                        out += "not ${p.text}"
                        out += "I don’t want to ${p.text}"
                        out += "${p.text.uppercase()}!"
                        out += "um ${p.text} please"
                    }
                }
                Match.Repeat -> more(map.words.repeat)
                is Match.Seq -> {
                    out += m.seq
                    val table = map.symbols[m.table]
                    if (table != null) out += m.seq.dropLast(1).map { c -> table[c.toString()]?.lastOrNull() ?: "" }.joinToString(" ")
                }
                is Match.Digits -> {
                    out += m.digits
                    out += m.digits.dropLast(1).toList().joinToString(" ")
                }
                is Match.Re, Match.AnyText -> Unit
            }
        }
        // Then always: unsure, a negated yes word, "to" that isn't a number, and a repeat with a number word in it.
        return (out.take(24) + listOf("I'm not sure", "of course not", "I want to play", "one more time")).distinct()
    }

    // ----- Nuclear War -----

    /** What players say to Nuclear War: the test's extras, buttons, names, numbers, mixed answers, commands. */
    val UTTERANCES = (NuclearPlayer.EXTRAS + listOf(
        "Answer", "Ignore", "the USA", "USA", "UK", "France", "China", "Russia", "All of them", "None", "1", "2",
        "Shield", "Research", "No", "Yes", "u s a", "the united states", "united states of america", "the us",
        "american", "united kingdom", "britain", "england", "french", "chinese", "russian", "Paris", "Marseille",
        "marseilles", "Lyon", "lyons", "leon", "New York City", "Los Angeles", "la", "Houston", "Edinburgh",
        "Cardiff", "Beijing", "Wuhan", "woohan", "Sochi", "saint petersburg", "petersburg", "St. Petersburg", "all",
        "all three", "every city", "all the cities", "shields", "build a shield", "do research", "skip", "continue",
        "play", "zero", "one", "four", "five bombs", "twenty two", "twenty-two", "fifty", "a couple", "99999999999",
        "2147483648", "-5", "0", "10", "100", "to", "for", "won", "no bombs", "yeah no", "no yes", "um yes", "uh no",
        "yes please", "no thanks", "not now", "never", "hang up", "answer it", "pick up", "of course", "i don't",
        "nothing", "pardon", "what", "say that again", "stop", "YES!", "  yes  ", "zzz", "bomb paris",
        "france and russia", "london paris", "not russia", "research shield",
        // The fixed answers: "us" for the USA, numbers said with "not" or a scale, negated and unsure yes words.
        "US", "U.S.", "us", "the U.S.", "yes, tell us", "not one", "I don't want one", "no, not a single one",
        "one hundred", "a hundred", "two thousand", "absolutely not", "definitely not", "of course not",
        "I'm not sure", "I don't know",
    )).distinct()

    // ----- Numbers -----

    /** Strings for String.toDoubleOrNull (the JVM's grammar). */
    val TO_DOUBLE = listOf(
        "1", "1.5", "-1.5", "+1.5", ".5", "5.", "1e5", "1E5", "1e+5", "1e-5", "1.5e3", " 1", "1 ", " 2 ", "\t3\n",
        "1d", "1D", "1f", "1F", "1.5d", "0x1p3", "0X1.8P1", "0x10", "NaN", "-NaN", "Infinity", "-Infinity", "+Infinity",
        "infinity", "nan", "inf", "", " ", "-", "+", ".", "e5", "1e", "1e+", "1_000", "1,000", "١", "１", "0", "-0",
        "00012", "1.7976931348623157E308", "1e309", "-1e309", "4.9e-324", "1e-400", "0.1", "0.30000000000000004",
        "9007199254740993", "12345678901234567890", "abc", "12abc", "true", "1.0.0", "--1", "1e5.5", "0x", "\u00a01",
        "1\u00a0",
    )

    /** Doubles for Double.toString: edge values, then values drawn from fixed seeds. */
    fun doubles(): List<Double> {
        val out = mutableListOf(
            0.0, -0.0, 1.0, -1.0, 0.1, 0.2, 0.3, 0.1 + 0.2, 1.0 / 3, 2.0 / 3, 1e-3, 9.99e-4, 0.001, 0.01, 1e7, 9999999.0,
            9999999.5, 1e7 + 0.5, 1e21, 1e22, 1e23, 1e-5, 123456.789, Double.MAX_VALUE, Double.MIN_VALUE,
            -Double.MIN_VALUE, 9007199254740992.0, 9.223372036854776E18, Double.NaN, Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY, 100.0, 1234567.0, 12.5, -2.5, 1e16, 1.2345678901234567, Math.PI, Math.E, 2e-3, 1.1,
            0.5, 2.5, 1e-7, 1.0E-4, 5e-324, 1.0E-323, 2.2250738585072014E-308, 4503599627370496.5, 0.1 * 3, 1e300,
            1.7976931348623157E308, 2.0 / 3 * 1e10, 1e-300 / 3,
        )
        val r = Random(2024)
        repeat(40) { out += r.nextDouble() }
        repeat(20) { out += r.nextDouble() * 1e9 }
        repeat(60) {
            val bits = (r.nextInt().toLong() shl 32) or (r.nextInt().toLong() and 0xffffffffL)
            out += java.lang.Double.longBitsToDouble(bits)
        }
        return out.distinctBy { java.lang.Double.doubleToLongBits(it) }
    }

    /** JSON texts for kotlinx's JsonElement.toString(). */
    val JSON = listOf(
        "1", "1.0", "-0", "-0.0", "1e2", "1E+2", "1.50", "0.1", "123456789012345678901234567890", "1e400", "true", "false",
        "null", "\"\"", "\"abc\"", "\"a\\\"b\"", "\"a\\\\b\"", "\"a/b\"", "\"a\\/b\"", "\"\\n\\t\\b\\f\\r\"",
        "\"\\u0001\\u001f\\u007f\"", "\"\\u00e9\\u2028\\u2029\"", "\"é😀\"", "\"\\ud83d\\ude00\"", "[]", "{}",
        "[1,2.0,\"x\",true,null]", "{\"a\":1,\"b\":[1.0,{\"c\":\"d\"}]}", "{\"a\":1,\"a\":2}", "{\"b\":1,\"a\":2,\"b\":3}",
        "{ \"spaced\" : [ 1 , 2 ] }", "{\"k\\\"ey\":\"v\\nal\"}", "{\"\":\"\"}", "[[[]]]", "\"\\u0000\"",
        "{\"play\":\"x\",\"dur\":1.0,\"lines\":[{\"at\":0,\"text\":\"Hi \\\"you\\\"\"}]}",
    )

    /** JSON primitives for kotlinx's accessors (content, doubleOrNull, booleanOrNull, intOrNull, longOrNull). */
    val PRIMITIVES = listOf(
        "1", "1.0", "-0", "1e2", "1E+2", "1.5e-3", "0.1", "\"1\"", "\"1.5\"", "\"abc\"", "true", "false", "\"true\"",
        "\"TRUE\"", "\"False\"", "\"yes\"", "null", "\"null\"", "9007199254740993", "2147483647", "2147483648",
        "-2147483648", "-2147483649", "9223372036854775807", "9223372036854775808", "\"  12 \"", "\"0x10\"", "\"1d\"",
        "1e400", "\"NaN\"", "\"Infinity\"", "\"\"", "\"-\"", "\"+1\"", "\"12\"", "\"-7\"", "12.0", "1e0", "\"1e2\"",
        "-12", "0", "\"007\"",
    )

    // ----- Map errors -----

    class MapCase(val name: String, val map: String, val packs: List<String> = emptyList())

    class RuntimeCase(val name: String, val map: String, val calls: List<List<String?>>)

    private const val YES_ASK = """{"say":[],"ask":{"reprompt":[],"answers":[{"yes":true,"go":"b"}]}}"""
    private const val B_END = """{"say":[],"end":{"kind":"ending","title":"Done"}}"""

    /**
     * A small map with nodes a and b. [a] replaces node a; [fields] replace or add top-level fields (name to JSON text,
     * null to leave a field out), in place.
     */
    private fun map(a: String = YES_ASK, fields: Map<String, String?> = emptyMap()): String {
        val all = linkedMapOf<String, String?>(
            "format" to "1", "id" to "\"demo\"", "title" to "\"Demo\"", "start" to "\"a\"", "vars" to "{\"n\":0}",
            "who" to "{\"H\":\"\"}", "nodes" to "{\"a\":$a,\"b\":$B_END}",
        )
        all.putAll(fields)
        return all.entries.filter { it.value != null }.joinToString(",", "{", "}") { "\"${it.key}\":${it.value}" }
    }

    private fun ask(answers: String, extra: String = "") = """{"say":[],"ask":{"reprompt":[]$extra,"answers":[$answers]}}"""

    private fun say(step: String) = """{"say":[$step],"go":"b"}"""

    private const val CLIP = """{"play":"c","dur":1,"lines":[{"at":0,"len":1,"who":"H","text":"Hi"}]}"""

    private val PACK = """{"format":1,"game":"demo","id":"demo-levels","vars":{"stars":0},"keep":["stars","n"],""" +
        """"who":{"G":"Guide"},"nodes":{"b":{"say":[],"end":{"kind":"chapter","title":"Level 1","next":"c"}},"c":$B_END}}"""

    val MAP_CASES = listOf(
        MapCase("base", map()),
        MapCase("format missing", map(fields = mapOf("format" to null))),
        MapCase("format 2", map(fields = mapOf("format" to "2"))),
        MapCase("format as text", map(fields = mapOf("format" to "\"1\""))),
        MapCase("format 1.0", map(fields = mapOf("format" to "1.0"))),
        MapCase("empty object", "{}"),
        MapCase("missing title", map(fields = mapOf("title" to null))),
        MapCase("missing id", map(fields = mapOf("id" to null))),
        MapCase("missing start", map(fields = mapOf("start" to null))),
        MapCase("title a number", map(fields = mapOf("title" to "1.50"))),
        MapCase("missing nodes", map(fields = mapOf("nodes" to null))),
        MapCase("nodes a list", map(fields = mapOf("nodes" to "[]"))),
        MapCase("node not an object", map(a = "1")),
        MapCase("node with nothing", map(a = """{"say":[]}""")),
        MapCase("node with ask and go", map(a = """{"say":[],"go":"b","ask":{"answers":[{"any":true}]}}""")),
        MapCase("ask without answers", map(a = """{"say":[],"ask":{"reprompt":[]}}""")),
        MapCase("answers not a list", map(a = """{"say":[],"ask":{"answers":{"yes":true}}}""")),
        MapCase("answer not an object", map(a = ask("\"yes\""))),
        MapCase("answer yes and no", map(a = ask("""{"yes":true,"no":true,"go":"b"}"""))),
        MapCase("answer without a match", map(a = ask("""{"go":"b"}"""))),
        MapCase("answer words and digits", map(a = ask("""{"words":["x"],"digits":"12","go":"b"}"""))),
        MapCase("seq without symbols", map(a = ask("""{"seq":"ab","go":"b"}"""))),
        MapCase("seq with symbols", map(a = ask("""{"seq":"ab","symbols":"t","go":"b"}"""), fields = mapOf("symbols" to """{"t":{"a":["ay"],"b":["bee"]}}"""))),
        MapCase("symbols not an object", map(fields = mapOf("symbols" to """{"t":["a"]}"""))),
        MapCase("least not a number", map(a = ask("""{"digits":"12","least":"x","go":"b"}"""))),
        MapCase("least 1.5", map(a = ask("""{"digits":"12","least":1.5,"go":"b"}"""))),
        MapCase("least 2.0", map(a = ask("""{"digits":"12","least":2.0,"go":"b"}"""))),
        MapCase("least as text", map(a = ask("""{"digits":"12","least":"2","go":"b"}"""))),
        MapCase("opposite and rank as text", map(a = ask("""{"words":["x"],"opposite":"1","rank":"2","go":"b"},{"words":["y"],"go":"b"}"""))),
        MapCase("rank too big", map(a = ask("""{"words":["x"],"rank":99999999999,"go":"b"}"""))),
        MapCase("bad regex", map(a = ask("""{"re":"(","go":"b"}"""))),
        MapCase("regex", map(a = ask("""{"re":"\\bfo+\\b","go":"b"}"""))),
        MapCase("answer flags as text", map(a = ask("""{"yes":"TRUE","go":"b"}"""))),
        MapCase("answer flag 1", map(a = ask("""{"yes":1,"any":"true","go":"b"}"""))),
        MapCase("answer words not a list", map(a = ask("""{"words":"x","go":"b"}"""))),
        MapCase("answer words empty after normalising", map(a = ask("""{"words":["?!","=..."],"go":"b"}"""))),
        MapCase("unknown step", map(a = say("""{"foo":1}"""))),
        MapCase("step not an object", map(a = say("\"x\""))),
        MapCase("play without dur", map(a = say("""{"play":"x"}"""))),
        MapCase("dur as text", map(a = say("""{"play":"x","dur":"1.5"}"""))),
        MapCase("dur not a number", map(a = say("""{"play":"x","dur":"abc","lines":[{"at":0,"who":"H","text":"A long line of text so that the object is cut at 120 characters"}]}"""))),
        MapCase("dur null", map(a = say("""{"play":"x","dur":null}"""))),
        MapCase("dur 1e3 and hex", map(a = say("""{"play":"x","dur":1e3},{"play":"y","dur":"0x1p3"}"""))),
        MapCase("dur too big", map(a = say("""{"play":"x","dur":1e400}"""))),
        MapCase("line without who", map(a = say("""{"play":"x","dur":1,"lines":[{"at":0,"len":1,"text":"Hi \"you\"\n\ttab"}]}"""))),
        MapCase("line without at", map(a = say("""{"play":"x","dur":1,"lines":[{"len":1,"who":"H","text":"é😀"}]}"""))),
        MapCase("line words not numbers", map(a = say("""{"play":"x","dur":1,"lines":[{"at":0,"who":"H","text":"t","w":["a"]}]}"""))),
        MapCase("line words as text", map(a = say("""{"play":"x","dur":1,"lines":[{"at":0,"who":"H","text":"t","w":["0.5",1]}],"sfx":"true"}"""))),
        MapCase("line more", map(a = say("""{"play":"x","dur":1,"lines":[{"at":0,"len":"0.5","who":"H","text":"t","more":"TRUE"}]}"""))),
        MapCase("beds", map(a = say("""{"bed":"m","volume":"0.25","dur":9},{"bed":null},{"bed":1,"volume":true}"""))),
        MapCase("when", map(a = say("""{"when":"n > 1","play":"x","dur":1},{"when":5,"play":"y","dur":1}"""))),
        MapCase("when not an expression", map(a = say("""{"when":"n >> 2","play":"x","dur":1}"""))),
        MapCase("when unknown function", map(a = say("""{"when":"foo(1)","play":"x","dur":1}"""))),
        MapCase("when unexpected characters", map(a = say("""{"when":"n # 2","play":"x","dur":1}"""))),
        MapCase("when empty", map(a = say("""{"when":"","play":"x","dur":1}"""))),
        MapCase("pick and by", map(a = say("""{"pick":[[$CLIP],[],"x"]},{"by":"n","cases":{"1":[$CLIP],"x":[]},"else":[$CLIP]},{"by":"n"}"""))),
        MapCase("num and pause", map(a = say("""{"num":"n"},{"pause":0.5},{"pause":"2"}"""))),
        MapCase("pause not a number", map(a = say("""{"pause":"soon"}"""))),
        MapCase("go unknown", map(a = """{"say":[],"go":{"to":"b"}}""")),
        MapCase("go a number", map(a = """{"say":[],"go":5}""")),
        MapCase("go end stop", map(a = """{"say":[],"go":{"end":"stop"}}""")),
        MapCase("go quit and leave", map(a = """{"say":[],"go":{"random":[{"end":"quit"},{"end":"leave"},"b"]}}""")),
        MapCase("go if without else", map(a = """{"say":[],"go":{"if":[{"when":"n","go":"b"}]}}""")),
        MapCase("go if", map(a = """{"say":[],"go":{"if":[{"when":"n","go":"b"}],"else":{"restart":"a"}}}""")),
        MapCase("go case without go", map(a = """{"say":[],"go":{"if":[{"when":"n"}],"else":"b"}}""")),
        MapCase("go case without when", map(a = """{"say":[],"go":{"if":[{"go":"b"}],"else":"b"}}""")),
        MapCase("go draw without deck", map(a = """{"say":[],"go":{"draw":["b"]}}""")),
        MapCase("go draw", map(a = """{"say":[],"go":{"draw":["b","a"],"deck":"d"}}""")),
        MapCase("go random not a list", map(a = """{"say":[],"go":{"random":"b"}}""")),
        MapCase("redirect", map(a = """{"redirect":[{"when":"n == 1","go":"b"}],"say":[],"go":"b"}""")),
        MapCase("redirect not an object", map(a = """{"redirect":["b"],"say":[],"go":"b"}""")),
        MapCase("set an object", map(a = """{"set":{"n":{"x":1}},"say":[],"go":"b"}""")),
        MapCase("set a list", map(a = """{"set":{"n":[1]},"say":[],"go":"b"}""")),
        MapCase("set null", map(a = """{"set":{"n":null},"say":[],"go":"b"}""")),
        MapCase("set values", map(a = """{"set":{"a":"+1.5","b":"+1.","c":"-2","d":"rand(1, 6)","e":"rand( -3 ,3 )","f":"=n * 2","g":"TRUE","h":true,"i":2.50},"say":[],"go":"b"}""")),
        MapCase("set calc empty", map(a = """{"set":{"n":"="},"say":[],"go":"b"}""")),
        MapCase("set calc bad", map(a = """{"set":{"n":"=n +"},"say":[],"go":"b"}""")),
        MapCase("set rand too big", map(a = """{"set":{"n":"rand(99999999999, 1)"},"say":[],"go":"b"}""")),
        MapCase("vars null", map(fields = mapOf("vars" to """{"x":null}"""))),
        MapCase("vars object", map(fields = mapOf("vars" to """{"x":{}}"""))),
        MapCase("vars values", map(fields = mapOf("vars" to """{"t":"TRUE","f":false,"d":0.5,"e":"","z":-0.0,"big":1e300,"n":-7}"""))),
        MapCase("vars not an object", map(fields = mapOf("vars" to "[1]"))),
        MapCase("keep", map(fields = mapOf("keep" to """["n","n",1,"x"]"""))),
        MapCase("repeat sometimes", map(fields = mapOf("repeat" to "\"sometimes\""))),
        MapCase("repeat 5", map(fields = mapOf("repeat" to "5"))),
        MapCase("repeat say", map(fields = mapOf("repeat" to "\"say\""))),
        MapCase("words not a list", map(fields = mapOf("words" to """{"yes":"yes"}"""))),
        MapCase("words", map(fields = mapOf("words" to """{"yes":["Yes!","=Fine","?"],"repeat":["again"],"mixed":{"yes":["yes","ok then"],"no":["NO"],"filler":["um"]}}"""))),
        MapCase("words mixed not an object", map(fields = mapOf("words" to """{"mixed":["x"]}"""))),
        MapCase("words not an object", map(fields = mapOf("words" to """["x"]"""))),
        MapCase("who not text", map(fields = mapOf("who" to """{"H":1,"G":null}"""))),
        MapCase("buttons", map(a = ask("""{"yes":true,"go":"b"}""", ""","buttons":[{"label":"Yes"},{"label":"No way","value":"no"}]"""))),
        MapCase("button without label", map(a = ask("""{"yes":true,"go":"b"}""", ""","buttons":[{"value":"x"}]"""))),
        MapCase("else", map(a = ask("""{"yes":true,"go":"b"}""", ""","else":{"say":[$CLIP],"set":{"n":"+1"}}"""))),
        MapCase("else a go", map(a = ask("""{"yes":true,"go":"b"}""", ""","else":"b""""))),
        MapCase("else bad go", map(a = ask("""{"yes":true,"go":"b"}""", ""","else":7"""))),
        MapCase("end without title", map().replace("\"title\":\"Done\"", "\"titles\":\"Done\"")),
        MapCase("end next a number", map().replace("\"title\":\"Done\"", "\"title\":\"Done\",\"next\":3,\"retry\":\"a\",\"locked\":\"p\"")),
        MapCase("duplicate keys", "{\"format\":1,\"id\":\"x\",\"title\":\"X\",\"start\":\"a\",\"id\":\"demo\",\"nodes\":{\"a\":$B_END,\"a\":$YES_ASK,\"b\":$B_END}}"),
        MapCase("unicode escapes", map().replace("\"title\":\"Demo\"", "\"title\":\"Caf\\u00e9 \\ud83d\\ude00 \\\"q\\\"\"")),
        MapCase("long title cut", map(a = """{"say":[],"ask":{"reprompt":[],"answers":[{"yes":true,"go":"b"}],"buttons":[{"value":"$LONG"}]}}""")),
        MapCase("cut after a backslash", map(a = ask("""{"yes":true,"go":"b"}""", ""","buttons":[{"value":"${"x".repeat(109)}\"q"}]"""))),
        MapCase("node id with quotes", "{\"format\":1,\"id\":\"demo\",\"title\":\"Demo\",\"start\":\"a\",\"nodes\":{\"a\\\"1\":{\"say\":[]}}}"),
        MapCase("pack", map(), listOf(PACK)),
        MapCase("two packs", map(), listOf(PACK, """{"format":1,"game":"demo","id":"more","keep":["m"],"symbols":{"t":{"x":["ex"]}},"nodes":{"d":$B_END}}""")),
        MapCase("pack for another game", map(), listOf(PACK.replace("\"game\":\"demo\"", "\"game\":\"other\""))),
        MapCase("pack id a number", map(), listOf(PACK.replace("\"game\":\"demo\",\"id\":\"demo-levels\"", "\"game\":\"other\",\"id\":7"))),
        MapCase("pack without game", map(), listOf(PACK.replace("\"game\":\"demo\",", ""))),
        MapCase("pack replaces a node badly", map(), listOf("""{"format":1,"game":"demo","id":"p","nodes":{"b":{"say":[]}}}""")),
        MapCase("pack vars not an object", map(), listOf("""{"format":1,"game":"demo","id":"p","vars":[1],"nodes":{}}""")),
    )

    private const val LONG = "A very long button value, long enough that the object's text runs past 120 characters, " +
        "so that the message cuts it short somewhere in the middle"

    private val SMALL = """{"format":1,"id":"demo","title":"Demo","start":"a","nodes":{"a":$YES_ASK,"b":$B_END}}"""

    val RUNTIME_CASES = listOf(
        RuntimeCase("a loop", """{"format":1,"id":"demo","title":"Demo","start":"a","nodes":{"a":{"say":[],"go":"c"},"c":{"say":[],"go":"a"}}}""", listOf(listOf("start"))),
        RuntimeCase("no such node", """{"format":1,"id":"demo","title":"Demo","start":"a","nodes":{"a":{"say":[],"go":"nowhere"}}}""", listOf(listOf("start"))),
        RuntimeCase("no symbol table", """{"format":1,"id":"demo","title":"Demo","start":"a","nodes":{"a":{"say":[],"ask":{"answers":[{"seq":"ab","symbols":"t","go":"a"}]}}}}""", listOf(listOf("start"), listOf("answer", "a b"))),
        RuntimeCase("answer at an end", SMALL, listOf(listOf("start"), listOf("answer", "yes"), listOf("answer", "yes"))),
        RuntimeCase("silence at an end", SMALL, listOf(listOf("start"), listOf("answer", "yes"), listOf("silence"))),
        RuntimeCase("next chapter not at an end", SMALL, listOf(listOf("start"), listOf("next"))),
        RuntimeCase("next chapter without a next", SMALL, listOf(listOf("start"), listOf("answer", "yes"), listOf("next"))),
        RuntimeCase("next chapter not in the map", SMALL.replace("\"title\":\"Done\"", "\"title\":\"Level 1\",\"kind\":\"chapter\",\"next\":\"level2\",\"locked\":\"demo-levels\"").replace("\"kind\":\"ending\",", ""), listOf(listOf("start"), listOf("answer", "yes"), listOf("next"))),
        RuntimeCase("restart at a missing node", SMALL, listOf(listOf("start"), listOf("restart", "zz"))),
    )

    // ----- Random -----

    /** The calls each random.json vector makes, on a logging Random. */
    fun randomProgram(r: Random) {
        repeat(8) { r.nextInt() }
        for (n in listOf(1, 2, 4, 8, 16, 1024, 1 shl 30)) repeat(2) { r.nextInt(n) }
        for (n in listOf(3, 5, 6, 7, 10, 20, 27, 37, 100, 1000, 1_000_001, Int.MAX_VALUE, (1 shl 30) + 1, 1_500_000_000)) {
            repeat(2) { r.nextInt(n) }
        }
        for ((from, until) in listOf(-10 to 10, -5 to -1, 0 to 1, Int.MIN_VALUE to Int.MAX_VALUE, Int.MIN_VALUE to 0,
            -1_000_000_000 to 1_500_000_000, 5 to 6, -2_000_000_000 to 2_000_000_000)) {
            repeat(2) { r.nextInt(from, until) }
        }
        for (bits in 0..32) r.nextBits(bits)
        repeat(6) { r.nextDouble() }
        repeat(8) { r.nextBoolean() }
        repeat(4) { r.nextInt(3) }
    }

    val RANDOM_SEEDS = listOf(0, 1, 2, 7, 37, 38, 42, 1000, 7920, -1, -2, -123456789, 123456789, Int.MAX_VALUE, Int.MIN_VALUE)

    val SHUFFLE_SEEDS = listOf(1, 2, 7, 42, -1)
    val SHUFFLE_SIZES = listOf(0, 1, 2, 3, 4, 5, 10, 52)
}
