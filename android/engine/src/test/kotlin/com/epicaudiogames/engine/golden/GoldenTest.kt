package com.epicaudiogames.engine.golden

import com.epicaudiogames.engine.Commands
import com.epicaudiogames.engine.Expr
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.MapException
import com.epicaudiogames.engine.Match
import com.epicaudiogames.engine.Matcher
import com.epicaudiogames.engine.Phrase
import com.epicaudiogames.engine.Saved
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.Text
import com.epicaudiogames.engine.Turn
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

/**
 * Writes (gradlew :engine:goldens) or checks (gradlew :engine:goldensCheck) the golden fixtures in fixtures/engine,
 * which the Swift engine replays; fixtures/engine/README.md is their format. Skipped in a plain :engine:test.
 */
class GoldenTest {
    private fun prop(name: String) = System.getProperty(name) ?: throw IllegalStateException("no $name (run it through gradlew)")

    @Test
    fun fixtures() {
        val write = System.getProperty("goldens.write") == "true"
        val check = System.getProperty("goldens.check") == "true"
        val dump = System.getProperty("goldens.dump")?.takeIf { it.isNotBlank() }
        assumeTrue("the fixtures are made by gradlew :engine:goldens", write || check || dump != null)
        val goldens = Goldens(File(prop("games.dir")), File(prop("engine.src")))
        if (dump != null) {
            val out = File(prop("goldens.dumpDir"), dump.replace('/', '_') + ".jsonl")
            out.parentFile.mkdirs()
            out.writeText(goldens.dump(dump).joinToString("") { "$it\n" })
            println("golden dump $dump -> ${out.path}")
            return
        }
        val dir = File(prop("fixtures.dir"))
        val files = goldens.all()
        if (write) write(dir, files) else check(dir, files)
    }

    /** Writes the files that changed and deletes generated files that are no longer made. */
    private fun write(dir: File, files: Map<String, String>) {
        for ((path, text) in files) {
            val f = File(dir, path)
            f.parentFile.mkdirs()
            if (!f.isFile || f.readText() != text) f.writeText(text)
        }
        for (stale in generated(dir) - files.keys) File(dir, stale).delete()
        var total = 0L
        for ((path, text) in files) {
            val size = text.toByteArray(Charsets.UTF_8).size
            total += size
            println("  %-48s %9d bytes".format(path, size))
        }
        println("  %-48s %9d bytes".format("total (${files.size} files)", total))
    }

    /** Fails, naming each file whose content differs (beyond the header's hashes) and where. */
    private fun check(dir: File, files: Map<String, String>) {
        val problems = mutableListOf<String>()
        val headerOnly = mutableListOf<String>()
        for ((path, text) in files) {
            val f = File(dir, path)
            if (!f.isFile) {
                problems += "$path: missing"
                continue
            }
            val old = f.readText()
            if (old == text) continue
            // The header's hashes change with any edit to games/ or the engine; say first what else changed.
            val was = STAMP.find(old)?.value
            val now = STAMP.find(text)?.value
            val same = if (was != null && now != null) old.replaceFirst(was, now) else old
            if (same == text) {
                headerOnly += path
                continue
            }
            val a = same.split('\n')
            val b = text.split('\n')
            val i = a.indices.firstOrNull { it >= b.size || a[it] != b[it] } ?: a.size
            val x = a.getOrElse(i) { "" }
            val y = b.getOrElse(i) { "" }
            val at = (0 until minOf(x.length, y.length)).firstOrNull { x[it] != y[it] } ?: minOf(x.length, y.length)
            fun around(s: String) = s.substring(minOf(s.length, maxOf(0, at - 150)), minOf(s.length, at + 150))
            problems += "$path: differs at line ${i + 1}, column ${at + 1}\n    committed: …${around(x)}…\n    now:       …${around(y)}…"
        }
        for (stale in generated(dir) - files.keys) problems += "$stale: no longer generated"
        if (headerOnly.isNotEmpty()) problems += "${headerOnly.size} more files differ only in their header's hashes (games/ or the engine changed)"
        if (problems.isNotEmpty()) {
            fail("fixtures/engine is out of date (cd android && ./gradlew :engine:goldens):\n" + problems.take(20).joinToString("\n"))
        }
    }

    private companion object {
        val STAMP = Regex(""""games_sha256":"[0-9a-f]{64}","engine_sha256":"[0-9a-f]{64}"""")
    }

    private fun generated(dir: File): Set<String> = dir.walkTopDown()
        .filter { it.isFile && (it.name.endsWith(".json") || it.name.endsWith(".jsonl")) }
        .map { it.relativeTo(dir).invariantSeparatorsPath }
        .toSet()
}

/** The fixtures, made from a games folder and the engine sources (for the header's hashes). */
class Goldens(private val games: File, engineSrc: File) {
    private val stamp = Canon.header(Canon.treeSha256(games, ".json"), Canon.treeSha256(engineSrc, ".kt"))

    /** A file's header (README section 4), with [more] fields after it. */
    private fun header(vararg more: Pair<String, Any?>): Map<String, Any?> = LinkedHashMap(stamp).apply { putAll(more) }

    /** A map as the app loads it: the free map, or the game with all its packs. */
    class Variant(val name: String, val dir: File, val files: List<File>, val map: GameMap) {
        val packs get() = files.drop(1)
    }

    val variants: List<Variant> by lazy {
        val dirs = games.listFiles().orEmpty().filter { File(it, "map.json").isFile }.sortedBy { it.name }
        check(dirs.isNotEmpty()) { "no maps in ${games.absolutePath}" }
        dirs.flatMap { dir ->
            val map = File(dir, "map.json")
            val packs = File(dir, "packs").listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }
            listOf(Variant(dir.name, dir, listOf(map), GameMap.load(map))) +
                if (packs.isEmpty()) emptyList() else listOf(Variant("${dir.name}+packs", dir, listOf(map) + packs, GameMap.load(map, packs)))
        }
    }

    /** Each game once, with everything it can have: its packs merged in when it has any. */
    private val fullest by lazy { variants.groupBy { it.dir }.values.map { it.last() } }

    private val audio by lazy {
        val clips = File(games, "${NuclearWar.ID}/clips.json")
        check(clips.isFile) { "no $clips: the Nuclear War fixtures need the real audio table" }
        NuclearAudio.load(clips)
    }

    fun all(): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["random.json"] = random()
        out["text.json"] = text()
        out["expr.json"] = expr()
        out["map-errors.json"] = mapErrors()
        val sweeps = mutableListOf<Map<String, Any?>>()
        for (v in variants) {
            out["maps/${v.name}.digest.json"] = digest(v)
            out["maps/${v.name}.matcher.json"] = matcher(v)
            val (tier1, sweep) = walks(v)
            out["maps/${v.name}.walks.jsonl"] = tier1
            sweeps += sweep
        }
        out["maps/hashes.json"] = Canon.jsonFile(header(
            "walks" to MAP_WALKS, "turns" to MapWalker.TURNS, "reopen" to MapWalker.REOPEN, "variants" to sweeps,
        ), setOf("variants"))
        val (games, hashes, saves) = nuclear()
        out["nuclear-war/games.jsonl"] = games
        out["nuclear-war/fanout.jsonl"] = fanout(saves)
        out["nuclear-war/hashes.json"] = hashes
        return out
    }

    // ----- random.json -----

    private fun random(): String {
        val vectors = Corpora.RANDOM_SEEDS.map { seed ->
            val r = LoggingRandom(Random(seed))
            Corpora.randomProgram(r)
            linkedMapOf("seed" to seed, "draws" to r.take())
        }
        val shuffles = Corpora.SHUFFLE_SEEDS.flatMap { seed ->
            Corpora.SHUFFLE_SIZES.map { size -> linkedMapOf("seed" to seed, "size" to size, "result" to (0 until size).toList().shuffled(Random(seed))) }
        }
        return Canon.jsonFile(header("vectors" to vectors, "shuffles" to shuffles), setOf("vectors", "shuffles"))
    }

    // ----- text.json -----

    private fun text(): String {
        val dropped = mutableListOf<Any?>()
        val raw = LinkedHashSet<String>()
        for (v in fullest) for (f in v.files) raw += Corpora.rawStrings(f)
        raw += Corpora.TEXT
        raw += Corpora.UTTERANCES
        val strings = raw.map { listOf(it, Text.normalise(it), Text.digits(it), Commands.isPause(it)) }

        // Phrases from the free maps' questions, and the asks they belong to.
        val asks = variants.filter { !it.name.endsWith("+packs") }.flatMap { v -> v.map.nodes.values.mapNotNull { it.ask } }
        val phrases = LinkedHashSet<Phrase>()
        for (a in asks) for (ans in a.answers) {
            when (val m = ans.match) {
                is Match.Words -> phrases += m.phrases
                is Match.Yes -> phrases += m.extra
                is Match.No -> phrases += m.extra
                else -> Unit
            }
        }
        val sample = phrases.toList().let { all -> all.filterIndexed { i, _ -> i % maxOf(1, all.size / 80) == 0 }.take(80) }
        val phraseLength = mutableListOf<Any?>(
            listOf("the red one", listOf("red", false), Text.phraseLength("the red one", Phrase("red", false))),
            listOf("i'm ready", listOf("red", false), Text.phraseLength("i'm ready", Phrase("red", false))),
            listOf("fine", listOf("fine", true), Text.phraseLength("fine", Phrase("fine", true))),
            listOf("i'm fine", listOf("fine", true), Text.phraseLength("i'm fine", Phrase("fine", true))),
        )
        val negated = mutableListOf<Any?>()
        for ((t, p) in listOf("don't follow it" to "follow", "i really don't want to follow" to "follow", "let's not hide" to "hide",
            "follow it" to "follow", "don't you want to go on and follow" to "follow")) negated.add(listOf(t, p, Text.negated(t, p)))
        for (p in sample) {
            for (t in Corpora.phraseTexts(p.text)) {
                phraseLength.add(listOf(t, listOf(p.text, p.exact), Text.phraseLength(t, p)))
                negated.add(listOf(t, p.text, Text.negated(t, p.text)))
            }
            phraseLength.add(listOf(p.text, listOf(p.text, !p.exact), Text.phraseLength(p.text, Phrase(p.text, !p.exact))))
        }
        val longest = mutableListOf<Any?>()
        val rehearsal = listOf(Phrase("rehearsal", false), Phrase("no rehearsal", false))
        longest.add(listOf("no rehearsal please", rehearsal.map(Canon::phrase), Text.longest("no rehearsal please", rehearsal)?.let(Canon::phrase)))
        // Ties: the first of the longest wins, whichever comes first in the text.
        val ties = listOf(Phrase("red", false), Phrase("big", false))
        for (t in listOf("big red", "red big", "a big red bus")) longest.add(listOf(t, ties.map(Canon::phrase), Text.longest(t, ties)?.let(Canon::phrase)))
        for (a in asks.filter { a -> a.answers.count { it.match is Match.Words } >= 2 }.take(60)) {
            val ps = a.answers.flatMap { (it.match as? Match.Words)?.phrases.orEmpty() }
            val texts = ps.take(3).flatMap { listOf(it.text, "well ${it.text} or ${ps.last().text}") } + "nothing at all"
            for (t in texts) longest.add(listOf(t, ps.map(Canon::phrase), Text.longest(t, ps)?.let(Canon::phrase)))
        }

        // Symbol tables: TextTest's, then Signal Decoders'.
        val tables = linkedMapOf(
            "test-letters" to linkedMapOf("c" to listOf("c", "see", "sea"), "a" to listOf("a", "ay", "eh")),
            "test-turns" to linkedMapOf("l" to listOf("left", "lift"), "r" to listOf("right", "write")),
        )
        for (v in variants) for ((name, table) in v.map.symbols) if (name !in tables) tables[name] = LinkedHashMap(table)
        val symbols = mutableListOf<Any?>()
        fun sym(said: String, table: String, spelled: Boolean) {
            symbols.add(listOf(said, table, spelled, Text.symbols(said, tables.getValue(table), spelled)))
        }
        sym("see a see", "test-letters", false)
        sym("c ac", "test-letters", false)
        sym("c ac", "test-letters", true)
        sym("left, right, write, lift!", "test-turns", false)
        for ((name, table) in tables) {
            val keys = table.keys.toList()
            val inputs = listOf(
                table.values.joinToString(" ") { it.first() },
                table.values.joinToString(", ") { it.last() }.uppercase() + "!",
                keys.joinToString(""), keys.take(3).joinToString(""), keys.reversed().joinToString(" "),
                "the ${table.values.first().first()} one, then ${table.values.last().first()} please",
                keys.joinToString("") + " " + keys.first(), "zzz", "",
            ) + table.values.map { it.joinToString(" ") }
            for (said in inputs) for (spelled in listOf(false, true)) sym(said, name, spelled)
        }

        // Mixed yes and no answers, per game.
        val mixed = mutableListOf<Any?>()
        for (v in variants.filter { !it.name.endsWith("+packs") }) {
            val m = v.map.words.mixed ?: continue
            val words = (m.yes.take(3) + m.no.take(3) + m.filler.take(2) + (m.yes + m.no).filter { ' ' in it }.take(2)).distinct()
            val texts = LinkedHashSet<String>()
            for (a in words) {
                texts += a
                for (b in words) texts += "$a $b"
            }
            texts += listOf("yes please", "no no no", "yeah no", "no yes", "um yes", "", "yes zzz", "${m.filler.firstOrNull()} ${m.filler.firstOrNull()}")
            for (t in texts) mixed.add(listOf(v.name, Text.normalise(t), Matcher.mixed(v.map, Text.normalise(t))))
        }

        val toDouble = Corpora.TO_DOUBLE.map { listOf(it, it.toDoubleOrNull()) }
        val doubleString = mutableListOf<Any?>()
        for (d in Corpora.doubles()) {
            if (Canon.javaTextIsShortest(d)) doubleString.add(listOf(d, d.toString()))
            else dropped.add(listOf("doubleString", d, d.toString()))
        }
        val json = Corpora.JSON.map { listOf(it, Json.parseToJsonElement(it).toString()) }
        val primitives = Corpora.PRIMITIVES.map {
            val p = Json.parseToJsonElement(it) as JsonPrimitive
            listOf(it, p.content, p.isString, p.doubleOrNull, p.booleanOrNull, p.intOrNull, p.longOrNull?.toString())
        }
        return Canon.jsonFile(header(
            "strings" to strings, "phraseLength" to phraseLength, "longest" to longest, "negated" to negated,
            "tables" to tables.mapValues { (_, t) -> t.entries.map { listOf(it.key, it.value) } }, "symbols" to symbols,
            "mixed" to mixed, "toDouble" to toDouble, "doubleString" to doubleString, "json" to json,
            "primitives" to primitives, "dropped" to dropped,
        ), setOf("strings", "phraseLength", "longest", "negated", "symbols", "mixed", "toDouble", "doubleString", "json",
            "primitives", "dropped"))
    }

    // ----- expr.json -----

    private fun expr(): String {
        val names = LinkedHashSet<String>()
        val perGame = fullest.map { v ->
            val sources = LinkedHashSet<Pair<String, String>>()
            for (f in v.files) Corpora.expressions(f, sources)
            val parsed = sources.map { (kind, src) -> Triple(kind, src, Expr.parse(src)) }
            parsed.forEach { names += it.third.names }
            v to parsed
        }
        val extra = Corpora.EXPRS.map { it to Expr.parse(it) }
        extra.forEach { names += it.second.names }
        val nameList = names.toList()
        val missing = emptyMap<String, Any>()
        val mixed = nameList.withIndex().associate { (i, n) -> n to Corpora.MIXED[i % Corpora.MIXED.size] }
        val numbers = nameList.withIndex().associate { (i, n) -> n to Corpora.NUMBERS[i % Corpora.NUMBERS.size] }
        val varsets = fullest.map { v -> linkedMapOf("name" to "initial", "game" to v.name, "vars" to Canon.vars(v.map.vars)) } + listOf(
            linkedMapOf("name" to "missing", "game" to null, "vars" to Canon.vars(missing)),
            linkedMapOf("name" to "mixed", "game" to null, "vars" to Canon.vars(mixed)),
            linkedMapOf("name" to "numbers", "game" to null, "vars" to Canon.vars(numbers)),
        )
        val dropped = mutableListOf<Any?>()
        fun results(e: Expr, sets: List<Map<String, Any>>): List<Any?>? {
            val out = sets.map { vars ->
                val value = e.eval(vars)
                val ok = when (value) {
                    is Double -> (value.isFinite() && value == kotlin.math.floor(value)) || Canon.javaTextIsShortest(value)
                    is String -> Canon.textIsShortest(value)
                    else -> true
                }
                if (!ok) return null
                listOf(Canon.value(value), e.test(vars), Expr.key(value))
            }
            return out
        }
        val exprs = mutableListOf<Any?>()
        for ((v, parsed) in perGame) {
            for ((kind, src, e) in parsed) {
                val r = results(e, listOf(v.map.vars, missing, mixed, numbers))
                if (r == null) dropped.add(listOf(v.name, src)) else exprs.add(listOf(v.name, src, kind, e.names.toList(), r))
            }
        }
        val extras = mutableListOf<Any?>()
        for ((src, e) in extra) {
            val r = results(e, listOf(missing, mixed, numbers))
            if (r == null) dropped.add(listOf(null, src)) else extras.add(listOf(src, e.names.toList(), r))
        }
        val errors = Corpora.BAD_EXPRS.map { src ->
            val message = try {
                Expr.parse(src)
                throw IllegalStateException("\"$src\" parses")
            } catch (e: MapException) {
                e.message
            }
            listOf(src, message)
        }
        return Canon.jsonFile(header("varsets" to varsets, "exprs" to exprs, "extra" to extras, "errors" to errors, "dropped" to dropped),
            setOf("varsets", "exprs", "extra", "errors", "dropped"))
    }

    // ----- map-errors.json -----

    private fun mapErrors(): String {
        val cases = Corpora.MAP_CASES.map { c ->
            val o = linkedMapOf<String, Any?>("name" to c.name, "map" to c.map, "packs" to c.packs)
            try {
                o["ok"] = Canon.hash(Canon.map(GameMap.parse(c.map, c.packs)))
            } catch (e: MapException) {
                o["error"] = e.message
            } catch (e: kotlinx.serialization.SerializationException) {
                throw IllegalStateException("map-errors case \"${c.name}\" isn't valid JSON", e)
            } catch (e: Exception) {
                o["error"] = true
            }
            o
        }
        val runtime = Corpora.RUNTIME_CASES.map { c ->
            val s = Session(GameMap.parse(c.map)) { 0 }
            c.calls.dropLast(1).forEach { call(s, it) }
            val error = try {
                call(s, c.calls.last())
                throw AssertionError("runtime case \"${c.name}\": the last call didn't throw")
            } catch (e: MapException) {
                e.message
            } catch (e: IllegalStateException) {
                e.message
            }
            linkedMapOf("name" to c.name, "map" to c.map, "calls" to c.calls, "error" to error)
        }
        return Canon.jsonFile(header("cases" to cases, "runtime" to runtime), setOf("cases", "runtime"))
    }

    private fun call(s: Session, input: List<String?>): Turn = when (input[0]) {
        "start" -> s.start()
        "answer" -> s.answer(input[1]!!)
        "silence" -> s.silence()
        "next" -> s.nextChapter()
        "restart" -> s.restart(input[1])
        else -> throw IllegalArgumentException("no such call $input")
    }

    // ----- Maps -----

    private fun digest(v: Variant): String = Canon.jsonFile(header(
        "variant" to v.name,
        "files" to v.files.map { it.relativeTo(games).invariantSeparatorsPath },
        "map" to Canon.mapHeader(v.map),
        "hash" to Canon.hash(Canon.map(v.map)),
        "nodes" to v.map.nodes.values.map { listOf(it.id, Canon.hash(Canon.node(it))) },
    ), setOf("nodes"))

    /** The chapter ends (in map order) whose next chapter is a pack's: where odd walks of a +packs variant start. */
    private fun entries(v: Variant): List<String> {
        if (v.packs.isEmpty()) return emptyList()
        val fromPacks = v.packs.flatMap { packNodes(it) }.toSet()
        return v.map.nodes.values.filter { n ->
            val e = n.end
            e != null && e.kind == "chapter" && e.next != null && e.next in fromPacks && e.next in v.map.nodes
        }.map { it.id }
    }

    private fun matcher(v: Variant): String {
        val walker = MapWalker(v.map)
        val only = if (v.packs.isEmpty()) null else v.packs.flatMap { packNodes(it) }.toSet()
        val asks = v.map.nodes.values.filter { it.ask != null && (only == null || it.id in only) }.map { n ->
            val ask = n.ask!!
            listOf(n.id, Corpora.matcherInputs(v.map, ask, walker.inputs(ask)).map { said ->
                val r = Matcher.match(v.map, ask, v.map.vars, said)
                listOf(said, r.index, r.repeat, r.how, r.aside)
            })
        }
        return Canon.jsonFile(header("variant" to v.name, "asks" to asks), setOf("asks"))
    }

    private fun packNodes(f: File): Set<String> =
        (Json.parseToJsonElement(f.readText()).jsonObject["nodes"] as? JsonObject)?.keys.orEmpty()

    /** Tier 1 (the first walks, line by line) and Tier 2 (every walk's hash). */
    private fun walks(v: Variant): Pair<String, Map<String, Any?>> {
        val entries = entries(v)
        val walker = MapWalker(v.map, entries)
        val tier1 = StringBuilder(Canon.json(header("variant" to v.name, "walks" to TIER1_WALKS, "entries" to entries))).append('\n')
        val hashes = mutableListOf<String>()
        val visited = HashSet<String>()
        var lines = 0
        for (w in 0 until MAP_WALKS) {
            if (w < TIER1_WALKS) tier1.append(Canon.json(linkedMapOf("walk" to w, "seed" to MapWalker.seed(w)))).append('\n')
            var h = Canon.FNV_START
            lines += walker.walk(w, { visited += it.visited }) { line ->
                h = Canon.fnv("\n", Canon.fnv(line, h))
                if (w < TIER1_WALKS) tier1.append(line).append('\n')
            }
            hashes += Canon.hex(h)
        }
        return tier1.toString() to linkedMapOf(
            "variant" to v.name, "entries" to entries, "lines" to lines, "visited" to visited.size, "nodes" to v.map.nodes.size,
            "walks" to hashes,
        )
    }

    // ----- Nuclear War -----

    private data class Nuclear(val games: String, val hashes: String, val saves: List<Saved>)

    private fun nuclear(): Nuclear {
        val player = NuclearPlayer(audio)
        val tier1 = StringBuilder(Canon.json(header("seeds" to listOf(1, NUCLEAR_TIER1)))).append('\n')
        // The fanout's saves: the first 3 at each question, in game and turn order.
        val saves = mutableListOf<Saved>()
        val taken = mutableMapOf<String, Int>()
        fun sample(s: Saved) {
            if ((taken[s.node] ?: 0) >= FANOUT_PER_QUESTION) return
            taken.merge(s.node, 1, Int::plus)
            saves += s
        }
        val games = mutableListOf<Any?>()
        for (seed in 1..NUCLEAR_GAMES) {
            var h = Canon.FNV_START
            val lines = mutableListOf<String>()
            val game = player.game(seed, ::sample) { line ->
                h = Canon.fnv("\n", Canon.fnv(line, h))
                if (seed <= NUCLEAR_TIER1) lines += line
            }
            if (seed <= NUCLEAR_TIER1) {
                tier1.append(Canon.json(linkedMapOf("seed" to seed, "turns" to game.lines, "end" to game.end))).append('\n')
                lines.forEach { tier1.append(it).append('\n') }
            }
            games.add(listOf(Canon.hex(h), game.lines, game.end))
        }
        val hashes = Canon.jsonFile(header("seeds" to listOf(1, NUCLEAR_GAMES), "games" to games), setOf("games"))
        return Nuclear(tier1.toString(), hashes, saves)
    }

    /** About 60 saves (up to 3 at each question), each answered with every utterance. */
    private fun fanout(saves: List<Saved>): String {
        val out = StringBuilder(Canon.json(header("utterances" to Corpora.UTTERANCES))).append('\n')
        for ((i, saved) in saves.withIndex()) {
            val seed = i + 1
            var open: String? = null
            val results = Corpora.UTTERANCES.mapIndexed { u, said ->
                val rnd = LoggingRandom(Random(seed))
                val game = NuclearWar(audio, rnd)
                val lines = Canon.Turns(freshAsks = true)
                val t0 = game.open(saved)
                val line0 = lines.line(0, listOf("open"), rnd.take(), t0, game.save())
                val h0 = Canon.hash(Canon.Raw(line0))
                check(open == null || open == h0) { "fanout: opening save $i isn't the same each time" }
                open = h0
                val understands = game.understands(said)
                val t1 = game.answer(said)
                val line1 = lines.line(1, listOf("answer", said), rnd.take(), t1, game.save())
                listOf(u, t1.heard?.answer, t1.heard?.how, t1.node, understands, Canon.hash(Canon.Raw(line1)))
            }
            out.append(Canon.json(linkedMapOf(
                "save" to linkedMapOf("node" to saved.node, "ended" to saved.ended, "vars" to Canon.vars(saved.vars)),
                "seed" to seed, "open" to open, "results" to results,
            ))).append('\n')
        }
        return out.toString()
    }

    // ----- Dump mode -----

    /** The lines for a dump spec (README section 11). */
    fun dump(spec: String): List<String> {
        val parts = spec.split('/')
        if (parts.size == 3 && parts[0] == NuclearWar.ID && parts[1] == "game") {
            val seed = parts[2].toInt()
            val lines = mutableListOf<String>()
            val game = NuclearPlayer(audio).game(seed) { lines += it }
            return listOf(Canon.json(linkedMapOf("seed" to seed, "turns" to game.lines, "end" to game.end))) + lines
        }
        val v = variants.firstOrNull { it.name == parts[0] } ?: throw IllegalArgumentException("no variant ${parts[0]} in $spec")
        return when {
            parts.size == 2 && parts[1] == "nodes" -> v.map.nodes.values.map { Canon.json(Canon.node(it)) }
            parts.size == 3 && parts[1] == "walk" -> {
                val w = parts[2].toInt()
                val lines = mutableListOf(Canon.json(linkedMapOf("walk" to w, "seed" to MapWalker.seed(w))))
                MapWalker(v.map, entries(v)).walk(w) { lines += it }
                lines
            }
            else -> throw IllegalArgumentException("can't read the dump spec $spec (README section 11)")
        }
    }

    companion object {
        const val TIER1_WALKS = 6
        const val MAP_WALKS = 500
        const val NUCLEAR_TIER1 = 10
        const val FANOUT_PER_QUESTION = 3
        const val NUCLEAR_GAMES = 3000
    }
}
