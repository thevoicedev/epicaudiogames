package com.epicaudiogames.app.analytics

import com.epicaudiogames.app.ui.ShopSource
import com.epicaudiogames.app.ui.Tab
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Something that happened in the app, for the usage data (docs/DESIGN.md › Usage data): an event of
 * web/analytics/events.json, the whitelist our server checks every event against, with some of the details it lists
 * for that event and nothing else. Made by [Events], never by hand. iOS: Analytics/Events.swift.
 */
data class Event(val name: String, val props: Map<String, Any> = emptyMap())

/** Where the microphone was asked for: mic_permission's "where". */
enum class MicAsked(val key: String) {
    ONBOARDING("onboarding"),
    GAME("game"),
    SETTINGS("settings"),
}

/** Where help was opened from: help_viewed's "source". Which topic is never sent. */
enum class HelpSource(val key: String) {
    TAB("tab"),
    GAME("game"),
    ONBOARDING("onboarding"),
}

/** How a purchase ended: purchase_result's "result". */
enum class PurchaseResult(val key: String) {
    PURCHASED("purchased"),
    /** Paid for in a way that takes a while (cash at a shop, a parent's approval): Play says when it's paid. */
    PENDING("pending"),
    CANCELLED("cancelled"),
    FAILED("failed"),
    /** The player had it already (bought on another phone). */
    OWNED("owned"),
}

/** How "Restore purchases" went: restore's "result". */
enum class RestoreResult(val key: String) {
    RESTORED("restored"),
    NONE("none"),
    FAILED("failed"),
}

/**
 * Every event the app sends, each with only the details web/analytics/events.json lists for it: which game, node,
 * pack or product (the maps' and the catalog's ids), counts and times, yes or no, and a few fixed words. Never
 * anything the player says or types, no words of a story, no audio, nothing about a screen reader or any setting, not
 * which help topic was read, nothing about the phone but the coarse details in [About] (docs/DESIGN.md › Usage data's
 * never-sent list). This file is the whole list: EventsTest holds it to events.json, and finds every place in the app
 * that names an event. iOS: Analytics/Events.swift.
 */
object Events {
    // ----- The app (AppModel) -----

    /**
     * The app came on screen: [cold] the first time since it started; [first] with no random ID yet, so the first time
     * since it was installed (or since its usage data was deleted, or turned off and on).
     */
    fun appOpen(cold: Boolean, first: Boolean) = Event("app_open", mapOf("cold" to cold, "first" to first))

    /** The app went off screen (the home screen, another app, the screen locked) after [seconds] on it. */
    fun appBackground(seconds: Long) = Event("app_background", mapOf("seconds" to seconds))

    /** The intro ended: by itself, or [skipped]. */
    fun introFinished(skipped: Boolean) = Event("intro_finished", mapOf("skipped" to skipped))

    /** Onboarding ended: Start playing ([completed]), or Skip. */
    fun onboardingFinished(completed: Boolean) =
        Event("onboarding_finished", mapOf("outcome" to if (completed) "completed" else "skipped"))

    /** What the player said to Android's microphone question, and where the app asked it. */
    fun micPermission(granted: Boolean, where: MicAsked) =
        Event("mic_permission", mapOf("result" to if (granted) "granted" else "denied", "where" to where.key))

    /** A tab shown. */
    fun tabView(tab: Tab) = Event("tab_view", mapOf("tab" to tab.key))

    /** A help topic opened, from the Help tab or a game (never which one). */
    fun helpViewed(source: HelpSource) = Event("help_viewed", mapOf("source" to source.key))

    // ----- The games (GameController) -----

    /** A game opened: [resumed] where the player left it. */
    fun gameOpen(game: String, resumed: Boolean) = Event("game_open", mapOf("game" to game, "resumed" to resumed))

    /**
     * A game reached an end at [node]: a chapter's end, a game over, or one of its ends (the maps' "ending", which the
     * whitelist calls "end"; any other kind is an end too, as the end panel says "The end" for it).
     */
    fun gameEnd(game: String, kind: String, node: String) = Event(
        "game_end",
        mapOf("game" to game, "kind" to endKind(kind), "node" to node),
    )

    /** Next chapter, to the chapter [next]. */
    fun chapterNext(game: String, next: String) = Event("chapter_next", mapOf("game" to game, "next" to next))

    /** The free part of a game is over: [pack] has what comes next. */
    fun lockedEnd(game: String, pack: String) = Event("locked_end", mapOf("game" to game, "pack" to pack))

    /** Play again, Try again or Start again. */
    fun gameRestart(game: String) = Event("game_restart", mapOf("game" to game))

    /**
     * A game closed: where it was ([node]; none if it never got going), how many turns it played and for how long,
     * and how many answers were spoken, typed and tapped and how many questions went unanswered (counts only: never
     * an answer).
     */
    fun gameLeave(
        game: String,
        node: String?,
        turns: Int,
        seconds: Long,
        spoken: Int,
        typed: Int,
        tapped: Int,
        silences: Int,
    ) = Event(
        "game_leave",
        buildMap {
            put("game", game)
            if (node != null) put("node", node)
            put("turns", turns)
            put("seconds", seconds)
            put("answers_voice", spoken)
            put("answers_typed", typed)
            put("answers_tapped", tapped)
            put("silences", silences)
        },
    )

    /** The game went wrong and stopped, at [node] (none if it went wrong as it opened). */
    fun gameError(game: String, node: String?) =
        Event("game_error", if (node != null) mapOf("game" to game, "node" to node) else mapOf("game" to game))

    // ----- The shop (AppModel, Store) -----

    /** The Shop tab, or a store sheet, opened [from] somewhere. */
    fun shopView(from: ShopSource) = Event("shop_view", mapOf("source" to from.key))

    /** Buy pressed, and Play's purchase sheet shown for [product]. */
    fun purchaseStart(product: String) = Event("purchase_start", mapOf("product" to product))

    /** How a purchase of [product] ended. */
    fun purchaseResult(product: String, result: PurchaseResult) =
        Event("purchase_result", mapOf("product" to product, "result" to result.key))

    /** "Restore purchases": how it went, and how many products the Play account has bought. */
    fun restore(result: RestoreResult, count: Int) =
        Event("restore", mapOf("result" to result.key, "count" to count))

    /** A pack's download: whether it installed, how long it took and how much came down. */
    fun packDownload(pack: String, installed: Boolean, seconds: Long, bytes: Long) = Event(
        "pack_download",
        mapOf(
            "pack" to pack, "result" to if (installed) "installed" else "failed", "seconds" to seconds,
            "bytes" to bytes,
        ),
    )

    /** An end's kind as the whitelist names it. */
    internal fun endKind(kind: String) = when (kind) {
        "chapter", "gameover" -> kind
        else -> "end"
    }

    // ----- The whitelist -----

    /** web/analytics/events.json's "common": the details every event has (see [Stamp]), and their types. */
    val COMMON: Map<String, String> = linkedMapOf(
        "install_id" to "uuid",
        "session_id" to "uuid",
        "seq" to "int",
        "ts" to "iso8601",
        "app_version" to "string",
        "build" to "string",
        "platform" to "enum:ios,android",
        "form_factor" to "enum:phone,tablet,desktop,watch",
        "os_version" to "string",
        "lang" to "string",
    )

    /** web/analytics/events.json's "events": each event's details and their types. Nothing else is sent. */
    val ALLOWED: Map<String, Map<String, String>> = linkedMapOf(
        "app_open" to mapOf("cold" to "bool", "first" to "bool"),
        "app_background" to mapOf("seconds" to "int"),
        "intro_finished" to mapOf("skipped" to "bool"),
        "onboarding_finished" to mapOf("outcome" to "enum:completed,skipped"),
        "mic_permission" to mapOf("result" to "enum:granted,denied", "where" to "enum:onboarding,game,settings"),
        "tab_view" to mapOf("tab" to "enum:games,shop,help,settings"),
        "help_viewed" to mapOf("source" to "enum:tab,game,onboarding"),
        "game_open" to mapOf("game" to "id", "resumed" to "bool"),
        "game_end" to mapOf("game" to "id", "kind" to "enum:chapter,gameover,end", "node" to "id"),
        "chapter_next" to mapOf("game" to "id", "next" to "id"),
        "locked_end" to mapOf("game" to "id", "pack" to "id"),
        "game_restart" to mapOf("game" to "id"),
        "game_leave" to mapOf(
            "game" to "id", "node" to "id", "turns" to "int", "seconds" to "int", "answers_voice" to "int",
            "answers_typed" to "int", "answers_tapped" to "int", "silences" to "int",
        ),
        "game_error" to mapOf("game" to "id", "node" to "id"),
        "shop_view" to mapOf("source" to "enum:tab,card,menu,locked_end"),
        "purchase_start" to mapOf("product" to "id"),
        "purchase_result" to mapOf("product" to "id", "result" to "enum:purchased,pending,cancelled,failed,owned"),
        "restore" to mapOf("result" to "enum:restored,none,failed", "count" to "int"),
        "pack_download" to mapOf(
            "pack" to "id", "result" to "enum:installed,failed", "seconds" to "int", "bytes" to "int",
        ),
    )

    /**
     * An id, as web/analytics/whitelist.js takes it: a game, node, pack or product id as the maps and the catalog have
     * them, capitals and a leading underscore included ("L1_win", "_restart").
     */
    val ID = Regex("^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,79}$")
    private val UUID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", RegexOption.IGNORE_CASE)
    private val ISO8601 = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,9})?(Z|[+-]\\d{2}:\\d{2})$")
    const val MAX_INT = 1_000_000_000L
    const val MAX_STRING = 64

    /**
     * Why an event can't be sent, or null if it can: an event or a detail the whitelist hasn't got, or a value that
     * isn't of the detail's type (the server would turn away the whole batch it came in).
     */
    fun problem(name: String, props: Map<String, Any>): String? {
        val allowed = ALLOWED[name] ?: return "unknown event \"$name\""
        for ((key, value) in props) {
            val type = allowed[key] ?: return "$name has no property \"$key\""
            if (!fits(type, value)) return "$name.$key has the wrong type"
        }
        return null
    }

    /** Whether [value] is of the whitelist's [type], as web/analytics/whitelist.js checks it. */
    fun fits(type: String, value: Any?): Boolean = when {
        type == "bool" -> value is Boolean
        type == "int" -> (value is Int || value is Long) && (value as Number).toLong() in 0..MAX_INT
        type == "id" -> value is String && ID.matches(value)
        type == "uuid" -> value is String && UUID.matches(value)
        type == "iso8601" -> value is String && ISO8601.matches(value)
        type == "string" -> value is String && value.length <= MAX_STRING && value == text(value)
        type.startsWith("enum:") -> value is String && value in type.removePrefix("enum:").split(",")
        else -> false
    }

    /**
     * An event as the server takes it: one JSON object with its name, its details, and the [stamp]'s common ones.
     * A common detail that's empty, or isn't of its type, is left out (every one but the ID, the session and the
     * number may be), so it can never cost the batch.
     */
    fun json(event: Event, stamp: Stamp): String = buildJsonObject {
        put("name", event.name)
        put("props", buildJsonObject {
            for ((key, value) in event.props) {
                when (value) {
                    is Boolean -> put(key, value)
                    is Number -> put(key, value)
                    else -> put(key, value.toString())
                }
            }
        })
        put("install_id", stamp.installId)
        put("session_id", stamp.sessionId)
        put("seq", stamp.seq)
        iso(stamp.at)?.let { put("ts", it) }
        val common = mapOf(
            "app_version" to text(stamp.about.appVersion),
            "build" to text(stamp.about.build),
            "platform" to "android",
            "form_factor" to stamp.about.formFactor,
            "os_version" to text(stamp.about.osVersion),
            "lang" to text(stamp.about.lang),
        )
        for ((key, value) in common) {
            if (value.isNotEmpty() && fits(COMMON.getValue(key), value)) put(key, JsonPrimitive(value))
        }
    }.toString()

    /** A time as the server takes it, UTC to the millisecond ("2026-10-09T09:41:00.123Z"); none outside 1970–2999. */
    fun iso(millis: Long): String? {
        if (millis !in 0 until YEAR_3000) return null
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))
    }

    /** Text from the phone (its Android version, language) as a "string" detail: no control characters, at most 64. */
    fun text(value: String): String {
        val clean = value.filter { it >= ' ' && it != '\u007f' && !it.isSurrogate() }
        return clean.take(MAX_STRING)
    }

    /** 3000-01-01T00:00:00Z: the server takes times before it. */
    private const val YEAR_3000 = 32_503_680_000_000L
}

/**
 * The details every event has (events.json's "common"), besides its own: the random ID, the session and the event's
 * number in it (never used twice in a session: the server keeps an event that comes twice once), when it happened
 * (ms since 1970), and what the app runs on.
 */
data class Stamp(val installId: String, val sessionId: String, val seq: Int, val at: Long, val about: About)

/**
 * What the app runs on, coarsely: its version and build, Android's version, the phone's language, and the kind of
 * device (phone, tablet, desktop or watch; never its make or model).
 */
data class About(
    val appVersion: String,
    val build: String,
    val osVersion: String,
    val lang: String,
    val formFactor: String,
)

/**
 * The kind of device, as events.json's form_factor has it (docs/DESIGN.md › Tablets…): a computer (a Chromebook: [pc],
 * Android's FEATURE_PC), a watch, a tablet (a screen whose smallest width is 600 dp or more, as a foldable open), or
 * a phone. iOS: the user interface idiom.
 */
fun formFactor(watch: Boolean, pc: Boolean, smallestWidthDp: Int): String = when {
    watch -> "watch"
    pc -> "desktop"
    smallestWidthDp >= 600 -> "tablet"
    else -> "phone"
}
