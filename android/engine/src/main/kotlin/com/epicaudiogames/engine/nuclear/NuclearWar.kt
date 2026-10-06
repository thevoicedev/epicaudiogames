package com.epicaudiogames.engine.nuclear

import com.epicaudiogames.engine.Answer
import com.epicaudiogames.engine.Ask
import com.epicaudiogames.engine.Button
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Heard
import com.epicaudiogames.engine.Match
import com.epicaudiogames.engine.Matcher
import com.epicaudiogames.engine.Mixed
import com.epicaudiogames.engine.Phrase
import com.epicaudiogames.engine.Play
import com.epicaudiogames.engine.Saved
import com.epicaudiogames.engine.SetValue
import com.epicaudiogames.engine.Step
import com.epicaudiogames.engine.Text
import com.epicaudiogames.engine.Turn
import com.epicaudiogames.engine.WordLists
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.math.floor
import kotlin.math.min
import kotlin.random.Random

/**
 * Nuclear War, as the Mini Games skill plays it on a speaker: a port of alexa/lambda/Games/nuclear-war/index.js with
 * its screen paths taken out. The functions keep the skill's names (in their comments) and its rules, quirks
 * included: computer countries never buy bombs when their motive is defence, a country that bombs back always aims
 * at the first city it can, and so on. Don, the announcer, says what Alexa said ([Lines]); the leaders' calls, the
 * music and the sound effects are the skill's own recordings ([NuclearAudio]).
 *
 * Left out: coins, the daily play limit and the upsell, and "play again, or a different game?" (the app's end
 * panel). Changed: lists of countries and cities are said in the countries' fixed order; a few dead ends of the skill
 * go on instead (noted where they are).
 */
class NuclearWar(private val audio: NuclearAudio, private val random: Random = Random.Default) : Play {
    companion object {
        const val ID = "nuclear-war"

        private val YES = listOf("yes", "yeah", "yep", "yup", "sure", "ok", "okay", "alright", "all right", "of course",
            "definitely", "absolutely", "please", "go on", "go ahead", "do it", "let's do it", "pick up", "answer",
            "answer it", "why not", "i do", "i would", "yes please")
        private val NO = listOf("no", "nope", "nah", "no thanks", "no thank you", "not now", "never", "no way",
            "not really", "neither", "ignore", "ignore it", "hang up", "don't", "i don't", "nothing", "no more")
        private val REPEAT = listOf("repeat", "say that again", "say it again", "what", "pardon")
        private val NUMBER_WORDS = mapOf(
            "zero" to 0, "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7,
            "eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14,
            "fifteen" to 15, "sixteen" to 16, "seventeen" to 17, "eighteen" to 18, "nineteen" to 19,
        )
        private val TENS = mapOf("twenty" to 20, "thirty" to 30, "forty" to 40, "fifty" to 50)
        private val NUMBER = Regex("\\b(\\d+|" + (NUMBER_WORDS.keys + TENS.keys + "couple").joinToString("|") + ")\\b")

        private val COUNTRY_WORDS = mapOf(
            "France" to listOf("france", "french"),
            "USA" to listOf("usa", "u s a", "the usa", "america", "american", "united states", "the united states",
                "united states of america", "the us"),
            "UK" to listOf("uk", "u k", "the uk", "united kingdom", "the united kingdom", "britain", "great britain",
                "england", "british"),
            "China" to listOf("china", "chinese"),
            "Russia" to listOf("russia", "russian"),
        )
        private val CITY_WORDS = mapOf(
            "Marseille" to listOf("marseilles"), "Lyon" to listOf("lyons", "leon"), "New York" to listOf("new york city"),
            "Los Angeles" to listOf("la", "l a"), "Wuhan" to listOf("woohan", "wu han"),
            "St Petersburg" to listOf("saint petersburg", "st petersburg", "petersburg"),
        )
    }

    /** Every text Don has said (tests check that each is one of [Lines.all]). */
    val spoken = mutableSetOf<String>()

    private var st = State()
    private var end: End? = null
    private var reprompt: List<Step> = emptyList()

    /** The word lists the answers are matched with (the Matcher reads them from a map). */
    private val words = GameMap(
        ID, "Nuclear War", "", emptyMap(), emptySet(), false, audio.who,
        WordLists(phrases(YES), phrases(NO), phrases(REPEAT),
            Mixed(listOf("yes", "yeah", "yep", "sure", "ok", "okay"), listOf("no", "nope", "nah"),
                listOf("um", "uh", "er", "erm", "well", "oh"))),
        emptyMap(), emptyMap(),
    )

    private fun phrases(list: List<String>) = list.map { Phrase(Text.normalise(it), false) }

    // ----- Play -----

    override val who: Map<String, String> get() = audio.who

    override val ask: Ask? get() = if (end == null) Ask(reprompt, answers().map { it.first }, null, buttons()) else null

    override fun start(): Turn {
        val kept = st.settingsJson()
        st = State().also { it.takeSettings(kept) }
        end = null
        val o = Out()
        playNuclearWar(o)
        return turn(o)
    }

    override fun open(saved: Saved?): Turn {
        (saved?.vars?.get("settings") as? String)?.let { st.takeSettings(Json.parseToJsonElement(it).jsonObject) }
        return if (saved != null && canResume(saved)) resume(saved) else start()
    }

    override fun canResume(saved: Saved) = !saved.ended && saved.vars["state"] is String && saved.node != Q.GAME_OVER.name

    override fun resume(saved: Saved): Turn {
        st = State.fromJson(Json.parseToJsonElement(saved.vars["state"] as String).jsonObject)
        end = null
        val o = Out()
        continueWar(o)
        return turn(o)
    }

    override fun save() = Saved(st.q.name, mapOf("state" to st.toJson().toString(), "settings" to st.settingsJson().toString()),
        end != null)

    override fun answer(said: String): Turn {
        val pairs = answers()
        val r = Matcher.match(words, Ask(reprompt, pairs.map { it.first }, null, emptyList()), emptyMap(), said)
        val o = Out()
        val buying = st.q == Q.BOMB_PROMPT || st.q == Q.BOMB_NUMBER_PROMPT
        when (val i = r.index?.let { pairs[it].second }) {
            Intent.Yes -> yes(o)
            Intent.No -> no(o)
            Intent.Number -> pickNumber(o, number(said))
            is Intent.Name -> if (buying) pickNumber(o, null) else answerWith(o, i.value)
            // While buying bombs, the skill reads anything else as a number it didn't catch. Otherwise "repeat",
            // or not understood: its fallback asks again.
            null -> if (buying && !r.repeat) pickNumber(o, null) else continueWar(o)
        }
        return turn(o, Heard(said, r.index, r.how))
    }

    override fun silence() = Turn(reprompt, ask, end, false, st.q.name, emptyList())

    override fun restart(at: String?) = start()

    override fun nextChapter(): Turn = throw IllegalStateException("Nuclear War has no chapters")

    override fun hasChapter(next: String) = false

    override fun understands(said: String): Boolean {
        val pairs = answers()
        return Matcher.match(words, Ask(reprompt, pairs.map { it.first }, null, emptyList()), emptyMap(), said)
            .let { it.index != null || it.repeat }
    }

    // ----- Turns -----

    /** A turn as it's made: steps to play and the reprompt (the skill's Response). */
    private inner class Out {
        val steps = mutableListOf<Step>()
        var reprompt: List<Step> = emptyList()

        fun don(text: String) {
            steps += line(text, false)
        }

        /** A piece of a sentence that carries on in the next one. */
        fun part(text: String) {
            steps += line(text, true)
        }

        fun money(amount: Long) = part(Lines.money(amount))

        /** A list said a name at a time ([Lines.items]). */
        fun items(names: List<String>, last: Lines.Last) {
            val pieces = Lines.items(names, last)
            pieces.forEachIndexed { i, p -> if (i == pieces.lastIndex && last == Lines.Last.END) don(p) else part(p) }
        }

        fun clip(path: String?) {
            audio.clip(path)?.let { steps += it }
        }

        /** A sound under what follows (the skill's mixers): it plays once, until [stopBeds] or the turn's end. */
        fun bed(path: String?, volume: Double) {
            audio.clip(path)?.let { steps += Step.Bed(it.path, volume, it.dur) }
        }

        fun stopBeds() {
            steps += Step.Bed(null, 0.0, 0.0)
        }

        fun pause(seconds: Double) {
            steps += Step.Pause(seconds)
        }

        fun mix(name: String) {
            audio.mix(name)?.let { steps += it }
        }

        fun reprompt(text: String) {
            reprompt = listOf(line(text, false))
        }
    }

    private fun line(text: String, more: Boolean): Step.Play {
        spoken += text
        val p = audio.don(text)
        return if (more) p.copy(lines = p.lines.map { it.copy(more = true) }) else p
    }

    private fun turn(o: Out, heard: Heard? = null): Turn {
        if (end == null) reprompt = o.reprompt
        return Turn(o.steps.toList(), ask, end, false, st.q.name, emptyList(), heard)
    }

    private fun finish(kind: String, title: String) {
        st.q = Q.GAME_OVER
        end = End(kind, title, null, null, null)
    }

    // ----- Answers: the skill's intents (yes, no, a number, a name) for the question at hand -----

    private sealed interface Intent {
        data object Yes : Intent
        data object No : Intent
        data object Number : Intent
        data class Name(val value: String) : Intent
    }

    private fun answers(): List<Pair<Answer, Intent>> {
        val out = mutableListOf<Pair<Answer, Intent>>()
        fun add(m: Match, i: Intent) {
            val key = when (i) {
                Intent.Yes -> "yes"
                Intent.No -> "no"
                Intent.Number -> "number"
                is Intent.Name -> "name:${i.value}"
            }
            out += Answer(m, null, mapOf("intent" to SetValue.Assign(key)), null, null) to i
        }
        fun words(list: List<String>) = Match.Words(phrases(list))
        add(Match.Yes(emptyList()), Intent.Yes)
        add(Match.No(emptyList()), Intent.No)
        if (st.q == Q.BOMB_PROMPT || st.q == Q.BOMB_NUMBER_PROMPT) {
            add(Match.Re(NUMBER.pattern), Intent.Number)
            add(words(listOf("none", "no bombs")), Intent.No)
        }
        if (st.q == Q.PHONE_COUNTRY) {
            add(words(listOf("next", "skip", "continue", "play")), Intent.No)
            add(words(listOf("next round")), Intent.Name("next round"))
        }
        if (st.q == Q.CHOOSE_BOMB_CITY) {
            add(words(listOf("all of them", "all", "all three", "every city", "all the cities", "all of it")),
                Intent.Name("all of them"))
        }
        for ((ref, list) in COUNTRY_WORDS) add(words(list), Intent.Name(ref))
        for (city in World.CITIES) add(words(listOf(city) + CITY_WORDS[city].orEmpty()), Intent.Name(city))
        add(words(listOf("shield", "shields", "a shield", "build a shield")), Intent.Name("shield"))
        add(words(listOf("research", "do research")), Intent.Name("research"))
        return out
    }

    private fun buttons(): List<Button> {
        val yesNo = listOf(Button("Yes", "yes"), Button("No", "no"))
        fun countries(refs: List<String>) = World.ordered(refs).map { Button(World.voice(it), it) }
        return when (st.q) {
            Q.CHOOSE_COUNTRY -> countries(World.REFS)
            Q.PHONE_COUNTRY -> listOf(Button("Answer", "yes"), Button("Ignore", "no"))
            Q.UPGRADE_PROMPT -> listOf(Button("Shield", "shield"), Button("Research", "research"), Button("No", "no"))
            Q.CHOOSE_BOMB_COUNTRY -> countries(attackable().map { it.ref })
            Q.CHOOSE_BOMB_CITY -> {
                val c = st.countries.find { it.ref == st.countryToBomb }
                val cities = c?.let { targetCities(it) }.orEmpty()
                cities.map { Button(it, it) } + if (cities.size == 3 && us().bombs >= 3) listOf(Button("All of them", "all of them")) else emptyList()
            }
            Q.SANCTION_COUNTRY -> countries(st.countries.filter { !it.sanctioned }.map { it.ref })
            Q.REMOVE_SANCTION -> countries(st.countries.filter { it.sanctioned }.map { it.ref })
            Q.BOMB_NUMBER_PROMPT -> {
                val max = maxBombs()
                (1..min(max, 3)).map { Button("$it", "$it") } + Button("None", "none")
            }
            Q.GAME_OVER -> emptyList()
            else -> yesNo
        }
    }

    /** The number said: "3", "three", "twenty two" (not "to", "for" or "won", which say other things). */
    private fun number(said: String): Int? {
        val t = Text.normalise(said.replace('-', ' ')).split(' ')
        for ((i, w) in t.withIndex()) {
            w.toIntOrNull()?.let { return it }
            TENS[w]?.let { tens -> return tens + (t.getOrNull(i + 1)?.let { NUMBER_WORDS[it] }?.takeIf { it < 10 } ?: 0) }
            NUMBER_WORDS[w]?.let { return it }
            if (w == "couple") return 2
        }
        return null
    }

    // ----- The skill's audio getters (Audio.js), over the table in clips.json -----

    private fun sfx(name: String) = audio.path("sfx", name)
    private fun theme(ref: String) = audio.path(ref, "Theme")

    /** One of a leader's recorded lines of a kind, not yet played this game if there is one (getGeneralChat etc.). */
    private fun unused(n: Nation, kind: String, field: String): String? {
        val options = audio.paths(n.ref, field)
        if (options.isEmpty()) return null
        val used = n.used.getOrPut(kind) { mutableListOf() }
        val i = options.indices.filter { it !in used }.ifEmpty { options.indices.toList() }.random(random)
        used += i
        return options[i]
    }

    // ----- Starting: doPlayNuclearWar, initNuclearStats, doChooseCountry -----

    private fun playNuclearWar(o: Out) {
        st.q = Q.CHOOSE_COUNTRY
        initNuclearStats()
        if (st.playedNuclear) {
            o.don(Lines.WELCOME_BACK)
        } else {
            st.playedNuclear = true
            o.don(Lines.WELCOME)
            o.mix("tutorial")
            o.don(Lines.PLAY_AS)
        }
        o.reprompt(Lines.WHICH_COUNTRY)
    }

    private fun initNuclearStats() {
        st.countries = listOf("France", "UK", "USA", "China", "Russia").shuffled(random).map { ref ->
            Nation(ref).apply { cities = World.land(ref).cities.shuffled(random).map { City(it) }.toMutableList() }
        }.toMutableList()
        st.us = null
        st.environment = 0
        st.prevEnvironment = 0
        st.round = 1
        st.citiesToBomb.clear()
        st.cityIndex = 0
        st.countryIndex = 0
        st.requestToBomb.clear()
        st.doneLongCall = false
        st.midGame = false
        st.countryToBomb = null
        st.cityBombIndex = 0
    }

    private fun us() = st.us!!
    private fun current() = st.countries[st.countryIndex]
    private fun currentCity() = us().cities[st.cityIndex]
    private fun isFinalRound() = st.round >= 5
    private fun maxBombs() = (us().balance / World.BOMB).toInt().coerceAtLeast(0)
    private fun bombsText(n: Int) = n.coerceIn(1, World.BOMBS_MAX)

    /** doChooseCountry */
    private fun chooseCountry(o: Out, country: String) {
        initNuclearStats()
        st.q = Q.COUNTRY_SELECT
        val us = st.countries.first { it.ref == country }
        st.us = us
        us.score = 0
        st.countries = st.countries.filter { it.ref != country }.toMutableList()
        val motivators = listOf("DEFENSE", "ENVIRONMENT", "FRIENDLY", "NUCLEAR").shuffled(random)
        st.countries.forEachIndexed { i, n -> n.motivator = motivators[i] }
        st.countryIndex = 0
        val first = current()
        o.bed(theme(country), 0.20)
        o.don(Lines.leaderOf(country))
        if (!st.rundown) {
            o.don(Lines.MEET_FIRST)
            o.don(Lines.meet(first.ref))
        } else {
            o.don(Lines.meetLeader(first.ref))
        }
        o.stopBeds()
        o.reprompt(Lines.meet(first.ref))
    }

    /** doMeetCountry: the representative's hello and what drives them, then the next country (or the spending). */
    private fun meetCountry(o: Out) {
        val c = current()
        o.bed(theme(c.ref), 0.20)
        o.clip(audio.path(c.ref, "Representative"))
        o.clip(audio.options(c.ref, "Motivators", c.motivator).randomOrNull(random))
        o.stopBeds()
        c.hasMet = true
        if (st.countryIndex > 2) {
            techPrompt(o)
        } else {
            st.countryIndex++
            val next = current()
            o.don(if (st.countryIndex == 3) Lines.meetFinally(next.ref) else Lines.meet(next.ref))
            o.reprompt(Lines.meet(next.ref))
        }
    }

    // ----- Spending: tech, the environment, the cities -----

    /** doNuclearTechPrompt */
    private fun techPrompt(o: Out, start: Boolean = true) {
        st.q = Q.NUCLEAR_PROMPT
        o.don(if (start) Lines.TECH_START else Lines.TECH)
        o.reprompt(Lines.TECH)
    }

    private fun buyTech(o: Out) {
        val us = us()
        us.tech = true
        st.q = Q.ENVIRONMENT_PROMPT
        us.balance -= World.TECH
        st.environment -= 10
        o.clip(sfx("kaching"))
        moneyLeft(o)
        if (st.round < 5) {
            o.bed(sfx("nuclearReactor"), 0.30)
            o.pause(0.5)
            o.don(Lines.TECH_DONE)
            o.stopBeds()
        }
        environmentPrompt(o)
    }

    /** environmentalImpactPrompt */
    private fun environmentPrompt(o: Out) {
        st.q = Q.ENVIRONMENT_PROMPT
        o.don(if (st.round > 1) Lines.ENV else Lines.ENV_START)
        o.reprompt(Lines.ENV)
    }

    private fun buyEnvironment(o: Out) {
        val us = us()
        us.balance -= World.ENVIRONMENT
        us.contributions++
        st.environment += 15
        val percent = st.environment + 100
        o.clip(sfx("kaching"))
        o.clip(sfx("upgradeEnvironment"))
        if (percent == 100) {
            o.don(Lines.ENV_BACK)
        } else {
            o.don(Lines.envAt((percent / 5 * 5).coerceIn(0, World.PERCENT_MAX)))
            if (st.round == 1 && !st.rundown) o.don(Lines.ENV_EXTRA)
        }
        moneyLeft(o)
        afterEnvironment(o)
    }

    private fun afterEnvironment(o: Out) {
        if (us().balance > World.RESEARCH) {
            st.cityIndex = 0
            cityUpgradePrompt(o)
        } else {
            sanctionPromptWithCheck(o)
        }
    }

    /** doNuclearMoneyLeftSpeech */
    private fun moneyLeft(o: Out) {
        val b = us().balance
        if (b <= 0) {
            o.don(Lines.SPENT_ALL)
        } else {
            o.part(Lines.YOU_HAVE)
            o.money(b)
            o.don(Lines.LEFT)
        }
    }

    private fun canUpgrade(city: City?): Boolean {
        if (city == null) return false
        val b = us().balance
        return !city.destroyed && ((b >= World.SHIELD && city.shield == 0) || (b >= World.RESEARCH && city.research == 0))
    }

    /** doCityUpgradePrompt: the first city to upgrade this round. */
    private fun cityUpgradePrompt(o: Out) {
        st.q = Q.CITY_PROMPT
        val names = us().cities.map { it.name }
        val city = us().cities.getOrNull(st.cityIndex)
        if (!canUpgrade(city)) {
            if (city == null) return sanctionPromptWithCheck(o)
            st.cityIndex++
            return cityUpgradePrompt(o)
        }
        city!!
        if (city.shield == 0 && city.research > 0) return shieldPrompt(o)
        if (city.research == 0 && city.shield > 0) return researchPrompt(o)
        if (st.midGame) {
            o.don(if (st.rundown) Lines.wantUpgrade(city.name) else Lines.anyUpgradesOn(city.name))
        } else {
            o.don(if (st.completed) Lines.upgradesTo(names[0]) else Lines.threeCities(names[0], names[1], names[2]))
        }
        o.reprompt(Lines.anyUpgradesTo(city.name))
    }

    /** doNextCityPrompt */
    private fun nextCityPrompt(o: Out, howAbout: Boolean = false) {
        st.q = Q.CITY_PROMPT
        val city = us().cities.getOrNull(st.cityIndex)
        if (!canUpgrade(city)) {
            if (st.cityIndex >= us().cities.size) return sanctionPromptWithCheck(o)
            st.cityIndex++
            return nextCityPrompt(o)
        }
        city!!
        if (city.shield == 0 && city.research > 0) return shieldPrompt(o)
        if (city.research == 0 && city.shield > 0) return researchPrompt(o)
        if (us().balance < World.SHIELD) return researchPrompt(o)
        o.don(if (howAbout) Lines.howAbout(city.name) else Lines.upgradesOn(city.name))
        o.reprompt(Lines.anyUpgradesTo(city.name))
    }

    /** doBuildOrResearchPrompt */
    private fun buildOrResearchPrompt(o: Out) {
        st.q = Q.UPGRADE_PROMPT
        o.don(Lines.COSTS)
        o.don(Lines.SHIELD_OR_RESEARCH)
        o.reprompt(Lines.SHIELD_OR_RESEARCH_AGAIN)
    }

    /** doResearchPrompt */
    private fun researchPrompt(o: Out) {
        st.q = Q.RESEARCH_PROMPT
        val name = currentCity().name
        val text = if (st.rundown) Lines.researchFor(name) else Lines.researchProductivity(name)
        o.don(text)
        o.reprompt(text)
    }

    /** doShieldPrompt */
    private fun shieldPrompt(o: Out) {
        st.q = Q.SHIELD_PROMPT
        val text = Lines.shieldFor(currentCity().name)
        o.don(text)
        o.reprompt(text)
    }

    /** doChooseResearch */
    private fun chooseResearch(o: Out) {
        val us = us()
        us.balance -= World.RESEARCH
        val city = currentCity()
        city.research = 1
        us.done += "research-${st.cityIndex}"
        o.clip(sfx("kaching"))
        o.bed(sfx("research"), 1.0)
        o.pause(0.5)
        o.don(Lines.productivity(city.name))
        o.part(Lines.YOU_HAVE)
        o.money(us.balance)
        o.don(Lines.LEFT)
        val enoughForResearch = us.balance >= World.RESEARCH
        val enoughForShield = us.balance >= World.SHIELD
        val doneAllCities = st.cityIndex >= us.cities.size - 1
        val doneShield = "shield-${st.cityIndex}" in us.done
        when {
            doneAllCities -> when {
                doneShield -> {
                    o.don(Lines.DONE_ALL)
                    sanctionPromptWithCheck(o)
                }
                enoughForShield -> shieldPrompt(o)
                else -> sanctionPromptWithCheck(o)
            }
            !enoughForResearch -> sanctionPromptWithCheck(o)
            doneShield -> {
                st.cityIndex++
                nextCityPrompt(o)
            }
            enoughForShield -> shieldPrompt(o)
            else -> {
                st.cityIndex++
                moneyLeft(o)
                nextCityPrompt(o)
            }
        }
    }

    /** doChooseShield */
    private fun chooseShield(o: Out) {
        val us = us()
        val city = currentCity()
        us.balance -= World.SHIELD
        city.shield = 1
        o.clip(sfx("kaching"))
        o.bed(sfx("shield"), 1.0)
        o.don(Lines.protectedNow(city.name))
        moneyLeft(o)
        us.done += "shield-${st.cityIndex}"
        if (isFinalRound()) {
            st.cityIndex++
            return finalShieldPrompt(o)
        }
        val enoughForResearch = us.balance >= World.RESEARCH
        val doneResearch = "research-${st.cityIndex}" in us.done
        val doneAllCities = st.cityIndex >= us.cities.size - 1
        when {
            doneAllCities -> when {
                doneResearch -> {
                    o.don(Lines.DONE_ALL)
                    sanctionPromptWithCheck(o)
                }
                enoughForResearch -> researchPrompt(o)
                else -> sanctionPromptWithCheck(o)
            }
            !enoughForResearch -> sanctionPromptWithCheck(o)
            doneResearch -> {
                st.cityIndex++
                nextCityPrompt(o)
            }
            else -> researchPrompt(o)
        }
    }

    // ----- Sanctions -----

    /** doSanctionPromptWithCheck */
    private fun sanctionPromptWithCheck(o: Out) {
        if (st.midGame) sanctionPrompt(o, mid = true, remove = st.countries.any { it.sanctioned }) else sanctionPrompt(o)
    }

    /** doSanctionPrompt */
    private fun sanctionPrompt(o: Out, mid: Boolean = false, remove: Boolean = false) {
        st.q = Q.SANCTION
        val text = when {
            mid && remove -> {
                st.q = Q.REMOVE_SANCTION_PROMPT
                Lines.REMOVE_ANY
            }
            mid -> if (st.rundown) Lines.ADD_ANY else Lines.ADD_ANY_LONG
            else -> Lines.SANCTION_ANY
        }
        o.don(text)
        o.reprompt(text)
    }

    /** doCountrySanctionChoice */
    private fun countrySanctionChoice(o: Out) {
        st.q = Q.SANCTION_COUNTRY
        val remaining = World.ordered(st.countries.filter { !it.sanctioned }.map { it.ref })
        val text = when {
            remaining.size >= 2 -> Lines.sanctionList(remaining)
            remaining.size == 1 -> {
                st.q = Q.SANCTION_SPECIFIC
                Lines.sanctionOne(remaining[0])
            }
            else -> return bombsOrNextRound(o)      // the skill asks to sanction "undefined"
        }
        o.don(text)
        o.reprompt(text)
    }

    /** sanctionCountry */
    private fun sanctionCountry(o: Out, ref: String) {
        st.countries.find { it.ref == ref }?.let {
            it.sanctioned = true
            it.wasSanctioned = false
        }
        // The skill's "and will get 20% less income" never plays: a country has always just been sanctioned.
        o.bed(sfx("stampFx"), 1.0)
        o.don(Lines.sanctioned(ref))
        if (st.countries.all { it.sanctioned }) {
            o.don(Lines.SANCTIONED_ALL)
            bombsOrNextRound(o)
        } else {
            st.q = Q.SANCTION
            o.don(Lines.SANCTION_ANOTHER)
            o.reprompt(Lines.SANCTION_ANOTHER)
        }
    }

    /** doRemoveSanctionPrompt */
    private fun removeSanctionPrompt(o: Out) {
        st.q = Q.REMOVE_SANCTION
        val sanctioned = World.ordered(st.countries.filter { it.sanctioned }.map { it.ref })
        if (sanctioned.size < 2) return removeIndividualSanctionPrompt(o)
        o.don(Lines.removeList(sanctioned))
        o.reprompt(Lines.removeListAgain(sanctioned))
    }

    /** doRemoveIndividualSanctionPrompt */
    private fun removeIndividualSanctionPrompt(o: Out) {
        st.q = Q.REMOVE_INDIVIDUAL_SANCTION
        val c = st.countries.firstOrNull { it.sanctioned } ?: return sanctionPromptWithCheck(o)
        o.don(Lines.removeOne(c.ref))
        o.reprompt(Lines.removeOne(c.ref))
    }

    /** unSanctionCountry */
    private fun unsanctionCountry(o: Out, ref: String) {
        st.countries.find { it.ref == ref }?.let {
            it.sanctioned = false
            it.wasSanctioned = true
            it.stillSanctioned = false
        }
        o.bed(sfx("eraser"), 1.0)
        o.don(Lines.youRemoved(ref))
        val left = st.countries.count { it.sanctioned }
        when {
            left == 1 -> removeIndividualSanctionPrompt(o)
            left > 1 -> {
                st.q = Q.REMOVE_SANCTION_PROMPT
                o.don(Lines.REMOVE_MORE)
                o.reprompt(Lines.REMOVE_MORE)
            }
            else -> sanctionPromptWithCheck(o)
        }
    }

    private fun afterRemovingSanctions(o: Out) {
        if (st.countries.any { !it.sanctioned }) sanctionPrompt(o, mid = true) else bombsOrNextRound(o)
    }

    // ----- Bombs -----

    /** doBombPrompt */
    private fun bombPrompt(o: Out) {
        st.q = Q.BOMB_PROMPT
        val n = us().bombs
        if (n > 0) {
            o.don(Lines.buyMore(bombsText(n)))
            o.reprompt(Lines.buyMoreAgain(bombsText(n)))
        } else {
            o.don(Lines.BUY_ANY)
            o.reprompt(Lines.BUY_ANY)
        }
    }

    /** askBombAmount */
    private fun askBombAmount(o: Out) {
        st.q = Q.BOMB_NUMBER_PROMPT
        o.don(Lines.HOW_MANY)
        o.reprompt(Lines.HOW_MANY)
    }

    /** doNuclearPickNumber */
    private fun pickNumber(o: Out, n: Int?) {
        if (st.q != Q.BOMB_PROMPT && st.q != Q.BOMB_NUMBER_PROMPT) return continueWar(o)
        val max = maxBombs()
        when {
            n == null -> {
                o.don(Lines.DIDNT_CATCH)
                askBombAmount(o)
            }
            n > max -> {
                o.don(Lines.affordUpTo(max.coerceAtMost(World.BOMBS_MAX)))
                askBombAmount(o)
            }
            n == 0 -> no(o)
            else -> {
                val us = us()
                o.clip(sfx("kaching"))
                us.balance -= n * World.BOMB
                us.bombs += n
                o.part(Lines.nowHave(bombsText(us.bombs)))
                if (us.balance <= 0) o.part(Lines.NOTHING) else o.money(us.balance)
                o.don(Lines.LEFT_IN_BANK)
                st.environment -= n * 5
                completeBombPurchase(o)
            }
        }
    }

    /** doCompleteBombPurchase */
    private fun completeBombPurchase(o: Out) {
        if (isFinalRound()) return finalShieldPrompt(o)
        if (us().balance >= World.ENVIRONMENT) environmentPrompt(o) else sanctionPromptWithCheck(o)
    }

    /** doBombsOrNextRound */
    private fun bombsOrNextRound(o: Out) {
        val n = us().bombs
        if (n > 0 && st.round > 1) {
            o.don(Lines.haveBombs(bombsText(n)))
            offerBombUse(o)
        } else {
            nextRound(o)
        }
    }

    /** doOfferBombUse (on a speaker, always "from the prompt") */
    private fun offerBombUse(o: Out) {
        st.q = Q.USE_BOMBS
        o.don(Lines.USE_ONE)
        o.reprompt(Lines.USE_A_BOMB)
    }

    /** getAttackableCountries */
    private fun attackable() = st.countries.filter { c ->
        !c.destroyed && c.cities.any { !it.destroyed && it.name !in st.citiesToBomb }
    }

    /** A country's cities that can still be aimed at, in its fixed order. */
    private fun targetCities(c: Nation) =
        World.orderedCities(c.cities.filter { !it.destroyed && it.name !in st.citiesToBomb }.map { it.name })

    /** askWhichCountryToBomb */
    private fun askWhichCountryToBomb(o: Out) {
        st.q = Q.CHOOSE_BOMB_COUNTRY
        val refs = World.ordered(attackable().map { it.ref })
        if (refs.isEmpty()) return nextRound(o)    // the skill says "Attack undefined": nothing left to aim at
        if (refs.size == 1) {
            st.q = Q.BOMB_INDIVIDUAL
            o.don(Lines.wantAttack(refs[0]))
            o.reprompt(Lines.wouldAttack(refs[0]))
            return
        }
        o.don(Lines.attackCountries(refs))
        o.reprompt(Lines.whichCountryAttack(refs))
    }

    /** chooseBombCity */
    private fun chooseBombCity(o: Out) {
        st.q = Q.CHOOSE_BOMB_CITY
        val c = st.countries.find { it.ref == st.countryToBomb } ?: return askWhichCountryToBomb(o)
        val cities = targetCities(c)
        if (cities.isEmpty()) return askWhichCountryToBomb(o)
        if (cities.size == 1) {
            st.cityBombIndex = 0
            o.don(Lines.wouldAttackCity(cities[0]))
            o.reprompt(Lines.wantAttackCity(cities[0]))
            return
        }
        o.don(if (cities.size == 3 && us().bombs >= 3) Lines.attackAll(cities) else Lines.attackCities(cities))
        o.reprompt(Lines.attackCities(cities))
    }

    /** chooseBombCityReprompt */
    private fun chooseBombCityReprompt(o: Out) {
        st.q = Q.CHOOSE_BOMB_CITY
        val c = st.countries.find { it.ref == st.countryToBomb } ?: return askWhichCountryToBomb(o)
        val cities = targetCities(c)
        if (cities.isEmpty()) return askWhichCountryToBomb(o)
        if (cities.size == 1) {
            st.cityBombIndex = 0
            o.don(Lines.oneLeft(cities[0]))
            o.reprompt(Lines.wantAttackCity(cities[0]))
            return
        }
        o.don(Lines.attackCities(cities))
        o.reprompt(Lines.whichCity(cities))
    }

    /** "Yes" to a city on offer: the first one said (doNuclearYes in CHOOSE_BOMB_CITY). */
    private fun launchOffered(o: Out) {
        val c = st.countries.find { it.ref == st.countryToBomb }
        val city = c?.let { targetCities(it) }?.getOrNull(st.cityBombIndex)
            ?: return if (c != null) chooseBombCityReprompt(o) else continueWar(o)
        val us = us()
        us.bombs--
        o.clip(sfx("pressButton"))
        o.don(Lines.launched(city))
        st.citiesToBomb += city
        us.countriesBombed += c.ref
        st.cityBombIndex = 0
        if (us.bombs > 0) {
            st.q = Q.USE_BOMBS
            o.don(Lines.bombsLeft(bombsText(us.bombs)))
            o.don(Lines.USE_ANOTHER)
            o.reprompt(Lines.USE_ANOTHER_AGAIN)
        } else {
            directed(o)
            nextRound(o)
        }
    }

    /** doSelectBombCity */
    private fun selectBombCity(o: Out, city: String) {
        val us = us()
        us.bombs--
        o.bed(sfx("pressButton"), 1.0)
        o.don(Lines.picked(city))
        st.citiesToBomb += city
        us.countriesBombed += World.landOf(city).ref
        st.cityBombIndex = 0
        moreBombsOrNextRound(o)
    }

    /** doSelectBombAllCities */
    private fun selectAllCities(o: Out) {
        val c = st.countries.first { it.ref == st.countryToBomb }
        val cities = targetCities(c)
        val us = us()
        us.bombs -= cities.size
        for (city in cities) {
            o.clip(sfx("pressButton"))
            o.don(Lines.picked(city))
            st.citiesToBomb += city
        }
        us.countriesBombed += c.ref
        st.cityBombIndex = 0
        moreBombsOrNextRound(o)
    }

    private fun moreBombsOrNextRound(o: Out) {
        val n = us().bombs
        if (n > 0) {
            st.q = Q.USE_BOMBS
            o.don(Lines.bombsLeft(bombsText(n)))
            if (n == 1) {
                o.don(Lines.USE_IT)
                o.reprompt(Lines.USE_IT)
            } else {
                o.don(Lines.USE_ANOTHER)
                o.reprompt(Lines.USE_ANOTHER_AGAIN)
            }
        } else {
            directed(o)
            nextRound(o)
        }
    }

    private fun directed(o: Out) {
        val n = st.citiesToBomb.size
        o.don(when (n) {
            1 -> Lines.DIRECTED_ONE
            2 -> Lines.DIRECTED_TWO
            else -> Lines.directedAll(n.coerceIn(3, World.BOMBS_MAX))
        })
    }

    /** A country or a city named while aiming (doAnswerNuclearWar in the bombing states). */
    private fun aimAt(o: Out, value: String) {
        if (value == "all of them") {
            if (st.q == Q.CHOOSE_BOMB_CITY && st.countryToBomb != null) {
                val c = st.countries.first { it.ref == st.countryToBomb }
                if (us().bombs >= targetCities(c).size) return selectAllCities(o)
                o.don(Lines.notEnoughForAll(c.ref))
            }
            return continueWar(o)
        }
        val ours = us().ref
        if (value in World.REFS && value != ours) {
            val c = st.countries.find { it.ref == value }
            when {
                c == null -> o.don(Lines.cantBomb(value))
                targetCities(c).isEmpty() -> o.don(Lines.allSet(value))
                else -> {
                    st.countryToBomb = value
                    st.cityBombIndex = 0
                    return chooseBombCity(o)
                }
            }
            return continueWar(o)
        }
        if (value in World.CITIES) {
            val inWar = st.countries.any { n -> n.cities.any { it.name == value && !it.destroyed } }
            when {
                value in World.land(ours).cities -> o.don(Lines.bombSelf(value).random(random))
                value in st.citiesToBomb -> o.don(Lines.ONE_PER_CITY)
                // A city of a country knocked out earlier counts as destroyed (the skill would aim at it).
                !inWar -> o.don(Lines.alreadyDestroyed(value))
                else -> return selectBombCity(o, value)
            }
            return continueWar(o)
        }
        if (value == ours) o.don(Lines.OWN_COUNTRY)
        continueWar(o)
    }

    // ----- Yes, no and names: doNuclearYes, doNuclearNo, doAnswerNuclearWar -----

    private fun yes(o: Out) {
        when (st.q) {
            Q.BOMB_INDIVIDUAL -> {
                st.q = Q.CHOOSE_BOMB_COUNTRY
                val first = World.ordered(attackable().map { it.ref }).firstOrNull() ?: return continueWar(o)
                aimAt(o, first)
            }
            Q.CHOOSE_BOMB_CITY -> launchOffered(o)
            Q.CONFIRM_BOMB_PROMPT -> {
                val c = st.countryToBomb ?: return continueWar(o)
                o.don(Lines.definitely(c))
                st.cityBombIndex = 0
                chooseBombCity(o)
            }
            Q.COUNTRY_SELECT -> meetCountry(o)
            Q.USE_BOMBS -> askWhichCountryToBomb(o)
            Q.NUCLEAR_PROMPT -> buyTech(o)
            Q.ENVIRONMENT_PROMPT -> buyEnvironment(o)
            Q.CITY_PROMPT -> {
                val city = currentCity()
                when {
                    us().balance >= World.SHIELD && city.shield == 0 && city.research == 0 -> buildOrResearchPrompt(o)
                    city.research > 0 -> shieldPrompt(o)
                    else -> researchPrompt(o)
                }
            }
            Q.SANCTION -> countrySanctionChoice(o)
            Q.UPGRADE_PROMPT -> {
                o.don(Lines.SHIELD_OR_RESEARCH_AGAIN)
                o.reprompt(Lines.SHIELD_OR_RESEARCH_AGAIN)
            }
            Q.RESEARCH_PROMPT -> chooseResearch(o)
            Q.SHIELD_PROMPT -> chooseShield(o)
            Q.SANCTION_SPECIFIC -> {
                val c = st.countries.firstOrNull { !it.sanctioned } ?: return continueWar(o)
                sanctionCountry(o, c.ref)
            }
            Q.PHONE_COUNTRY -> phoneCountry(o, true)
            Q.BOMB_PROMPT -> {
                o.part(Lines.YOU_HAVE)
                o.money(us().balance)
                o.don(Lines.TO_SPEND)
                o.don(Lines.BOMB_COST)
                askBombAmount(o)
            }
            Q.REMOVE_SANCTION_PROMPT ->
                if (st.countries.count { it.sanctioned } == 1) removeIndividualSanctionPrompt(o) else removeSanctionPrompt(o)
            Q.REMOVE_INDIVIDUAL_SANCTION -> {
                st.q = Q.REMOVE_SANCTION
                val c = st.countries.firstOrNull { it.sanctioned } ?: return continueWar(o)
                answerWith(o, c.ref)
            }
            else -> continueWar(o)      // SANCTION_COUNTRY too: the skill's "yes" there has nothing to pick
        }
    }

    private fun no(o: Out) {
        when (st.q) {
            Q.BOMB_INDIVIDUAL, Q.CHOOSE_BOMB_COUNTRY -> nextRound(o)
            Q.USE_BOMBS -> {
                if (st.citiesToBomb.isEmpty()) {
                    val n = bombsText(us().bombs)
                    o.don(if (isFinalRound()) Lines.dontUse(n) else Lines.keepForLater(n))
                }
                nextRound(o)
            }
            Q.CONFIRM_BOMB_PROMPT -> {
                o.don(Lines.haveBombs(bombsText(us().bombs)))
                offerBombUse(o)
            }
            Q.CHOOSE_BOMB_CITY -> {
                val c = st.countryToBomb ?: return chooseBombCityReprompt(o)
                st.q = Q.CONFIRM_BOMB_PROMPT
                o.don(Lines.sureBomb(c))
                o.reprompt(Lines.sureBomb(c))
            }
            Q.COUNTRY_SELECT -> techPrompt(o)
            Q.NUCLEAR_PROMPT -> environmentPrompt(o)
            Q.ENVIRONMENT_PROMPT -> afterEnvironment(o)
            Q.RESEARCH_PROMPT -> if (st.cityIndex >= us().cities.size - 1) {
                o.don(Lines.ALL_CITIES)
                sanctionPromptWithCheck(o)
            } else {
                st.cityIndex++
                nextCityPrompt(o)
            }
            // UPGRADE_PROMPT: the skill's SkillFlow makes a no there a no to the city (doNo).
            Q.CITY_PROMPT, Q.UPGRADE_PROMPT -> if (st.cityIndex >= us().cities.size - 1) {
                o.don(Lines.EVERY_CITY)
                sanctionPromptWithCheck(o)
            } else {
                st.cityIndex++
                nextCityPrompt(o, howAbout = true)
            }
            Q.SANCTION, Q.SANCTION_COUNTRY, Q.SANCTION_SPECIFIC -> bombsOrNextRound(o)
            Q.PHONE_COUNTRY -> {
                if (st.countryIndex >= st.countries.size) return callsComplete(o)
                phoneCountry(o, false)
                st.countryIndex++
                nextCall(o)
            }
            Q.BOMB_PROMPT, Q.BOMB_NUMBER_PROMPT -> completeBombPurchase(o)
            Q.REMOVE_SANCTION_PROMPT, Q.REMOVE_SANCTION, Q.REMOVE_INDIVIDUAL_SANCTION -> afterRemovingSanctions(o)
            Q.SHIELD_PROMPT -> when {
                isFinalRound() -> {
                    st.cityIndex++
                    finalShieldPrompt(o)
                }
                st.cityIndex >= us().cities.size - 1 -> {
                    o.don(Lines.EVERY_CITY)
                    sanctionPromptWithCheck(o)
                }
                else -> {
                    st.cityIndex++
                    nextCityPrompt(o)
                }
            }
            else -> continueWar(o)
        }
    }

    /** A country, a city, "shield" or "research" said (doAnswerNuclearWar). */
    private fun answerWith(o: Out, value: String) {
        when (st.q) {
            Q.PHONE_COUNTRY -> if (value == "next round") callsComplete(o) else continueWar(o)
            Q.CHOOSE_COUNTRY -> if (value in World.REFS) chooseCountry(o, value) else continueWar(o)
            Q.CHOOSE_BOMB_COUNTRY, Q.USE_BOMBS, Q.CHOOSE_BOMB_CITY, Q.BOMB_INDIVIDUAL -> aimAt(o, value)
            Q.UPGRADE_PROMPT, Q.SHIELD_PROMPT, Q.RESEARCH_PROMPT, Q.CITY_PROMPT -> upgradeWith(o, value)
            Q.SANCTION_COUNTRY, Q.SANCTION, Q.SANCTION_SPECIFIC -> {
                val c = st.countries.find { it.ref == value }
                when {
                    c != null && c.sanctioned -> {
                        o.don(Lines.alreadySanctioned(value))
                        countrySanctionChoice(o)
                    }
                    c != null -> sanctionCountry(o, value)
                    else -> {
                        if (value == us().ref) o.don(Lines.SANCTION_OWN)
                        else if (value in World.REFS) o.don(Lines.cantSanction(value))
                        countrySanctionChoice(o)
                    }
                }
            }
            Q.REMOVE_SANCTION, Q.REMOVE_SANCTION_PROMPT, Q.REMOVE_INDIVIDUAL_SANCTION -> {
                val c = st.countries.find { it.ref == value }
                when {
                    c != null && c.sanctioned -> unsanctionCountry(o, value)
                    c != null -> {
                        o.don(Lines.noSanctionsOn(value))
                        if (st.q == Q.REMOVE_INDIVIDUAL_SANCTION) removeIndividualSanctionPrompt(o) else removeSanctionPrompt(o)
                    }
                    else -> {
                        if (value == us().ref) o.don(Lines.UNSANCTION_OWN)
                        else if (value in World.REFS) o.don(Lines.notToUnsanction(value))
                        sanctionPromptWithCheck(o)
                    }
                }
            }
            else -> continueWar(o)
        }
    }

    /** "Shield" or "research" said at a city's upgrades. */
    private fun upgradeWith(o: Out, value: String) {
        val city = us().cities.getOrNull(st.cityIndex) ?: return continueWar(o)
        if (isFinalRound() && st.q == Q.SHIELD_PROMPT && value != "shield") return shieldPrompt(o)
        when (value) {
            "shield" -> when {
                city.shield > 0 -> {
                    o.don(Lines.alreadyShield(city.name))
                    continueWar(o)
                }
                us().balance < World.SHIELD -> {
                    o.don(Lines.noMoneyShield(city.name))
                    researchPrompt(o)
                }
                else -> chooseShield(o)
            }
            "research" -> if (city.research > 0) {
                o.don(Lines.alreadyResearch(city.name))
                continueWar(o)
            } else {
                chooseResearch(o)
            }
            else -> continueWar(o)      // the skill: "You can't <what was said>, in this war."
        }
    }

    /** doContinueNuclearWar: the question again (also "repeat", and anything not understood). */
    private fun continueWar(o: Out) {
        when (st.q) {
            Q.CHOOSE_COUNTRY -> {
                o.don(Lines.CHOOSE_FROM)
                o.reprompt(Lines.CHOOSE_FROM)
            }
            Q.COUNTRY_SELECT -> {
                o.don(Lines.meet(current().ref))
                o.reprompt(Lines.meet(current().ref))
            }
            Q.NUCLEAR_PROMPT -> {
                o.don(Lines.TECH_SPEND)
                o.reprompt(Lines.TECH_SPEND)
            }
            Q.ENVIRONMENT_PROMPT -> environmentPrompt(o)
            Q.RESEARCH_PROMPT -> researchPrompt(o)
            Q.UPGRADE_PROMPT -> buildOrResearchPrompt(o)
            Q.SANCTION -> sanctionPrompt(o)
            Q.SANCTION_COUNTRY, Q.SANCTION_SPECIFIC -> countrySanctionChoice(o)
            Q.CITY_PROMPT -> nextCityPrompt(o)
            Q.SHIELD_PROMPT -> shieldPrompt(o)
            Q.PHONE_COUNTRY -> {
                val c = st.countries.getOrNull(st.countryIndex) ?: return callsComplete(o)
                o.don(Lines.callImportant(c.ref))
                o.reprompt(Lines.callAgain(c.ref))
            }
            Q.BOMB_PROMPT -> {
                o.don(Lines.BUY_ANY)
                o.reprompt(Lines.BUY_NUCLEAR)
            }
            Q.BOMB_NUMBER_PROMPT -> {
                val max = maxBombs()
                if (max > 0) o.don(Lines.affordUpTo(max.coerceAtMost(World.BOMBS_MAX)))
                o.don(Lines.HOW_MANY_SAY)
                o.reprompt(Lines.HOW_MANY_SAY)
            }
            Q.REMOVE_SANCTION_PROMPT -> {
                o.don(Lines.REMOVE_FROM_ONE)
                o.reprompt(Lines.REMOVE_FROM_ONE)
            }
            Q.REMOVE_SANCTION -> removeSanctionPrompt(o)
            Q.REMOVE_INDIVIDUAL_SANCTION -> removeIndividualSanctionPrompt(o)
            Q.USE_BOMBS -> {
                o.don(Lines.USE_A_BOMB_LONG)
                o.reprompt(Lines.USE_A_BOMB_LONG)
            }
            Q.CHOOSE_BOMB_COUNTRY, Q.BOMB_INDIVIDUAL -> askWhichCountryToBomb(o)
            Q.CHOOSE_BOMB_CITY -> chooseBombCityReprompt(o)
            Q.CONFIRM_BOMB_PROMPT -> {
                val c = st.countryToBomb ?: return askWhichCountryToBomb(o)
                o.don(Lines.sureBombAll(c))
                o.reprompt(Lines.sureBombAll(c))
            }
            Q.GAME_OVER -> {
                o.don(Lines.CAN_YOU_REPEAT)
                o.reprompt(Lines.CAN_YOU_REPEAT)
            }
        }
    }

    // ----- The calls: doPhoneCountryPrompt, doPhoneCountry, doAngryCountryCall, doCallsComplete -----

    /** doPhoneCountryPrompt */
    private fun phoneCountryPrompt(o: Out) {
        st.q = Q.PHONE_COUNTRY
        val c = current()
        o.bed(theme(c.ref), 0.25)
        if (st.round < 3 && !st.doneLongCall) {
            st.doneLongCall = true
            o.bed(sfx("phoneRing"), 1.0)
            o.pause(3.0)
            o.don(Lines.callIncoming(c.ref))
        } else {
            o.bed(sfx("shortRing"), 1.0)
            o.pause(1.0)
            o.don((if (st.countryIndex > 0) Lines.onHold(c.ref) else Lines.longCall(c.ref)).random(random))
            o.don(Lines.PICK_UP.random(random))
        }
        o.stopBeds()
        o.reprompt(Lines.ANSWER)
    }

    /** The next call after one is answered or ignored. */
    private fun nextCall(o: Out) {
        when {
            st.countryIndex >= st.countries.size -> callsComplete(o)
            current().attackUs != 0 -> angryCountryCall(o)
            else -> phoneCountryPrompt(o)
        }
    }

    /**
     * doPhoneCountry: what a country does when it calls. Answered ([respond]), the call plays and the next one rings;
     * ignored (and in the final round, where nobody calls), its effects happen all the same.
     */
    private fun phoneCountry(o: Out, respond: Boolean) {
        val cur = st.countries.getOrNull(st.countryIndex) ?: return callsComplete(o)
        val us = us()
        if (respond) o.clip(sfx("pickupPhone"))
        var hungUp = false
        var doPickup = false
        var angry = false
        var sanctionUs = false
        var removeSanctions = false
        val introHello = respond && if (st.round <= 2) st.countryIndex < 2 else random.nextDouble() < 0.5
        var wasBombed = us.countriesBombed.count { it == cur.ref }
        val withNuclear = st.countries.filter { it.tech && it.ref != cur.ref }.map { it.ref }
        val doubleSanction = cur.stillSanctioned
        val sanctionedUs = cur.ref in us.sanctionedBy
        val tripleSanction = doubleSanction && sanctionedUs
        fun hello() {
            if (introHello) o.clip(audio.path(cur.ref, "PhoneHello"))
        }
        if (cur.attackUs != 0 || cur.hasAttackedUs) {
            hungUp = true
            if (respond) o.clip(sfx("hangUp"))
        } else if (cur.wasSanctioned && wasBombed == 0) {
            hello()
            val target = st.countries.filter { it.ref != cur.ref && !it.destroyed }.map { it.ref }.randomOrNull(random)
            cur.wasSanctioned = false
            cur.stillSanctioned = false
            st.requestToBomb += cur.ref to (target ?: "")
            if (respond) {
                if (sanctionedUs) {
                    removeSanctions = true
                    us.sanctioned = false
                    us.sanctionedBy.removeAll { it == cur.ref }
                }
                o.clip(audio.path(cur.ref, "SanctionsRemoved"))
                o.clip(target?.let { audio.keyed(cur.ref, "BombCountry", it) })
            }
        } else if (cur.bombedBy.isNotEmpty() && cur.strikesToUse != 0) {
            hello()
            var toBomb = cur.bombedBy.random(random)
            if (random.nextDouble() < 0.5 && wasBombed > 0) toBomb = us.ref
            var city: City? = null
            var bombingUs = false
            cur.bombify += toBomb
            val target = st.countries.find { it.ref == toBomb }
            if (target != null) {
                city = target.alive().randomOrNull(random)
            } else {
                for ((from, _) in st.requestToBomb) {
                    if (from == cur.ref) {
                        city = us.alive().randomOrNull(random)
                        bombingUs = true
                    }
                }
            }
            if (city != null) {
                // "We're going to attack <city>." (China has no clip for Cardiff: on Alexa it 404s; here it's left out)
                if (respond) o.clip(audio.keyed(cur.ref, "Attack", city.name.replace(Regex("[^A-Za-z]"), "")))
                doPickup = true
            } else if (bombingUs) {
                hungUp = true
                cur.attackUs++
                cur.hasAttackedUs = true
                if (respond) o.clip(sfx("hangUp"))
            } else if (respond) {
                o.clip(unused(cur, "general", "GeneralChat"))
            }
        } else if (wasBombed > 0 || (doubleSanction && us.sanctioned) || tripleSanction) {
            hello()
            if (wasBombed == 0) wasBombed = 1
            cur.attackUs = wasBombed + if (doubleSanction) 1 else 0
            if (respond) {
                o.clip(audio.path(cur.ref, "GotBombed"))
                angry = true
            }
        } else if (doubleSanction) {
            sanctionUs = true
            us.sanctionedBy += cur.ref
            us.sanctioned = true
            if (respond) o.clip(sfx("hangUp"))
        } else if (cur.sanctioned) {
            hello()
            cur.stillSanctioned = true
            if (respond) o.clip(audio.path(cur.ref, "RemoveSanction"))
        } else {
            hello()
            if (respond) when (cur.motivator) {
                "DEFENSE" -> o.clip(unused(cur, "defense", "DefenseSpending"))
                "ENVIRONMENT" ->
                    if (st.environment < 0) o.clip(audio.paths(cur.ref, "EnvironmentBad").randomOrNull(random))
                    else o.clip(unused(cur, "general", "GeneralChat"))
                "FRIENDLY" ->
                    if (withNuclear.isNotEmpty() && random.nextDouble() < 0.5) {
                        o.clip(audio.keyed(cur.ref, "Worried", withNuclear.random(random)))
                    } else {
                        o.clip(unused(cur, "friendly", "Friendly"))
                    }
                "NUCLEAR" ->
                    if (random.nextDouble() < 0.2) o.clip(unused(cur, "general", "GeneralChat"))
                    else o.clip(unused(cur, "nuclear", "NuclearBuilding"))
            }
        }
        if (!respond) return
        if ((wasBombed == 0 && !doubleSanction) || doPickup || sanctionUs) o.clip(sfx("pickupPhone"))
        when {
            removeSanctions -> {
                o.don(Lines.removedOnYou(cur.ref))
                o.clip(sfx("eraser"))
            }
            sanctionUs -> {
                o.don(Lines.INSTA_HANG_UP.random(random))
                o.clip(sfx("stampFx"))
                o.don(Lines.SANCTIONED_YOU)
            }
            hungUp -> o.don(Lines.INSTA_HANG_UP.random(random))
            angry -> o.don(if (tripleSanction) Lines.TRIPLE_SANCTION.random(random) else Lines.enemyAngry(cur.ref).random(random))
        }
        st.countryIndex++
        nextCall(o)
    }

    /** doAngryCountryCall: countries that want to attack you don't call (two or three in a row are said together). */
    private fun angryCountryCall(o: Out) {
        val cur = current()
        if (cur.attackUs == 0) return phoneCountryPrompt(o)
        st.countryIndex++
        val next = st.countries.getOrNull(st.countryIndex)
        if (next != null && next.attackUs != 0) {
            st.countryIndex++
            val nextNext = st.countries.getOrNull(st.countryIndex)
            if (nextNext != null && nextNext.attackUs != 0) {
                o.bed(sfx("crickets"), 0.5)
                o.don(Lines.NO_CALLS.random(random))
                o.stopBeds()
                return callsComplete(o)
            }
            val pair = World.ordered(listOf(cur.ref, next.ref))
            o.don(Lines.twoNoTalk(pair[0], pair[1]).random(random))
            if (nextNext == null) callsComplete(o) else phoneCountryPrompt(o)
        } else {
            o.don(Lines.singleNoTalk(cur.ref).random(random))
            if (next == null) callsComplete(o) else phoneCountryPrompt(o)
        }
    }

    /** doCallsComplete: on to this round's spending. */
    private fun callsComplete(o: Out) {
        st.countryIndex = 0
        val us = us()
        if (isFinalRound()) {
            st.cityIndex = 0
            o.don(if (hasFinalRoundMove()) Lines.FINAL_MOVE else Lines.FINAL)
            when {
                us.tech && us.balance >= World.BOMB -> bombPrompt(o)
                hasFinalRoundMove() -> finalShieldPrompt(o)
                else -> sanctionPromptWithCheck(o)
            }
            return
        }
        o.don(Lines.callsDone(st.round))
        val b = us.balance
        when {
            b >= World.TECH && !us.tech -> techPrompt(o, start = false)
            b >= World.ENVIRONMENT && !us.tech -> environmentPrompt(o)
            b < World.ENVIRONMENT && !us.tech -> sanctionPromptWithCheck(o)
            b >= World.BOMB && us.tech -> bombPrompt(o)
            b >= World.ENVIRONMENT && us.tech -> environmentPrompt(o)
            else -> sanctionPromptWithCheck(o)
        }
    }

    /** getNextShieldableCityIndex */
    private fun nextShieldableCity(): Int {
        val us = us()
        if (us.balance < World.SHIELD) return -1
        for (i in st.cityIndex until us.cities.size) if (!us.cities[i].destroyed && us.cities[i].shield == 0) return i
        return -1
    }

    private fun hasFinalRoundMove(): Boolean {
        val us = us()
        return (us.tech && us.balance >= World.BOMB) || us.bombs > 0 || nextShieldableCity() != -1
    }

    /** doFinalRoundStart: nobody calls, but what the calls would do happens. */
    private fun finalRoundStart(o: Out) {
        for (i in st.countries.indices) {
            st.countryIndex = i
            if (st.countries[i].attackUs == 0) phoneCountry(o, false)
        }
        callsComplete(o)
    }

    /** doFinalShieldPrompt */
    private fun finalShieldPrompt(o: Out) {
        val i = nextShieldableCity()
        if (i == -1) return bombsOrNextRound(o)
        st.cityIndex = i
        shieldPrompt(o)
    }

    // ----- The end of a round: doNextRound -----

    private fun nextRound(o: Out) {
        st.countryIndex = 0
        st.midGame = true
        st.q = Q.PHONE_COUNTRY
        val prevBalance = us().balance
        st.prevEnvironment = st.environment
        countryDecisions()
        st.round++
        bombCountries(o)
        for (c in st.countries) c.score += score(c)
        us().score += score(us())
        st.cityBombIndex = 0
        for (c in st.countries) updateBalance(c)
        updateBalance(us())
        if (st.prevEnvironment + 100 < 0) {
            heavenlyEnvironmentDestruction(o)
            us().destroyed = true
            st.countries.forEach { it.destroyed = true }
        }
        // Every other country gone (the skill counts four, so a country knocked out in an earlier round kept the
        // game going with nobody left to call; here it's over).
        val allDestroyed = st.countries.all { c -> c.cities.all { it.destroyed } }
        when {
            allDestroyed -> if (us().destroyed) everyCountryDestroyed(o) else destroyEveryOneGameOver(o)
            us().destroyed -> weGotDestroyedGameOver(o)
            st.round > 5 -> nuclearGameOver(o)
            else -> roundReport(o, prevBalance)
        }
    }

    /** The rest of doNextRound: who's out, the round, the scores and the money, then the calls. */
    private fun roundReport(o: Out, prevBalance: Long) {
        val us = us()
        val out = World.ordered(st.countries.filter { it.destroyed }.map { it.ref })
        st.countries = st.countries.filter { !it.destroyed }.toMutableList()
        o.bed(sfx("longOrchestral"), 0.10)
        if (out.isNotEmpty()) {
            o.pause(1.5)
            o.bed(sfx("deplete"), 1.0)
            o.don(Lines.countriesDestroyed(out).random(random))
        }
        o.bed(sfx("trumpet"), 1.0)
        o.pause(3.0)
        o.don(Lines.roundComplete(st.round - 1))
        if (!st.rundown) {
            o.don(Lines.SCORES)
            o.clip(sfx("woosh"))
            o.don(Lines.SCORE_PARTS)
            st.rundown = true
            val balancePoints = if (prevBalance > 5_000_000) 4 else if (prevBalance >= 2_000_000) 2 else 0
            var research = 0
            var shields = 0
            var cityPoints = 0
            for (c in us.alive()) {
                cityPoints += 5
                if (c.shield > 0) shields += 1
                if (c.research > 0) research += 2
            }
            if (balancePoints > 0) {
                o.part(Lines.bankPoints(balancePoints))
                o.money(prevBalance)
                o.don(Lines.IN_THE_BANK)
                o.clip(sfx("kaching"))
            }
            if (us.contributions > 0) {
                o.don(Lines.envPoints(us.contributions.coerceAtMost(5)))
                o.clip(sfx("upgradeEnvironment"))
            }
            when {
                research > 0 && shields == 0 -> {
                    o.don(Lines.researchAndCities(research, cityPoints))
                    o.clip(sfx("research"))
                }
                shields > 0 && research == 0 -> {
                    o.don(Lines.shieldsAndCities(shields, cityPoints))
                    o.clip(sfx("shield"))
                }
                shields > 0 -> {
                    o.don(Lines.shieldsResearchAndCities(shields, research, cityPoints))
                    o.bed(sfx("shield"), 1.0)
                    o.pause(0.5)
                    o.clip(sfx("research"))
                }
                else -> o.don(Lines.citiesOnly(cityPoints))
            }
        } else {
            val alive = us.alive()
            if (alive.isNotEmpty()) {
                // "upgraded" counts every city left, as the skill does.
                val upgraded = alive.count { it.shield > 0 || it.research > 0 }
                o.don(if (upgraded == 0) Lines.citiesNoUpgrades(alive.size) else Lines.citiesUpgraded(alive.size))
            }
            if (us.bombs > 0) o.don(Lines.reserve(bombsText(us.bombs)))
            o.pause(1.0)
        }
        o.clip(sfx("woosh"))
        scoreSpeech(o, end = false)
        val earned = us.balance - prevBalance
        if (earned == 0L) {
            o.don(Lines.NO_EARNINGS)
        } else {
            if (earned < 0) {
                o.part(Lines.YOU_LOST)
                o.money(-earned)
                o.don(Lines.THIS_ROUND)
            } else {
                o.part(Lines.YOU_RECEIVED)
                o.money(earned)
                o.don(Lines.IN_EARNINGS)
                o.clip(sfx("kaching"))
            }
            o.part(Lines.YOU_HAVE)
            o.money(us.balance)
            o.don(Lines.TO_SPEND)
        }
        o.stopBeds()
        st.citiesToBomb.clear()
        if (isFinalRound()) return finalRoundStart(o)
        val first = current()
        if (first.attackUs != 0 || first.hasAttackedUs) angryCountryCall(o) else phoneCountryPrompt(o)
    }

    /** calculateScoreForCountry */
    private fun score(c: Nation): Int {
        var s = if (c.balance > 5_000_000) 4 else if (c.balance >= 2_000_000) 2 else 0
        s += c.contributions
        for (city in c.alive()) {
            s += 5
            if (city.shield > 0) s += 1
            if (city.research > 0) s += 2
        }
        return s
    }

    /** updateCountryBalance */
    private fun updateBalance(c: Nation) {
        var add = 0.0
        for (city in c.cities) {
            if (!city.destroyed) add += 3_000_000
            if (city.research > 0) add += 1_000_000
        }
        add += st.environment * 100_000.0
        if (c.sanctioned) add = floor(add * 0.8)
        c.balance += add.toLong()
        if (c.balance < 0) c.balance = 0
    }

    // ----- What the other countries do: doCountryDecisions -----

    private fun rnd() = random.nextDouble()

    /** randomIntFromInterval */
    private fun randomInt(min: Int, max: Int) = floor(rnd() * (max - min + 1) + min).toInt()

    private fun countryDecisions() {
        val lateRounds = st.round > 3
        val us = us()
        for (x in st.countries) {
            if (x.destroyed) continue
            if (x.alive().size == 1 && x.balance >= World.SHIELD) {
                for (c in x.cities) if (!c.destroyed && c.shield == 0) {
                    c.shield++
                    x.balance -= World.SHIELD
                }
            }
            fun contribute() {
                x.balance -= World.ENVIRONMENT
                x.contributions++
                st.environment += 15
            }
            when (x.motivator) {
                "ENVIRONMENT" -> {
                    if (x.balance >= World.ENVIRONMENT) contribute()
                    if (lateRounds && x.tech) maxOutBombs(x)
                    if ((x.bombedBy.isNotEmpty() || st.environment < 0 || x.ref in us.countriesBombed) && x.tech) maxOutBombs(x)
                    buyShieldsOrResearch(x)
                }
                "DEFENSE" -> {
                    if (x.balance >= World.ENVIRONMENT) contribute()
                    maxOutShields(x)
                    // Its bombs: the skill works out how many from NaN, so it never buys any.
                    if (st.round >= 2 || x.bombedBy.isNotEmpty() || x.ref in us.countriesBombed) {
                        if (!x.tech && x.balance >= World.TECH) {
                            x.balance -= World.TECH
                            x.tech = true
                            st.environment -= 10
                        }
                    }
                    var research = min(3L, x.balance / World.RESEARCH).toInt()
                    if (research > 0) research = randomInt(1, research)
                    for (c in x.cities) if (!c.destroyed && c.research == 0 && research > 0) {
                        c.research++
                        research--
                        x.balance -= World.RESEARCH
                    }
                }
                "FRIENDLY" -> {
                    if (x.balance >= World.ENVIRONMENT) contribute()
                    randomlyBuyNuclearStuff(x)
                    randomlyBuyNuclearStuff(x)
                    if (x.ref == "Russia" && rnd() < 0.65) nuclearTechPurchasing(x)
                    if (rnd() < 0.5) nuclearTechPurchasing(x)
                    buyShieldsOrResearch(x)
                }
                "NUCLEAR" -> {
                    if (x.balance >= World.ENVIRONMENT && rnd() < 0.5) contribute()
                    if (lateRounds && x.tech) maxOutBombs(x)
                    nuclearTechPurchasing(x)
                    if (st.round == 1) {
                        for (c in x.cities) if (x.balance >= World.SHIELD && !c.destroyed && c.shield == 0) {
                            c.shield++
                            x.balance -= World.SHIELD
                        }
                    } else if (rnd() < 0.2) {
                        buyShieldsOrResearch(x)
                    }
                    if (x.balance < 5_000_000) buyResearchEverywhere(x)
                    // The skill sets a chance of shields from the research count, but only checks it isn't zero.
                    if (x.cities.any { it.research > 0 }) {
                        for (c in x.cities) if (x.balance >= World.SHIELD && !c.destroyed && c.shield == 0) {
                            c.shield++
                            x.balance -= World.SHIELD
                        }
                    } else {
                        buyResearchEverywhere(x)
                    }
                }
            }
        }
    }

    private fun buyResearchEverywhere(x: Nation) {
        for (c in x.cities) if (x.balance >= World.RESEARCH && !c.destroyed && c.research == 0) {
            c.research++
            x.balance -= World.RESEARCH
        }
    }

    private fun buyBomb(x: Nation) {
        x.balance -= World.BOMB
        x.bombs++
        x.strikesToUse++
        st.environment -= 5
    }

    /** randomlyBuyNuclearStuff */
    private fun randomlyBuyNuclearStuff(x: Nation) {
        val options = mutableListOf<String>()
        if (x.balance >= World.RESEARCH && x.cities.any { !it.destroyed && it.research == 0 }) options += "research"
        if (x.balance >= World.SHIELD && x.cities.any { !it.destroyed && it.shield == 0 }) options += "shield"
        if (x.tech && st.round >= 2 && x.balance >= World.BOMB) options += "bombs"
        when (options.randomOrNull(random)) {
            "research" -> {
                x.balance -= World.RESEARCH
                x.cities.filter { !it.destroyed && it.research == 0 }.randomOrNull(random)?.let { it.research++ }
            }
            "shield" -> {
                x.balance -= World.SHIELD
                x.cities.filter { !it.destroyed && it.shield == 0 }.randomOrNull(random)?.let { it.shield++ }
            }
            "bombs" -> buyBomb(x)
        }
    }

    /** doNuclearTechPurchasing */
    private fun nuclearTechPurchasing(x: Nation) {
        if (x.tech) {
            val amount = (x.balance / World.BOMB).toInt()
            if (amount > 0 && x.bombs < 4) repeat(amount.coerceAtMost(100)) { if (x.bombs < 5) buyBomb(x) }
        } else if (x.balance >= World.TECH) {
            x.tech = true
            x.balance -= World.TECH
            st.environment -= 10
        }
    }

    /** countryBuyShieldsOrResearch */
    private fun buyShieldsOrResearch(x: Nation) {
        var research = min(3L, x.balance / World.RESEARCH)
        var shields = min(3L, x.balance / World.SHIELD)
        for (c in x.cities) {
            if (rnd() > 0.7 && !c.destroyed && c.research == 0 && research > 0 && x.balance >= World.RESEARCH) {
                c.research++
                research--
                x.balance -= World.RESEARCH
            } else if (!c.destroyed && c.shield == 0 && shields > 0 && x.balance >= World.SHIELD) {
                c.shield++
                shields--
                x.balance -= World.SHIELD
            }
        }
    }

    /** maxOutBombs */
    private fun maxOutBombs(x: Nation) {
        val amount = (x.balance / World.BOMB).toInt()
        if (amount > 0 && x.bombs < 3) repeat(amount.coerceAtMost(100)) { if (x.bombs < 5) buyBomb(x) }
    }

    /** maxOutShields */
    private fun maxOutShields(x: Nation) {
        var n = min(3L, x.balance / World.SHIELD)
        if (n > 0) for (c in x.cities) if (!c.destroyed && c.shield == 0 && n > 0) {
            c.shield++
            n--
            x.balance -= World.SHIELD
        }
    }

    // ----- The bombing: bombCountries -----

    private class Bombing {
        val destroyedCities = mutableListOf<String>()
        val destroyedShields = mutableListOf<String>()
        /** additionalBombingMap: each country's targets this round, in the order they bombed. */
        val strikes = linkedMapOf<String, MutableList<String>>()
        var total = 0

        fun hit(city: City) {
            if (city.shield > 0) {
                city.shield--
                destroyedShields += city.name
            } else {
                city.destroyed = true
                destroyedShields.removeAll { it == city.name }
                destroyedCities += city.name
            }
        }
    }

    private fun bombCountries(o: Out) {
        val b = Bombing()
        b.total = st.citiesToBomb.size
        val us = us()
        for (x in st.countries) {
            for (city in x.cities) repeat(st.citiesToBomb.count { it == city.name }) { b.hit(city) }
            if (x.strikesToUse == 0) continue
            var amount = if (x.strikesToUse < 3) x.strikesToUse else randomInt(3, x.strikesToUse)
            if (st.round > 4) amount = x.strikesToUse
            val bombedByThis = mutableListOf<String>()
            repeat(amount.coerceAtMost(100)) {
                val insufficient = us.contributions == 0
                when {
                    // (this strike isn't counted in the skill's total, so it doesn't harm the environment)
                    x.attackUs != 0 && x.bombify.isEmpty() -> bombOurCountry(x, bombedByThis, b)
                    x.bombify.isNotEmpty() || x.attackUs != 0 || insufficient -> {
                        val struck = when {
                            x.bombify.isNotEmpty() && x.attackUs != 0 ->
                                if (rnd() > 0.6 || insufficient) bombOurCountry(x, bombedByThis, b) else bombifyCountry(x, bombedByThis, b)
                            x.bombify.isNotEmpty() -> bombifyCountry(x, bombedByThis, b)
                            else -> bombOurCountry(x, bombedByThis, b)
                        }
                        if (struck) b.total++
                    }
                    else -> fudge(x, bombedByThis, b)
                }
            }
        }
        for (c in st.countries) if (!c.destroyed && c.cities.count { it.destroyed } == 3) c.destroyed = true
        if (us.cities.count { it.destroyed } == 3) us.destroyed = true

        if (st.citiesToBomb.isNotEmpty()) {
            o.part(Lines.YOU_WILL_BOMB)
            o.items(st.citiesToBomb.distinct(), Lines.Last.END)
        }
        val ours = World.land(us.ref).cities
        for ((ref, cities) in b.strikes) {
            val mine = cities.filter { it in ours }
            val others = cities.filter { it !in ours }
            if (mine.isNotEmpty()) {
                o.bed(sfx("alarm"), 0.5)
                o.pause(1.0)
                o.part(Lines.isBombing(ref).random(random))
                o.items(mine, Lines.Last.END)
                if (others.isNotEmpty()) {
                    o.part(Lines.ALSO_BOMBING)
                    o.items(others, Lines.Last.END)
                }
            } else {
                o.part(Lines.isBombing(ref).random(random))
                o.items(cities, Lines.Last.END)
            }
        }
        if (st.citiesToBomb.isEmpty() && b.strikes.isEmpty()) return
        repeat(b.total) {
            if (st.environment > -100) {
                st.environment -= 5
                st.prevEnvironment -= 5
            }
        }
        for (n in Lines.COUNTDOWN) {
            o.don(n)
            o.clip(sfx("singleBeep"))
        }
        o.clip(sfx("dropExplode"))
        val cities = b.destroyedCities.distinct()
        val shields = b.destroyedShields.distinct()
        if (cities.isEmpty() && shields.isEmpty()) return
        o.bed(audio.paths("sfx", "dramaticFx").randomOrNull(random), 1.0)
        o.bed(sfx("orchestralShort"), 1.0)
        o.pause(0.5)
        if (cities.size == 1) {
            o.don(Lines.destroyCity(cities[0]).random(random))
        } else if (cities.size > 1) {
            o.items(cities, Lines.Last.ON)
            o.don(Lines.DESTROY_CITIES.random(random))
        }
        if (shields.size == 1) {
            o.don(Lines.destroyShield(shields[0]).random(random))
        } else if (shields.size > 1) {
            val (lead, tail) = Lines.DESTROY_SHIELDS.random(random)
            o.part(lead)
            o.items(shields, Lines.Last.ON)
            o.don(tail)
        }
        o.stopBeds()
    }

    private fun strike(x: Nation, city: City, bombedByThis: MutableList<String>, b: Bombing) {
        bombedByThis += city.name
        b.strikes.getOrPut(x.ref) { mutableListOf() } += city.name
        b.hit(city)
    }

    /** bombOurCountry: true if a bomb was dropped. */
    private fun bombOurCountry(x: Nation, bombedByThis: MutableList<String>, b: Bombing): Boolean {
        val ours = us().cities.filter { !it.destroyed && it.name !in bombedByThis }
        if (ours.isEmpty()) return false
        x.attackUs--
        x.strikesToUse--
        x.bombs--
        x.hasAttackedUs = true
        // With three cities the skill's random choice never works: it's always the first.
        val i = if (ours.size == 2 && rnd() >= 0.7) 1 else 0
        strike(x, ours[i], bombedByThis, b)
        return true
    }

    /** bombifyCountry: a country bombing back at one that bombed it (always its first city that's left). */
    private fun bombifyCountry(x: Nation, bombedByThis: MutableList<String>, b: Bombing): Boolean {
        val target = st.countries.filter { it.ref in x.bombify }.randomOrNull(random)
        if (target == null) {
            x.bombify.clear()
            return false
        }
        val city = target.cities.firstOrNull { !it.destroyed && it.name !in bombedByThis } ?: return false
        x.strikesToUse--
        x.bombs--
        strike(x, city, bombedByThis, b)
        return true
    }

    /**
     * The skill's "fudge": a strike at another computer country, sometimes the leader's or Russia's cities (never
     * yours: its check for that compares a boolean with a string).
     */
    private fun fudge(x: Nation, bombedByThis: MutableList<String>, b: Bombing) {
        val places = st.countries.filter { it.ref != x.ref }
            .flatMap { c -> c.cities.filter { !it.destroyed && it.name !in bombedByThis }.map { it.name } }
        if (places.isEmpty()) return
        x.strikesToUse--
        x.bombs--
        b.total++
        val leader = st.countries.sortedByDescending { score(it) }.firstOrNull()
        var place: String? = null
        if (leader != null) {
            val theirs = places.filter { p -> leader.cities.any { it.name == p } }
            if (theirs.isNotEmpty() && rnd() < 0.3) place = theirs.random(random)
        }
        if (place == null && st.countries.any { it.ref == "Russia" }) {
            val russian = places.filter { it in World.land("Russia").cities }
            if (russian.isNotEmpty() && rnd() < 0.2) place = russian.random(random)
        }
        val target = place ?: places.random(random)
        for (c in st.countries) for (city in c.cities) if (city.name == target) {
            c.bombedBy += x.ref
            strike(x, city, bombedByThis, b)
        }
    }

    // ----- Scores: getNuclearTeamRanks, createScoresArray, getAllScoreSpeech, doGameOverScoreSpeech -----

    /** A country's score in the rankings ([ref] null: you). */
    private data class Rank(val ref: String?, val score: Int)

    /** The countries still in the war and you, best first, ties grouped (you first in a pair, last in a bigger tie). */
    private fun scoreGroups(): List<List<Rank>> {
        val all = (st.countries.filter { !it.destroyed }.map { Rank(it.ref, it.score) } +
            listOfNotNull(us().takeIf { !it.destroyed }?.let { Rank(null, it.score) })).sortedByDescending { it.score }
        val groups = mutableListOf<MutableList<Rank>>()
        for (r in all) if (groups.isNotEmpty() && groups.last().last().score == r.score) groups.last() += r else groups += mutableListOf(r)
        return groups.map { g ->
            if (g.size < 2) g else {
                val usHere = g.filter { it.ref == null }
                val others = g.filter { it.ref != null }
                if (g.size == 2) usHere + others else others + usHere
            }
        }
    }

    /** The place said for a group: "last", "first", or its ordinal counting the ties above it. */
    private fun placeOf(groups: List<List<Rank>>, x: Int): String {
        if (x == groups.size - 1) return "last"
        if (x == 0) return "first"
        var place = x + 1
        val above = groups.take(x).sumOf { it.size }
        if (place in 2..4 && above > x) place += above - x
        return World.ordinal(place)
    }

    /** The scores, last place first (getAllScoreSpeech; [end]: doGameOverScoreSpeech, "came" not "are in"). */
    private fun scoreSpeech(o: Out, end: Boolean) {
        val groups = scoreGroups()
        for (x in groups.indices.reversed()) {
            val place = placeOf(groups, x)
            val group = groups[x]
            val first = end && place == "first"
            if (first) {
                o.bed(sfx("marching"), 1.0)
                o.pause(3.0)
                o.bed(sfx("triumph"), 1.0)
                o.pause(2.0)
            }
            if (group.size > 1) {
                o.items(group.map { Lines.subject(it.ref) }, if (end) Lines.Last.ON else Lines.Last.COMMA)
                o.part(if (end) Lines.endTiePlacing(place) else Lines.tiePlacing(place))
            } else {
                o.part(if (end) Lines.endPlacing(group[0].ref, place) else Lines.placing(group[0].ref, place))
            }
            o.don(Lines.points(group.last().score))
        }
    }

    // ----- Game over -----

    /** doNuclearGameOver: the five rounds are done. */
    private fun nuclearGameOver(o: Out) {
        st.playedNuclear = true
        o.bed(sfx("longOrchestral"), 0.20)
        o.clip(sfx("trumpet"))
        o.don(Lines.GAME_OVER)
        st.completed = true
        // (The skill's "<country> was knocked out" lines need countries it only lists when the environment
        // collapses, and then the game ends the other way: they're never said.)
        scoreSpeech(o, end = true)
        val groups = scoreGroups()
        for (r in groups[0]) if (r.ref != null) o.clip(audio.path(r.ref, "Victory"))
        o.stopBeds()
        val ours = groups.indexOfFirst { g -> g.any { it.ref == null } }
        val place = placeOf(groups, ours)
        val title = when {
            ours == 0 && groups[0].size == 1 -> "You won the war!"
            ours == 0 -> "You came joint first"
            else -> "You came $place"
        }
        finish("ending", title)
    }

    /** everyCountryDestroyed */
    private fun everyCountryDestroyed(o: Out) {
        o.bed(sfx("longOrchestral"), 0.25)
        o.don(Lines.EVERY_COUNTRY)
        o.stopBeds()
        finish("gameover", "Every country was destroyed")
    }

    /** destroyEveryOneGameOver: you're the last country standing. */
    private fun destroyEveryOneGameOver(o: Out) {
        o.bed(sfx("longOrchestral"), 0.25)
        o.don(Lines.EVERYONE_DESTROYED.random(random))
        o.bed(sfx("marching"), 1.0)
        o.pause(3.0)
        o.bed(sfx("triumph"), 1.0)
        o.pause(2.0)
        o.don(Lines.victory(us().ref))
        o.stopBeds()
        finish("ending", "The last country standing!")
    }

    /** doWeGotDestroyedGameOver */
    private fun weGotDestroyedGameOver(o: Out) {
        o.bed(sfx("longOrchestral"), 0.30)
        o.pause(1.5)
        o.don(Lines.WE_LOSE.random(random))
        o.don(Lines.GAME_OVER)
        o.stopBeds()
        finish("gameover", "Your cities were destroyed")
    }

    /** doHeavenlyEnvironmentDestruction: the environment gave out. */
    private fun heavenlyEnvironmentDestruction(o: Out) {
        o.bed(sfx("halo"), 0.40)
        o.pause(0.5)
        o.don(Lines.LIGHTNING)
        o.bed(sfx("thunderbolt"), 1.0)
        o.pause(3.0)
        o.clip(sfx("dropExplode"))
        o.don(Lines.WAR_STOPPED)
        o.stopBeds()
    }
}
