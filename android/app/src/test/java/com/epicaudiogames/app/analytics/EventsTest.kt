package com.epicaudiogames.app.analytics

import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.ui.ShopSource
import com.epicaudiogames.app.ui.Tab
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.lang.reflect.Modifier

/**
 * What the app can send as usage data, against the server's whitelist (web/analytics/events.json and the id pattern in
 * web/analytics/whitelist.js; docs/DESIGN.md › Usage data): the app's copy of it is the file's; every event it makes
 * is one the server takes, and every one in the file is made somewhere; every place in the app that names an event
 * names one of the file's, with its details; and nothing about accessibility, nothing the player says or types, and
 * no audio can ride along in any event.
 */
class EventsTest {
    @Test
    fun theAppsWhitelistIsTheServers() {
        assertEquals(Whitelist.common, Events.COMMON)
        assertEquals(Whitelist.events, Events.ALLOWED)
        // The same ids: the maps' own (capitals, a leading underscore), as the server takes them.
        assertEquals(Whitelist.idPattern, Events.ID.pattern)
        for (id in listOf("noodle-rush", "L1_win", "L2_intro", "Page1", "_restart", "ac-diffGame", "CHOOSE_COUNTRY")) {
            assertTrue(id, Events.fits("id", id))
        }
    }

    @Test
    fun everyEventTheAppMakesIsOneTheServerTakes() {
        val made = everyEvent()
        for (e in made) {
            assertNull("$e", Events.problem(e.name, e.props))
            assertNull("$e", Whitelist.problem(sent(e)))
        }
        // And every event in the whitelist is one the app makes.
        assertEquals(Whitelist.events.keys, made.map { it.name }.toSet())
    }

    @Test
    fun theMapsEndsAreTheWhitelistsKinds() {
        assertEquals("chapter", Events.endKind("chapter"))
        assertEquals("gameover", Events.endKind("gameover"))
        // The maps' and Nuclear War's last ends are "ending"; the whitelist (and the reports) call them "end".
        assertEquals("end", Events.endKind("ending"))
        assertEquals("end", Events.endKind("something new"))
    }

    @Test
    fun everyPlaceTheAppNamesAnEventIsInTheWhitelist() {
        val sources = File("src/main/java").walk().filter { it.extension == "kt" }.toList()
        assertTrue("no sources found from ${File(".").absolutePath}", sources.size > 20)
        val named = mutableMapOf<String, MutableSet<String>>()
        for (file in sources) {
            val text = file.readText()
            // An event made by name: Event("name", …), and any name handed straight to track, onEvent or event.
            for (call in calls(text, Regex("""\b(Event|track|onEvent|event)\(\s*"([^"]+)""""))) {
                val props = named.getOrPut(call.name) { mutableSetOf() }
                // Its details, in that call: "key" to value.
                Regex(""""([A-Za-z_]+)"\s+to\b""").findAll(call.text).forEach { props += it.groupValues[1] }
                // …and those a map built for it puts: put("key", value).
                Regex("""\bput\(\s*"([A-Za-z_]+)"""").findAll(call.text).forEach { props += it.groupValues[1] }
            }
        }
        for ((name, props) in named) {
            val allowed = Whitelist.events[name]
            assertNotNull("the app names \"$name\", which isn't in events.json", allowed)
            assertTrue("$name: ${props - allowed!!.keys} aren't in events.json", allowed.keys.containsAll(props))
        }
        assertEquals("events made by name", Whitelist.events.keys, named.keys)

        // Every one of Events' makers is used in the app, outside Events.kt: every event is wired.
        val events = sources.single { it.name == "Events.kt" }.readText()
        val makers = Regex("""\n    fun ([a-z][A-Za-z]+)\(""").findAll(events.substringBefore("// ----- The whitelist"))
            .map { it.groupValues[1] }.toList()
        assertEquals(19, makers.size)
        val elsewhere = sources.filter { it.name != "Events.kt" }.joinToString("\n") { it.readText() }
        for (maker in makers) assertTrue("Events.$maker isn't used", "Events.$maker(" in elsewhere)
    }

    @Test
    fun noEventCanCarryAnythingAboutAccessibilityWordsOrAudio() {
        // What's never sent (docs/DESIGN.md › Usage data), as words a detail's name could have.
        val never = setOf(
            "screen", "reader", "talkback", "voiceover", "accessibility", "a11y", "theme", "contrast", "font", "text",
            "size", "scale", "bold", "motion", "speed", "volume", "haptics", "policy", "highlight", "caption", "said",
            "say", "words", "transcript", "utterance", "reply", "typed_text", "partial", "guess", "audio", "recording",
            "speech", "clip", "topic", "model", "device", "manufacturer", "brand", "advertising", "gaid", "location",
            "latitude", "longitude", "ip", "email", "name",
        )
        // …and every setting there is, by its key, as it is and in snake case (a new setting is covered by itself).
        val settings = AppSettings::class.java.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && it.type == String::class.java }
            .map { it.get(null) as String }
            .filter { it.startsWith("settings.") }
            .map { it.removePrefix("settings.") }
        assertTrue(settings.size >= 18)
        val settingNames = settings.flatMap { listOf(it.lowercase(), snake(it)) }.toSet()
        for (allowed in listOf(Whitelist.events, Events.ALLOWED)) {
            for ((event, props) in allowed) {
                for (prop in props.keys) {
                    assertFalse("$event.$prop names a setting", prop.lowercase() in settingNames)
                    val words = prop.lowercase().split('_')
                    assertTrue("$event.$prop: ${words.filter { it in never }}", words.none { it in never })
                    // A detail is a count, yes or no, one of a few words, or an id: never free text.
                    assertFalse("$event.$prop is free text", props.getValue(prop) == "string")
                }
            }
        }
        // And whatever the app's code asked, the whitelist keeps such details out.
        val forbidden = mapOf(
            "screen_reader" to true, "talkback" to true, "theme" to "contrast", "text_scale" to 1.3, "voice_speed" to 2,
            "music_volume" to 0, "answer_time" to "longest", "mic_auto" to "never", "said" to "yes please",
            "text" to "Gribbo: who goes there?", "audio" to "scenes/q1", "topic" to "voice", "model" to "Pixel 9",
        )
        for ((event, props) in Events.ALLOWED) {
            val good = props.keys.associateWith { sample(props.getValue(it)) }
            assertNull(event, Events.problem(event, good))
            for ((key, value) in forbidden) assertNotNull("$event + $key", Events.problem(event, good + (key to value)))
        }
        // Words in an id's place (an answer passed off as a node) aren't an id.
        for (words in listOf("yes please", "Who goes there?", "I'd like the cake", "", "x".repeat(81))) {
            val end = mapOf("game" to "noodle-rush", "kind" to "end", "node" to words)
            assertNotNull(words, Events.problem("game_end", end))
        }
    }

    @Test
    fun anEventAsSentIsWhatTheServerTakes() {
        val stamp = Stamp(
            installId = "4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10",
            sessionId = "9d7e1c32-0a4b-4f53-8c6d-1e2f3a4b5c6d",
            seq = 7,
            at = 1_791_538_860_123L,
            about = About("1.0", "3", "15", "en-GB", "tablet"),
        )
        val event = Events.gameOpen("noodle-rush", resumed = true)
        val sent = Json.parseToJsonElement(Events.json(event, stamp)).jsonObject
        assertNull(Whitelist.problem(sent))
        assertEquals(
            setOf("name", "props", "install_id", "session_id", "seq", "ts", "app_version", "build", "platform",
                "form_factor", "os_version", "lang"),
            sent.keys,
        )
        assertEquals("2026-10-09T09:41:00.123Z", sent.getValue("ts").jsonPrimitive.content)
        assertEquals("android", sent.getValue("platform").jsonPrimitive.content)
        assertEquals("tablet", sent.getValue("form_factor").jsonPrimitive.content)
        assertEquals("7", sent.getValue("seq").jsonPrimitive.content)
        assertEquals("""{"game":"noodle-rush","resumed":true}""", sent.getValue("props").toString())

        // What the phone says about itself is cleaned, or left out, rather than costing the batch.
        val odd = stamp.copy(at = -1, about = About("1.0", "3", "16\u0000beta", "x".repeat(100), "foldable"))
        val cleaned = Json.parseToJsonElement(Events.json(Events.gameRestart("frootopia"), odd)).jsonObject
        assertNull(Whitelist.problem(cleaned))
        assertFalse("ts" in cleaned)
        assertFalse("form_factor" in cleaned)
        assertEquals("16beta", cleaned.getValue("os_version").jsonPrimitive.content)
        assertEquals(64, cleaned.getValue("lang").jsonPrimitive.content.length)
    }

    @Test
    fun theKindOfDeviceIsCoarse() {
        assertEquals("phone", formFactor(watch = false, pc = false, smallestWidthDp = 411))
        assertEquals("phone", formFactor(watch = false, pc = false, smallestWidthDp = 599))
        assertEquals("tablet", formFactor(watch = false, pc = false, smallestWidthDp = 600))
        assertEquals("desktop", formFactor(watch = false, pc = true, smallestWidthDp = 1200))
        assertEquals("watch", formFactor(watch = true, pc = false, smallestWidthDp = 192))
        val type = Events.COMMON.getValue("form_factor")
        for (kind in listOf("phone", "tablet", "desktop", "watch")) assertTrue(Events.fits(type, kind))
    }

    @Test
    fun whereUsageDataGoes() {
        val release = { extra: String?, testLab: Boolean -> UsageData.serverFor(debug = false, extra, testLab) }
        val debug = { extra: String?, testLab: Boolean -> UsageData.serverFor(debug = true, extra, testLab) }
        // A release build: our server (never one from the launch: any app can launch it), unless it's Play's
        // pre-launch report (Firebase Test Lab) or it's told "off".
        assertEquals(UsageData.SERVER, release(null, false))
        assertEquals(UsageData.SERVER, release("http://evil.example", false))
        assertNull(release(null, true))
        assertNull(release("off", false))
        // A debug build: nowhere, unless it's given a server as it's launched.
        assertNull(debug(null, false))
        assertEquals("http://127.0.0.1:3000", debug("http://127.0.0.1:3000", false))
        assertEquals("http://127.0.0.1:3000", debug("http://127.0.0.1:3000/api/events", false))
        assertEquals("https://epicaudiogames.com", debug("https://epicaudiogames.com/", false))
        assertNull(debug("OFF", false))
        assertNull(debug("127.0.0.1:3000", false))
        assertNull(debug("http://127.0.0.1:3000", true))
    }

    /** Every event the app can make: each maker with every one of its choices. */
    private fun everyEvent(): List<Event> = buildList {
        for (cold in listOf(true, false)) for (first in listOf(true, false)) add(Events.appOpen(cold, first))
        add(Events.appBackground(0))
        add(Events.appBackground(86_400))
        add(Events.introFinished(true))
        add(Events.introFinished(false))
        add(Events.onboardingFinished(true))
        add(Events.onboardingFinished(false))
        for (where in MicAsked.entries) for (granted in listOf(true, false)) add(Events.micPermission(granted, where))
        for (tab in Tab.entries) add(Events.tabView(tab))
        for (source in HelpSource.entries) add(Events.helpViewed(source))
        add(Events.gameOpen("alien-customs", resumed = true))
        add(Events.gameOpen("nuclear-war", resumed = false))
        for (kind in listOf("chapter", "gameover", "ending")) add(Events.gameEnd("alien-customs", kind, "L1_win"))
        add(Events.chapterNext("alien-customs", "L2_intro"))
        add(Events.lockedEnd("the-werewolf", "the-werewolf-stories"))
        add(Events.gameRestart("frootopia"))
        add(Events.gameLeave("noodle-rush", "Page1", 14, 312, 9, 3, 2, 1))
        add(Events.gameLeave("noodle-rush", null, 0, 0, 0, 0, 0, 0))
        add(Events.gameError("frootopia", "_restart"))
        add(Events.gameError("frootopia", null))
        for (source in ShopSource.entries) add(Events.shopView(source))
        add(Events.purchaseStart("alien_customs_levels"))
        for (result in PurchaseResult.entries) add(Events.purchaseResult("frootopia_stories", result))
        for (result in RestoreResult.entries) add(Events.restore(result, 2))
        add(Events.packDownload("alien-customs-levels", installed = true, seconds = 41, bytes = 26_214_400))
        add(Events.packDownload("the-werewolf-stories", installed = false, seconds = 3, bytes = 0))
    }

    /** An event as the app sends it. */
    private fun sent(e: Event): JsonObject = Json.parseToJsonElement(
        Events.json(e, Stamp("00000000-0000-4000-8000-0000000000aa", "00000000-0000-4000-8000-0000000000bb", 0,
            1_791_538_860_000L, About("1.0", "3", "15", "en-GB", "phone"))),
    ).jsonObject

    /** A value of a whitelist type. */
    private fun sample(type: String): Any = when {
        type == "bool" -> true
        type == "int" -> 1
        type == "id" -> "noodle-rush"
        type.startsWith("enum:") -> type.removePrefix("enum:").substringBefore(',')
        else -> "x"
    }

    /** "voiceSpeed" as "voice_speed". */
    private fun snake(name: String) = name.replace(Regex("([a-z])([A-Z])"), "$1_$2").lowercase()

    /** A call found in the source: the event it names, and its text up to its closing bracket. */
    private class Call(val name: String, val text: String)

    /** Every call [pattern] finds (its second group the name), with the text of its arguments. */
    private fun calls(text: String, pattern: Regex): List<Call> = pattern.findAll(text).map { m ->
        val open = text.indexOf('(', m.range.first)
        var depth = 0
        var end = open
        for (i in open until text.length) {
            if (text[i] == '(') depth++
            if (text[i] == ')') depth--
            if (depth == 0) {
                end = i
                break
            }
        }
        Call(m.groupValues[2], text.substring(open, end + 1))
    }.toList()
}
