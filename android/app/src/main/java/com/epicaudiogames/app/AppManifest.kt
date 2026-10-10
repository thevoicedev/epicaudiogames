package com.epicaudiogames.app

import android.content.res.AssetManager
import android.util.Log
import com.epicaudiogames.engine.Line
import com.epicaudiogames.engine.Step
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

/**
 * The app's own audio and help, from content/app/app.json (merged into the assets as app/app.json): built by
 * tools/app_audio.py from tools/app_text.toml, so the words shown are the words spoken. The intro's [sting], the
 * [earcons]' lengths, the [welcome] and the [help] pages for this app: a page marked for iOS is left out, one marked
 * for Android or for neither kept, in the file's order.
 *
 * A page's clips are steps in the maps' format (docs/MAP_FORMAT.md), so AudioPlayer plays them as a turn, with "app" as
 * the game (assets/app/<path>.m4a). Plain Kotlin, tested on the JVM with the real file (AppManifestTest). iOS: EpicAppCore's
 * AppManifest.swift.
 */
class AppManifest(
    val sting: Sting?,
    /** Each earcon's length in seconds, by its name ("listen-start"). */
    val earcons: Map<String, Double>,
    val welcome: HelpPage?,
    val help: List<HelpPage>,
) {
    /** The help page [id] ("voice"), if this app has one. */
    fun topic(id: String): HelpPage? = help.firstOrNull { it.id == id }

    companion object {
        /** The app's folder in the assets, and the "game" its clips are played as. */
        const val FOLDER = "app"
        /** This app's pages, besides those for both. */
        const val PLATFORM = "android"
        private const val TAG = "AppManifest"

        /** The manifest in the app's assets; null if the build has none (placeholder content) or it can't be read. */
        fun load(assets: AssetManager): AppManifest? = runCatching {
            parse(assets.open("$FOLDER/app.json").bufferedReader().use { it.readText() })
        }.onFailure { Log.w(TAG, "no app.json to read", it) }.getOrNull()

        /** Reads app.json's [text], keeping the pages for [platform] (and those for every platform). */
        fun parse(text: String, platform: String = PLATFORM): AppManifest {
            val root = Json.parseToJsonElement(text).jsonObject
            val sting = (root["sting"] as? JsonObject)?.let { s ->
                Sting(
                    file = s.str("file"),
                    seconds = s.num("dur"),
                    voiceAt = s.num("voiceAt"),
                    voiceEnd = s.num("voiceEnd"),
                    text = s.str("text"),
                )
            }
            val earcons = (root["earcons"] as? JsonObject).orEmpty().mapValues { (_, e) -> (e as? JsonObject)?.num("dur") ?: 0.0 }
            fun mine(page: JsonObject) = page.optStr("platform").let { it == null || it == platform }
            val welcome = (root["welcome"] as? JsonObject)?.takeIf(::mine)?.let { page("welcome", it) }
            val help = (root["help"] as? JsonArray).orEmpty().map { it.jsonObject }.filter(::mine).map { page(it.str("id"), it) }
            return AppManifest(sting, earcons, welcome, help)
        }

        private fun page(id: String, o: JsonObject) = HelpPage(
            id = id,
            title = o.str("title"),
            summary = o.optStr("summary") ?: "",
            text = (o["text"] as? JsonArray).orEmpty().map { (it as JsonPrimitive).content },
            clipParagraph = (o["clipParagraph"] as? JsonArray).orEmpty().map { (it as JsonPrimitive).intOrNull ?: -1 },
            steps = (o["steps"] as? JsonArray).orEmpty().mapNotNull { step(it.jsonObject) },
            links = (o["links"] as? JsonArray).orEmpty().map { l ->
                val lo = l.jsonObject
                HelpLink(lo.str("label"), lo.str("url"))
            },
        )

        /** A clip, a pause or a bed, as GameMap reads them; a step of another kind is left out. */
        private fun step(o: JsonObject): Step? = when {
            "play" in o -> Step.Play(
                path = o.str("play"),
                dur = o.num("dur"),
                lines = (o["lines"] as? JsonArray).orEmpty().map { l ->
                    val lo = l.jsonObject
                    Line(
                        at = lo.num("at"),
                        len = (lo["len"] as? JsonPrimitive)?.doubleOrNull ?: 0.0,
                        who = lo.optStr("who") ?: "",
                        text = lo.str("text"),
                        words = (lo["w"] as? JsonArray)?.map { (it as JsonPrimitive).content.toDouble() },
                    )
                },
                sfx = (o["sfx"] as? JsonPrimitive)?.booleanOrNull == true,
            )
            "pause" in o -> Step.Pause(o.num("pause"))
            "bed" in o -> Step.Bed(
                path = (o["bed"] as? JsonPrimitive)?.takeIf { it.isString }?.content,
                volume = (o["volume"] as? JsonPrimitive)?.doubleOrNull ?: 1.0,
                dur = (o["dur"] as? JsonPrimitive)?.doubleOrNull ?: 0.0,
            )
            else -> null
        }

        private fun JsonObject.str(key: String): String =
            optStr(key) ?: throw IllegalArgumentException("app.json: missing \"$key\" in $this")

        private fun JsonObject.optStr(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

        private fun JsonObject.num(key: String): Double =
            (this[key] as? JsonPrimitive)?.doubleOrNull ?: throw IllegalArgumentException("app.json: missing \"$key\"")

        private fun JsonArray?.orEmpty(): List<JsonElement> = this ?: emptyList()

        private fun JsonObject?.orEmpty(): Map<String, JsonElement> = this ?: emptyMap()
    }
}

/** The intro's sound: [file] in the app's folder, [seconds] long, the voice saying [text] from [voiceAt] to [voiceEnd]. */
data class Sting(val file: String, val seconds: Double, val voiceAt: Double, val voiceEnd: Double, val text: String)

/**
 * A page the app shows and can read aloud: the welcome, or a help topic. [text] is its paragraphs as shown; [steps] its
 * clips (one per paragraph, with pauses, and the earcons it plays as examples), each clip's paragraph in
 * [clipParagraph] (-1 for an earcon, which has no words).
 */
data class HelpPage(
    val id: String,
    val title: String,
    /** One line about it, for the list of topics. */
    val summary: String,
    val text: List<String>,
    val clipParagraph: List<Int>,
    val steps: List<Step>,
    val links: List<HelpLink>,
) {
    /** Each clip's lines, in order (a clip is a Play step; AudioPlayer.position counts them so). */
    val clipLines: List<List<Line>> get() = steps.filterIsInstance<Step.Play>().map { it.lines }

    /** Whether it has anything to play. */
    val hasClips: Boolean get() = steps.any { it is Step.Play }
}

/** A link under a help page's text: a web page, or an email (mailto:). */
data class HelpLink(val label: String, val url: String)
