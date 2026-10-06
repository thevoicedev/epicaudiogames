package com.epicaudiogames.engine.nuclear

import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.MapException
import com.epicaudiogames.engine.Step
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * Nuclear War's audio, games/nuclear-war/clips.json (made by tools/games/nuclearwar.py): Don's lines by their text;
 * the skill's recorded clips by their path on the Mini Games CDN ("nuclear-war/UK/Hello.mp3"); the skill's audio
 * table, which says which clips each of its getters chooses from; and the rules, mixed ahead as one clip.
 */
class NuclearAudio(
    val who: Map<String, String>,
    private val voice: Map<String, Step.Play>,
    private val clips: Map<String, Step.Play>,
    private val table: JsonObject,
    private val mixes: Map<String, Step.Play>,
) {
    /** Don saying a line ([missing] notes the lines without a clip; tests fail on them). */
    fun don(text: String): Step.Play = voice[text] ?: placeholder(text).also { missing += text }

    val missing = mutableSetOf<String>()

    fun has(text: String) = text in voice

    /** A recorded clip; null when the skill's table has no such file (it would 404 on Alexa: nothing plays). */
    fun clip(path: String?): Step.Play? = path?.let { clips[it] ?: if (clips.isEmpty()) Step.Play("audio/$it", 1.0, emptyList()) else null }

    fun mix(name: String): Step.Play? = mixes[name]

    /** A field of the table for a country ("Representative") or of its sounds ("sfx"). */
    fun path(section: String, field: String): String? = ((table[section] as? JsonObject)?.get(field) as? JsonPrimitive)?.content

    /** A field that is a list of paths ("GeneralChat"). */
    fun paths(section: String, field: String): List<String> =
        ((table[section] as? JsonObject)?.get(field) as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()

    /** A field that maps names to paths ("Attack": city to clip). */
    fun keyed(section: String, field: String, key: String): String? =
        (((table[section] as? JsonObject)?.get(field) as? JsonObject)?.get(key) as? JsonPrimitive)?.content

    /** A motivator comment: one path, or a list to choose from. */
    fun options(section: String, field: String, key: String): List<String> =
        when (val e = ((table[section] as? JsonObject)?.get(field) as? JsonObject)?.get(key)) {
            is JsonPrimitive -> listOf(e.content)
            is JsonArray -> e.map { it.jsonPrimitive.content }
            else -> emptyList()
        }

    companion object {
        fun load(file: File) = parse(file.readText())

        fun parse(text: String): NuclearAudio {
            val root = Json.parseToJsonElement(text).jsonObject
            if (root["format"]?.jsonPrimitive?.content != "1") throw MapException("clips.json: only format 1 is supported")
            fun plays(key: String) = (root[key] as? JsonObject)?.mapValues { (_, v) -> play(v.jsonObject) } ?: emptyMap()
            return NuclearAudio(
                who = (root["who"] as? JsonObject)?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap(),
                voice = plays("voice"),
                clips = plays("clips"),
                table = root["table"] as? JsonObject ?: JsonObject(emptyMap()),
                mixes = plays("mixes"),
            )
        }

        /** Before the audio is made (tests, the typing player): every line and clip a placeholder. */
        fun placeholder() = NuclearAudio(WHO, emptyMap(), emptyMap(), JsonObject(emptyMap()), emptyMap())

        private fun placeholder(text: String) = Step.Play("don/missing", 1.0, listOf(Line(0.0, 1.0, "HOST", text)))

        val WHO = mapOf("HOST" to "") + World.LANDS.associate { it.who to it.leader }

        private fun play(o: JsonObject) = Step.Play(
            path = o.getValue("play").jsonPrimitive.content,
            dur = o.getValue("dur").jsonPrimitive.doubleOrNull ?: 0.0,
            lines = (o["lines"] as? JsonArray)?.map { l ->
                val lo = l.jsonObject
                Line(
                    at = lo.getValue("at").jsonPrimitive.doubleOrNull ?: 0.0,
                    len = (lo["len"] as? JsonPrimitive)?.doubleOrNull ?: 0.0,
                    who = lo.getValue("who").jsonPrimitive.content,
                    text = lo.getValue("text").jsonPrimitive.content,
                    words = (lo["w"] as? JsonArray)?.map { it.jsonPrimitive.content.toDouble() },
                )
            } ?: emptyList(),
            sfx = (o["sfx"] as? JsonPrimitive)?.booleanOrNull == true,
        )
    }
}
