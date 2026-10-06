package com.epicaudiogames.engine.nuclear

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** The skill's SkillStates for Nuclear War: the question the game waits at. */
enum class Q {
    CHOOSE_COUNTRY, COUNTRY_SELECT, NUCLEAR_PROMPT, ENVIRONMENT_PROMPT, CITY_PROMPT, UPGRADE_PROMPT, RESEARCH_PROMPT,
    SHIELD_PROMPT, SANCTION, SANCTION_COUNTRY, SANCTION_SPECIFIC, REMOVE_SANCTION_PROMPT, REMOVE_SANCTION,
    REMOVE_INDIVIDUAL_SANCTION, PHONE_COUNTRY, BOMB_PROMPT, BOMB_NUMBER_PROMPT, USE_BOMBS, CHOOSE_BOMB_COUNTRY,
    CHOOSE_BOMB_CITY, CONFIRM_BOMB_PROMPT, BOMB_INDIVIDUAL, GAME_OVER,
}

/** A city: its shield and research (counts, as the skill keeps them), and whether it's been destroyed. */
class City(val name: String) {
    var shield = 0
    var research = 0
    var destroyed = false
}

/** A country in the war (the skill's createCountrySessionObj, and the fields its code adds on the way). */
class Nation(val ref: String) {
    var balance = 10_000_000L
    var motivator = ""
    var strikesToUse = 0
    var contributions = 0
    var bombs = 0
    val bombedBy = mutableListOf<String>()
    val sanctionedBy = mutableListOf<String>()
    val countriesBombed = mutableListOf<String>()
    var tech = false
    var cities = mutableListOf<City>()
    val bombify = mutableListOf<String>()
    var score = 0
    var sanctioned = false
    var wasSanctioned = false
    var stillSanctioned = false
    var destroyed = false
    /** A count in the skill (and "angry" whenever it isn't 0, even below it). */
    var attackUs = 0
    var hasAttackedUs = false
    var hasMet = false
    /** The leaders' recorded lines already played, per kind ("general", "defense", "friendly", "nuclear"). */
    val used = mutableMapOf<String, MutableList<Int>>()
    /** Ours: the skill's "shield-<i>" and "research-<i>" flags (set when bought, never cleared). */
    val done = mutableSetOf<String>()

    fun alive() = cities.filter { !it.destroyed }

    fun toJson(): JsonObject = buildJsonObject {
        put("ref", ref)
        put("balance", balance)
        put("motivator", motivator)
        put("strikesToUse", strikesToUse)
        put("contributions", contributions)
        put("bombs", bombs)
        putJsonArray("bombedBy") { bombedBy.forEach { add(JsonPrimitive(it)) } }
        putJsonArray("sanctionedBy") { sanctionedBy.forEach { add(JsonPrimitive(it)) } }
        putJsonArray("countriesBombed") { countriesBombed.forEach { add(JsonPrimitive(it)) } }
        put("tech", tech)
        putJsonArray("cities") {
            cities.forEach { c ->
                add(buildJsonObject {
                    put("name", c.name)
                    put("shield", c.shield)
                    put("research", c.research)
                    put("destroyed", c.destroyed)
                })
            }
        }
        putJsonArray("bombify") { bombify.forEach { add(JsonPrimitive(it)) } }
        put("score", score)
        put("sanctioned", sanctioned)
        put("wasSanctioned", wasSanctioned)
        put("stillSanctioned", stillSanctioned)
        put("destroyed", destroyed)
        put("attackUs", attackUs)
        put("hasAttackedUs", hasAttackedUs)
        put("hasMet", hasMet)
        putJsonObject("used") { used.forEach { (k, v) -> put(k, JsonArray(v.map { JsonPrimitive(it) })) } }
        putJsonArray("done") { done.forEach { add(JsonPrimitive(it)) } }
    }

    companion object {
        fun fromJson(o: JsonObject): Nation = Nation(o.str("ref")).apply {
            balance = o.getValue("balance").jsonPrimitive.long
            motivator = o.str("motivator")
            strikesToUse = o.int("strikesToUse")
            contributions = o.int("contributions")
            bombs = o.int("bombs")
            bombedBy += o.strings("bombedBy")
            sanctionedBy += o.strings("sanctionedBy")
            countriesBombed += o.strings("countriesBombed")
            tech = o.bool("tech")
            cities = o.getValue("cities").jsonArray.map { e ->
                val c = e.jsonObject
                City(c.str("name")).apply {
                    shield = c.int("shield")
                    research = c.int("research")
                    destroyed = c.bool("destroyed")
                }
            }.toMutableList()
            bombify += o.strings("bombify")
            score = o.int("score")
            sanctioned = o.bool("sanctioned")
            wasSanctioned = o.bool("wasSanctioned")
            stillSanctioned = o.bool("stillSanctioned")
            destroyed = o.bool("destroyed")
            attackUs = o.int("attackUs")
            hasAttackedUs = o.bool("hasAttackedUs")
            hasMet = o.bool("hasMet")
            o["used"]?.jsonObject?.forEach { (k, v) -> used[k] = v.jsonArray.map { it.jsonPrimitive.int }.toMutableList() }
            done += o.strings("done")
        }
    }
}

/** One game of Nuclear War (the skill's ad.Session.nuclear and its SkillState), and what it keeps between games. */
class State {
    var q = Q.CHOOSE_COUNTRY
    var countries = mutableListOf<Nation>()
    var us: Nation? = null
    var environment = 0
    var prevEnvironment = 0
    var round = 1
    val citiesToBomb = mutableListOf<String>()
    var cityIndex = 0
    var countryIndex = 0
    /** Who asked to have whom bombed (from, to). */
    val requestToBomb = mutableListOf<Pair<String, String>>()
    var doneLongCall = false
    var midGame = false
    var countryToBomb: String? = null
    var cityBombIndex = 0

    // The skill's Settings, kept between games: the first game's tutorial, rundown and city list are said once.
    var playedNuclear = false
    var rundown = false
    var completed = false

    fun toJson(): JsonObject = buildJsonObject {
        put("q", q.name)
        putJsonArray("countries") { countries.forEach { add(it.toJson()) } }
        put("us", us?.toJson() ?: JsonNull)
        put("environment", environment)
        put("prevEnvironment", prevEnvironment)
        put("round", round)
        putJsonArray("citiesToBomb") { citiesToBomb.forEach { add(JsonPrimitive(it)) } }
        put("cityIndex", cityIndex)
        put("countryIndex", countryIndex)
        putJsonArray("requestToBomb") { requestToBomb.forEach { (a, b) -> add(JsonArray(listOf(JsonPrimitive(a), JsonPrimitive(b)))) } }
        put("doneLongCall", doneLongCall)
        put("midGame", midGame)
        put("countryToBomb", countryToBomb)
        put("cityBombIndex", cityBombIndex)
        putSettings()
    }

    fun settingsJson(): JsonObject = buildJsonObject { putSettings() }

    private fun kotlinx.serialization.json.JsonObjectBuilder.putSettings() {
        put("playedNuclear", playedNuclear)
        put("rundown", rundown)
        put("completed", completed)
    }

    /** Takes the settings kept between games from a saved state (or its settings alone). */
    fun takeSettings(o: JsonObject) {
        playedNuclear = o.bool("playedNuclear")
        rundown = o.bool("rundown")
        completed = o.bool("completed")
    }

    companion object {
        fun fromJson(o: JsonObject): State = State().apply {
            q = Q.valueOf(o.str("q"))
            countries = o.getValue("countries").jsonArray.map { Nation.fromJson(it.jsonObject) }.toMutableList()
            us = (o["us"] as? JsonObject)?.let { Nation.fromJson(it) }
            environment = o.int("environment")
            prevEnvironment = o.int("prevEnvironment")
            round = o.int("round")
            citiesToBomb += o.strings("citiesToBomb")
            cityIndex = o.int("cityIndex")
            countryIndex = o.int("countryIndex")
            o.getValue("requestToBomb").jsonArray.forEach { p ->
                val a = p.jsonArray
                requestToBomb += a[0].jsonPrimitive.content to a[1].jsonPrimitive.content
            }
            doneLongCall = o.bool("doneLongCall")
            midGame = o.bool("midGame")
            countryToBomb = (o["countryToBomb"] as? JsonPrimitive)?.takeIf { it.isString }?.content
            cityBombIndex = o.int("cityBombIndex")
            takeSettings(o)
        }
    }
}

private fun JsonObject.str(k: String) = getValue(k).jsonPrimitive.content
private fun JsonObject.int(k: String) = (this[k] as? JsonPrimitive)?.int ?: 0
private fun JsonObject.bool(k: String) = (this[k] as? JsonPrimitive)?.boolean ?: false
private fun JsonObject.strings(k: String): List<String> =
    (this[k] as? JsonArray)?.map { (it as JsonElement).jsonPrimitive.content } ?: emptyList()
