package com.epicaudiogames.app.analytics

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/**
 * The server's own whitelist, read from web/ as the server reads it: web/analytics/events.json, and the id pattern in
 * web/analytics/whitelist.js. The tests check what the app sends against this, not against the app's own copy
 * ([Events.ALLOWED]), so the two can't agree on a mistake. (The tests run in android/app.)
 */
object Whitelist {
    val file = File("../../web/analytics/events.json")
    private val root: JsonObject = Json.parseToJsonElement(file.readText()).jsonObject

    /** "common": each common field's type. */
    val common: Map<String, String> = types(root.getValue("common").jsonObject)

    /** "events": each event's properties and their types. */
    val events: Map<String, Map<String, String>> =
        root.getValue("events").jsonObject.mapValues { (_, props) -> types(props.jsonObject) }

    /** whitelist.js's `const ID = /…/;`. */
    val idPattern: String = run {
        val js = File("../../web/analytics/whitelist.js").readText()
        val match = checkNotNull(Regex("const ID = /(.+)/;").find(js)) { "no ID pattern in whitelist.js" }
        match.groupValues[1]
    }
    private val id = Regex(idPattern)
    private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", RegexOption.IGNORE_CASE)
    private val iso = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,9})?(Z|[+-]\\d{2}:\\d{2})$")

    private fun types(o: JsonObject) = o.mapValues { (_, type) -> type.jsonPrimitive.content }

    /**
     * Why the server would turn away this event (one element of a batch, as sent), or null if it would take it:
     * whitelist.js's checkEvent, by the file's types.
     */
    fun problem(event: JsonObject): String? {
        val name = (event["name"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return "no name"
        val allowed = events[name] ?: return "unknown event $name"
        for ((key, value) in event) {
            if (key == "name" || key == "props") continue
            val type = common[key] ?: return "unknown field $key"
            if (!fits(type, value)) return "$key has the wrong type: $value"
        }
        for (key in listOf("install_id", "session_id", "seq")) if (key !in event) return "no $key"
        val props = event["props"] ?: return null
        if (props !is JsonObject) return "props is not an object"
        for ((key, value) in props) {
            val type = allowed[key] ?: return "$name has no property $key"
            if (!fits(type, value)) return "$name.$key has the wrong type: $value"
        }
        return null
    }

    /** Whether a JSON value is of a whitelist type, as whitelist.js's compile() checks it. */
    fun fits(type: String, value: JsonElement): Boolean {
        val p = value as? JsonPrimitive ?: return false
        return when {
            type == "bool" -> !p.isString && p.booleanOrNull != null
            type == "int" -> !p.isString && p.content.toLongOrNull()?.let { it in 0..1_000_000_000L } == true
            type == "id" -> p.isString && id.matches(p.content)
            type == "uuid" -> p.isString && uuid.matches(p.content)
            type == "iso8601" -> p.isString && iso.matches(p.content)
            type == "string" -> p.isString && p.content.length <= 64 && p.content.none { it < ' ' || it == '\u007f' }
            type.startsWith("enum:") -> p.isString && p.content in type.removePrefix("enum:").split(",")
            else -> error("a type the server doesn't know: $type")
        }
    }

    /** A batch as sent (a JSON array of events), each checked; the events, if all of them would be taken. */
    fun batch(body: ByteArray): List<JsonObject> {
        val events = Json.parseToJsonElement(body.toString(Charsets.UTF_8)) as kotlinx.serialization.json.JsonArray
        check(events.size in 1..100) { "${events.size} events in a batch" }
        check(body.size <= 64 * 1024) { "a batch of ${body.size} bytes" }
        return events.map { e ->
            val o = e.jsonObject
            problem(o)?.let { throw AssertionError("the server would refuse ${o["name"]}: $it") }
            o
        }
    }
}
