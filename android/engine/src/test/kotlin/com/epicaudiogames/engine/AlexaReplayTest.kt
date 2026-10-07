package com.epicaudiogames.engine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * Replays the walks that tools/parity.js recorded in the real Alexa skill: every turn must play the same clips, in
 * the same order, and end or leave the game at the same time. Where the skill picked a random branch, the engine
 * is given the same pick. Skipped when there are no recordings (they need the all-minigames-sites repo).
 */
class AlexaReplayTest {
    /** A turn where a map deliberately differs from the skill. The walk stops there. */
    private class Known(val why: String, val applies: (at: String, said: String, alexa: List<String>, ours: List<String>) -> Boolean)

    private val known = listOf(
        Known("Signal Decoders: the skill also hears \"one\" (a follow word) in \"the second one\" and asks again; the " +
            "map takes the longer phrase, hide, which is why the skill lists \"the second one\" as a hide word") { at, said, _, _ ->
            at == "ai-choice" && said == "the second one"
        },
        Known("Frootopia: the app has stories 2 to 5 (in a pack), so story 1's ending plays its teaser for story 2, as " +
            "the skill does when its series is switched on (FROOTOPIA_SERIES)") { _, _, alexa, ours ->
            ours == alexa + "scenes/fr-sting"
        },
        // fixed: the skills took "of course not" and "I'm not sure" as a yes, and "I don't know" as a no
        Known("A negated phrase without an opposite (\"of course not\", \"probably not\", \"let's not hide\") doesn't " +
            "count, and an answer that isn't sure (\"I'm not sure\", \"I don't know\") is neither yes nor no") { _, said, _, _ ->
            val t = Text.normalise(said)
            Text.unsure(t) || t.split(' ').any { it in setOf("don't", "dont", "not", "never") }
        },
        // fixed: the skills' digit reader took "to", "for", "won" and "oh" for numbers anywhere ("I want to play" was 2)
        Known("\"To\", \"too\", \"for\", \"fore\", \"won\" and \"oh\" are numbers only next to another number") { _, said, _, _ ->
            Text.normalise(said).split(' ').any { it in setOf("to", "too", "for", "fore", "won", "oh") }
        },
        // fixed: Noodle Rush's skill asked again on everyday yeses and noes ("okay", "let's do it", "no way")
        Known("Noodle Rush takes more ways to say yes and no (\"okay\", \"let's do it\", \"no way\", \"I'm ready\"), where " +
            "the skill only asked the question again") { _, said, alexa, _ ->
            Text.normalise(said) in NOODLE_RUSH_WORDS && alexa.size == 1 && alexa[0].startsWith("prompts/")
        },
    )

    /** The exact-match answers Noodle Rush's map gained after the recordings were made. */
    private val NOODLE_RUSH_WORDS = setOf(
        "all right", "alright", "i do", "i don't", "i don't want to", "i want to", "i would", "i wouldn't",
        "i'm ready", "im ready", "let's do it", "let's go", "let's play", "lets do it", "lets go", "lets play",
        "no i don't", "no i wouldn't", "no thank you", "no way", "not now", "ok", "okay", "ready", "sure thing",
        "yeah i'm ready", "yeah let's go", "yes i do", "yes i want to", "yes i would", "yes i'm ready",
        "yes let's go", "yes let's play",
    ).map { Text.normalise(it) }.toSet()

    private val gamesDir = File(System.getProperty("games.dir") ?: "../../games")
    private val recordings = File(gamesDir.parentFile, "tools/cache/parity")

    @Test
    fun mapsPlayWhatAlexaPlays() {
        val files = recordings.listFiles().orEmpty().filter { it.name.endsWith(".json") }.sortedBy { it.name }
        assumeTrue("no recordings in $recordings (run node tools/parity.js)", files.isNotEmpty())
        val problems = mutableListOf<String>()
        for (file in files) {
            val root = Json.parseToJsonElement(file.readText()).jsonObject
            val id = root.getValue("game").jsonPrimitive.content
            val map = GameMap.load(File(gamesDir, "$id/map.json"))
            val walks = root.getValue("walks").jsonArray.map { w -> w.jsonObject.getValue("turns").jsonArray.map { it.jsonObject } }
            var agreed = 0
            var stopped = 0
            val mine = mutableListOf<String>()
            for ((w, turns) in walks.withIndex()) {
                when (val problem = replay(map, turns)) {
                    null -> agreed++
                    KNOWN -> stopped++
                    else -> mine += "$id walk ${w + 1}: $problem"
                }
            }
            problems += mine.take(8)
            println("$id: ${walks.sumOf { it.size }} turns in ${walks.size} walks: $agreed the same as Alexa" +
                if (stopped > 0) ", $stopped the same up to a known difference" else "")
        }
        assertTrue(problems.take(15).joinToString("\n", "\n"), problems.isEmpty())
    }

    /** Null if the engine plays the walk exactly as Alexa did, else what differed. */
    private fun replay(map: GameMap, turns: List<JsonObject>): String? {
        var session = Session(map) { 0 }
        val at = turns[0]["node"]?.jsonPrimitive?.content
        if (turns[0].getValue("said").jsonPrimitive.content == "@at" && at != null) {
            session.restore(Saved(at, emptyMap(), false))      // a grid cell: straight to the question
        } else {
            differs(session.start(), turns[0])?.let { return "launch: $it" }
        }
        for (i in 1 until turns.size) {
            val recorded = turns[i]
            val said = recorded.getValue("said").jsonPrimitive.content
            val saved = session.save()
            var firstTry: String? = null
            var next: Session? = null
            for (k in 0 until 4) {
                val s = Session(map) { n -> k % n }
                s.restore(saved)
                val turn = if (said == "@next") s.nextChapter() else s.answer(said)
                val why = differs(turn, recorded)
                if (why == null) {
                    next = s
                    break
                }
                if (firstTry == null) firstTry = "(heard: ${turn.heard?.how}) $why"
            }
            if (next == null) {
                val alexa = recorded.getValue("clips").jsonArray.map { it.jsonPrimitive.content }
                val ours = Session(map) { 0 }.apply { restore(saved) }
                    .let { s -> if (said == "@next") s.nextChapter() else s.answer(said) }
                    .steps.filterIsInstance<Step.Play>().map { it.path }
                if (known.any { it.applies(saved.node, said, alexa, ours) }) return KNOWN
                return "turn ${i + 1} at ${saved.node}, \"$said\": $firstTry"
            }
            session = next!!
        }
        return null
    }

    private companion object {
        const val KNOWN = "known"
    }

    private fun differs(turn: Turn, recorded: JsonObject): String? {
        val alexa = recorded.getValue("clips").jsonArray.map { it.jsonPrimitive.content }
        val ours = turn.steps.filterIsInstance<Step.Play>().map { it.path }
        val phase = when {
            turn.quit -> "left"
            turn.end != null -> "over"
            else -> "playing"
        }
        val alexaPhase = recorded.getValue("phase").jsonPrimitive.content
        return when {
            ours != alexa -> "Alexa played $alexa, the map $ours"
            phase != alexaPhase -> "Alexa is $alexaPhase (${recorded["state"]?.jsonPrimitive?.content}), the map $phase"
            else -> null
        }
    }
}
