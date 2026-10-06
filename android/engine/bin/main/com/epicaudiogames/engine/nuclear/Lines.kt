package com.epicaudiogames.engine.nuclear

/**
 * Don's lines: what Alexa said in Nuclear War (the skill's addVoice calls and its Speech.js lists), word for word but
 * for punctuation, and with fewer of the random variations that have a name in them. Each line is one clip, found by
 * its text. A line with a name or a small number in it has a clip per value; lists of names, money and points are
 * said in pieces that carry on into each other (see [items] and [NuclearWar]).
 *
 * [all] lists every text the game can say, with the words around each piece so it's rendered as part of a sentence:
 * tools/games/nuclearwar.py renders them all, and NuclearWarTest checks that the game says nothing else.
 */
object Lines {
    /**
     * A text to render: [speak] is what Don reads when it differs from what's shown ("Saint Petersburg"); [before] and
     * [after] are the words around a piece of a sentence.
     */
    data class Phrase(val text: String, val speak: String, val before: String = "", val after: String = "")

    private fun cap(s: String) = s.replaceFirstChar { it.uppercaseChar() }
    private fun v(ref: String) = World.voice(ref)
    private fun bombs(n: Int) = if (n == 1) "bomb" else "bombs"
    private fun pts(n: Int) = if (n == 1) "point" else "points"

    /**
     * What Don is given to read for a text: numbers in words (ElevenLabs reads digits well, but its timings for them
     * are unreliable, and the clips are cut by those timings), and a few names as they're said.
     */
    fun speak(text: String): String =
        NUMBER.replace(text.replace("St Petersburg", "Saint Petersburg").replace("500K", "500 thousand")
            .replace("%", " percent")) { m ->
            val (whole, fraction) = m.value.replace(",", "").split(".").let { it[0] to it.getOrNull(1) }
            spell(whole.toLong()) + (fraction?.let { f -> " point " + f.map { spell(it.digitToInt().toLong()) }.joinToString(" ") } ?: "")
        }

    private val NUMBER = Regex("\\d[\\d,]*(\\.\\d+)?")
    private val SMALL = listOf("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    private val TENS = listOf("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")

    /** 109 is "one hundred nine", as ElevenLabs says it. */
    fun spell(n: Long): String = when {
        n < 20 -> SMALL[n.toInt()]
        n < 100 -> TENS[(n / 10).toInt()] + if (n % 10 != 0L) "-" + SMALL[(n % 10).toInt()] else ""
        n < 1000 -> SMALL[(n / 100).toInt()] + " hundred" + if (n % 100 != 0L) " " + spell(n % 100) else ""
        n < 1_000_000 -> spell(n / 1000) + " thousand" + if (n % 1000 != 0L) " " + spell(n % 1000) else ""
        else -> spell(n / 1_000_000) + " million" + if (n % 1_000_000 != 0L) " " + spell(n % 1_000_000) else ""
    }

    private const val OPTIONS = "France, the USA, the UK, China or Russia"

    // ----- Starting: doPlayNuclearWar, doChooseCountry, the meetings -----

    const val WELCOME = "Welcome to the nuclear war game."
    const val PLAY_AS = "Would you like to play as $OPTIONS?"
    const val WELCOME_BACK = "Welcome back to nuclear war. Would you like to play as $OPTIONS?"
    const val WHICH_COUNTRY = "Which country would you like to play as? $OPTIONS."
    const val CHOOSE_FROM = "Choose from: $OPTIONS."
    const val MEET_FIRST =
        "Before making decisions in round one, it is a good idea to meet the representatives from the other countries."

    fun leaderOf(ref: String) = "You are now the leader of ${v(ref)}."
    fun meet(ref: String) = "Would you like to meet ${v(ref)}?"
    fun meetFinally(ref: String) = "Finally, would you like to meet ${v(ref)}?"
    fun meetLeader(ref: String) = "Would you like to meet the leader of ${v(ref)}?"

    // ----- Spending: nuclear tech, the environment, the cities -----

    const val TECH_START = "Round 1. Now let's spend that 10 million. The first decision is to spend 5 million and " +
        "invest in nuclear tech. Do you want to invest in nuclear tech?"
    const val TECH = "Do you want to invest in nuclear tech?"
    const val TECH_SPEND = "Would you like to spend 5 million on nuclear tech?"
    const val TECH_DONE = "You now have nuclear tech. In the next round you will be able to buy bombs."
    const val ENV_START = "Would you like to spend 1 million and improve the environment by 15%?"
    const val ENV = "Would you like to spend 1 million on the environment?"
    const val ENV_BACK = "The environment is back to 100 percent."
    fun envAt(percent: Int) = "The environment is at $percent percent."
    const val ENV_EXTRA = "This will bring in an extra 500K for all countries each round."
    const val SPENT_ALL = "You have spent all your money."
    const val DONE_ALL = "You've done work to all your cities."
    const val EVERY_CITY = "You've gone through every city."
    const val ALL_CITIES = "You've gone through all your cities."
    const val COSTS = "A shield costs 3 million, and research costs 2 million."
    const val SHIELD_OR_RESEARCH = "Want to build a shield, or do research?"
    const val SHIELD_OR_RESEARCH_AGAIN = "Build a shield, or do research?"

    fun wantUpgrade(city: String) = "Want to upgrade $city?"
    fun anyUpgradesOn(city: String) = "Do you want to do any upgrades on $city?"
    fun upgradesTo(city: String) = "Do you want to do upgrades to $city?"
    fun anyUpgradesTo(city: String) = "Do you want to do any upgrades to $city?"
    fun threeCities(a: String, b: String, c: String) =
        "Now you have 3 cities to defend and improve. $a, $b and $c. Do you want to do upgrades to $a?"
    fun howAbout(city: String) = "How about $city?"
    fun upgradesOn(city: String) = "Want to do upgrades on $city?"
    fun researchFor(city: String) = "Would you like to do research for $city?"
    fun researchProductivity(city: String) = "Would you like to do research and increase productivity of $city?"
    fun shieldFor(city: String) = "Would you like to build a shield for $city?"
    fun productivity(city: String) = "$city now has increased productivity and will bring in an extra 1 million every round."
    fun protectedNow(city: String) = "$city is now protected from one nuclear strike."
    fun alreadyShield(city: String) = "You already have a shield on $city."
    fun noMoneyShield(city: String) = "You don't have enough money for a shield for $city."
    fun alreadyResearch(city: String) = "You already have research on $city."

    // ----- Sanctions -----

    const val REMOVE_ANY = "Want to remove any sanctions?"
    const val ADD_ANY = "Want to add any sanctions?"
    const val ADD_ANY_LONG = "Would you like to add sanctions to any country?"
    const val SANCTION_ANY = "Would you like to sanction any country?"
    const val REMOVE_FROM_ONE = "Would you like to remove sanctions from a country?"
    const val REMOVE_MORE = "Would you like to remove anymore sanctions?"
    const val SANCTIONED_ALL = "You have sanctioned all the countries."
    const val SANCTION_ANOTHER = "Want to sanction another country?"
    const val SANCTION_OWN = "You can't sanction your own country!"
    const val UNSANCTION_OWN = "You can't unsanction your own country!"
    const val SANCTIONED_YOU = "They've just sanctioned you."

    /** "Sanction France, the UK or China." (2 to 4 countries, in [World.ordered] order). */
    fun sanctionList(refs: List<String>): String {
        val n = refs.map(::v)
        return when (n.size) {
            4 -> "Sanction ${n[0]}, ${n[1]}, ${n[2]} or ${n[3]}."
            3 -> "Sanction ${n[0]}, ${n[1]} or ${n[2]}."
            else -> "Sanction ${n[0]} or ${n[1]}."
        }
    }

    fun sanctionOne(ref: String) = "Would you like to sanction ${v(ref)}?"
    fun sanctioned(ref: String) = "${cap(v(ref))} has been sanctioned."
    fun alreadySanctioned(ref: String) = "You have already sanctioned ${v(ref)}."
    fun cantSanction(ref: String) = "You can't sanction ${v(ref)}."

    /** The skill's doRemoveSanctionPrompt list: "France, the UK, or China." */
    private fun orList(refs: List<String>): String {
        val n = refs.map(::v)
        return n.dropLast(1).joinToString(", ") + ", or " + n.last() + "."
    }

    fun removeList(refs: List<String>) = "Remove sanctions from ${orList(refs)}"
    fun removeListAgain(refs: List<String>) = "Which country would you like to remove sanctions from? ${orList(refs)}"
    fun removeOne(ref: String) = "Would you like to remove sanctions from ${v(ref)}?"
    fun youRemoved(ref: String) = "You have removed the sanctions on ${v(ref)}."
    fun noSanctionsOn(ref: String) = "${cap(v(ref))} doesn't have any sanctions!"
    fun notToUnsanction(ref: String) = "${cap(v(ref))} is not available to unsanction."
    fun removedOnYou(ref: String) = "${cap(v(ref))} has removed the sanctions on your country."

    // ----- Bombs: buying and aiming -----

    fun bombsLeft(n: Int) = "You have $n ${bombs(n)} left."
    fun haveBombs(n: Int) = "You have $n ${bombs(n)}."
    fun buyMore(n: Int) = "You have $n ${bombs(n)}, want to buy anymore?"
    fun buyMoreAgain(n: Int) = "You have $n ${bombs(n)}, would you like to buy anymore?"
    fun affordUpTo(n: Int) = "You can afford up to $n ${bombs(n)}."
    fun nowHave(n: Int) = "You now have $n ${bombs(n)} and"
    fun dontUse(n: Int) = "You don't use your ${bombs(n)}."
    fun keepForLater(n: Int) = "You keep your $n ${bombs(n)} for later."
    fun reserve(n: Int) = "Finally, you have $n ${bombs(n)} in reserve."
    fun directedAll(n: Int) = "You have directed all $n of your bombs."
    const val DIRECTED_ONE = "You have directed your only bomb."
    const val DIRECTED_TWO = "You have directed both of your bombs."
    const val USE_IT = "Would you like to use it?"
    const val USE_ANOTHER = "Want to use another bomb?"
    const val USE_ANOTHER_AGAIN = "Would you like to use another bomb?"
    const val USE_ONE = "Want to use one?"
    const val USE_A_BOMB = "Want to use a bomb?"
    const val USE_A_BOMB_LONG = "Would you like to use a bomb?"
    const val BUY_ANY = "Would you like to buy any bombs?"
    const val BUY_NUCLEAR = "Would you like to buy nuclear bombs?"
    const val BOMB_COST = "Bombs cost 3 million each."
    const val HOW_MANY = "How many bombs would you like to buy?"
    const val HOW_MANY_SAY = "How many bombs would you like to buy? Say a number."
    const val DIDNT_CATCH = "Didn't catch that."
    const val ONE_PER_CITY = "You can only use one bomb per city."
    const val OWN_COUNTRY = "I don't think bombing your own country is a good idea."
    const val CAN_YOU_REPEAT = "Can you repeat that?"

    /** "Attack France, the UK or China." (2 to 4 countries). */
    fun attackCountries(refs: List<String>): String {
        val n = refs.map(::v)
        return "Attack " + when (n.size) {
            4 -> "${n[0]}, ${n[1]}, ${n[2]} or ${n[3]}."
            3 -> "${n[0]}, ${n[1]}, or ${n[2]}."
            else -> "${n[0]} or ${n[1]}."
        }
    }

    fun whichCountryAttack(refs: List<String>) = "Which country would you like to attack? " + attackCountries(refs).removePrefix("Attack ")
    fun wantAttack(ref: String) = "Want to attack ${v(ref)}?"
    fun wouldAttack(ref: String) = "Would you like to attack ${v(ref)}?"
    fun cantBomb(ref: String) = "You can't bomb ${v(ref)}."
    fun allSet(ref: String) = "You have already set bombs on all cities in ${v(ref)}."
    fun noCitiesLeft(ref: String) = "${cap(v(ref))} hasn't got any cities left! You can't attack them."
    fun notEnoughForAll(ref: String) = "You don't have enough bombs to bomb all of ${v(ref)}'s cities."
    fun sureBomb(ref: String) = "Are you sure you want to bomb ${v(ref)}?"
    fun sureBombAll(ref: String) = "You've gone through all the cities. Are you sure you want to bomb ${v(ref)}?"
    fun definitely(ref: String) = "${cap(v(ref))} is definitely going to get it."

    private fun cityOptions(cities: List<String>) =
        if (cities.size == 2) "${cities[0]} or ${cities[1]}" else "${cities[0]}, ${cities[1]} or ${cities[2]}"

    /** "Attack Paris, Lyon or Marseille." (2 or 3 of one country's cities). */
    fun attackCities(cities: List<String>) = "Attack ${cityOptions(cities)}."
    fun attackAll(cities: List<String>) = "Attack ${cities[0]}, ${cities[1]}, ${cities[2]}, or all of them."
    fun whichCity(cities: List<String>) = "Which city do you want to attack? ${cityOptions(cities)}."
    fun wouldAttackCity(city: String) = "Would you like to attack $city?"
    fun wantAttackCity(city: String) = "Want to attack $city?"
    fun oneLeft(city: String) = "There's just one city left in ${v(World.landOf(city).ref)}. $city. Want to attack it?"
    fun launched(city: String) = "A bomb will be launched on $city."
    fun picked(city: String) = "$city."
    fun alreadyDestroyed(city: String) = "$city has already been destroyed."
    fun bombSelf(city: String) = listOf(
        "It would be rather silly to bomb $city, it's your own city!",
        "Bombing $city? No way! You don't want to destroy the place you live in.",
        "Bombing your own city would probably backfire.",
        "Don't bomb your own city! People will complain.",
    )

    // ----- The calls -----

    fun callIncoming(ref: String) = "A call from ${v(ref)} is incoming. Would you like to answer?"
    const val ANSWER = "Would you like to answer?"
    fun callImportant(ref: String) = "Would you like to answer a call from ${v(ref)}, it might be important."
    fun callAgain(ref: String) = "Would you like to answer a call from ${v(ref)}?"

    fun longCall(ref: String): List<String> {
        val c = v(ref)
        return listOf(
            "${cap(c)} is calling.", "${cap(c)} is ringing.", "${cap(c)} is on the line.", "It's $c on the phone.",
            "A call from $c is incoming.", "Incoming call from $c.", "You have a call from $c waiting.",
            "Your phone is ringing, it's $c.",
        )
    }

    fun onHold(ref: String): List<String> {
        val c = cap(v(ref))
        return listOf(
            "$c is on hold.", "$c is waiting.", "$c wants to speak with you.", "$c would like a chat.",
            "$c is waiting to talk.", "$c is on the line.",
        )
    }

    val PICK_UP = listOf(
        "Want to answer?", "Want to pick up?", "Shall we hear what they have to say?", "Want to listen?",
        "Will you pick up the phone?", "Want to chat?",
    )

    val NO_CALLS = listOf(
        "It appears no one feels like giving you a call this round. Curious...",
        "This round, it's as if everyone is hesitant to dial your number. Peculiar.",
        "The lack of phone calls this round is quite baffling.",
        "Seems like no calls are coming through this round. Intriguing...",
        "This round, the phone remains quiet. Unexpected. Or maybe not.",
        "No one appears to be reaching out this round. How unusual.",
        "No calls for you this round, which is rather strange.",
        "This round, no one seems to be dialing your digits. How odd.",
        "Nobody seems to have you on speed dial this round. How bizarre.",
        "The phone lines seem unusually quiet this round.",
    )

    val INSTA_HANG_UP = listOf(
        "They hung up straight away. Seems like they're trying to send a message.",
        "They hung up instantly. How cheeky.",
        "They hang up. Now that's a power move.",
        "Psych! They didn't even say anything.",
        "An immediate hang-up. It's as if they're making a statement.",
        "They disconnected. How sassy.",
        "They hung up without a word.",
        "The line went dead instantly. A silent protest.",
        "Click! They hung up, just like that.",
        "The call was over before it began.",
        "No conversation necessary, apparently.",
        "They didn't bother with small talk.",
    )

    val TRIPLE_SANCTION = listOf(
        "It's probably to do with sanctioning them for so long.",
        "It might be to do with the sanctioning.",
        "I think the sanctioning has taken its toll.",
        "It might be related to the duration of the sanctions.",
        "Sanctioning over time seems to have had an effect.",
        "Extended sanctioning might be a contributing factor.",
        "The ongoing sanctions could be taking their toll.",
        "It might be due to the long-standing sanctions.",
    )

    fun enemyAngry(ref: String): List<String> {
        val l = World.land(ref).leaderSays
        return listOf(
            "Gosh, $l sounds really annoyed.", "Oh dear, $l has had better days.", "Yikes, $l is really steamed up.",
            "Oh my, $l is not a happy camper right now.", "Blimey, $l is quite miffed.",
            "Holy smokes, $l is fuming like a volcano!", "Uh-oh, you've really ruffled $l's feathers.",
            "$l needs to take a breather.",
            "You've really riled them up. Watch out.", "Woops, you've definitely struck a chord with them.",
            "Golly, that was an awkward call.", "That call was hotter than a jalapeño!",
            "Well, that was a spicy meatball of a conversation!",
        )
    }

    fun singleNoTalk(ref: String): List<String> {
        val c = v(ref)
        return listOf(
            "${cap(c)} doesn't want to talk. How weird.", "${cap(c)} doesn't want to chat. Now that's peculiar.",
            "Looks like $c is giving us the cold shoulder.", "${cap(c)} has decided to ghost us. How mature.",
            "Seems like $c is taking a vow of silence.",
            "${cap(c)} is ignoring us. Did we forget their birthday or something?",
        )
    }

    /** Two countries, in [World.ordered] order. */
    fun twoNoTalk(a: String, b: String): List<String> {
        val x = v(a)
        val y = v(b)
        return listOf("${cap(x)} and $y don't want to talk.", "${cap(x)} and $y seem to be unavailable.",
            "Neither $x or $y want to talk.")
    }

    fun callsDone(round: Int) = "All calls done. Round $round out of 5."
    const val FINAL_MOVE = "Final round! Last chance to protect your cities, or attack."
    const val FINAL = "Final round!"

    // ----- The bombing at the end of a round -----

    const val YOU_WILL_BOMB = "You will bomb"
    fun isBombing(ref: String) = listOf("${cap(v(ref))} is bombing", "${cap(v(ref))} is nuking")
    const val ALSO_BOMBING = "They are also bombing"
    val COUNTDOWN = listOf("3", "2", "1")

    fun destroyCity(city: String) = listOf(
        "$city was blown to smithereens.", "$city has been vaporized.", "The blast wiped $city off the map.",
        "$city has been obliterated.", "$city has been reduced to radioactive rubble.", "$city is in ruins.",
    )

    /** After a list of cities: "Paris and Lyon" ... */
    val DESTROY_CITIES = listOf(
        "have been blown to smithereens.", "have been turned to rubble.", "have been vaporized.",
        "have been obliterated by nukes.", "have been reduced to ashes.", "are in smoldering ruins.",
    )

    fun destroyShield(city: String) = listOf(
        "The shield on $city was blown up.", "The shield around $city has been shattered.",
        "The shield on $city has been obliterated.", "The forcefield on $city has been destroyed.",
        "The shield over $city has been crushed.", "The shield on $city has been broken.",
    )

    /** Around a list of cities: "The shields around" ... "have been shattered." */
    val DESTROY_SHIELDS = listOf(
        "The shields around" to "have been shattered.", "The shields on" to "have been decimated.",
        "The shields over" to "have been crushed.", "The forcefields on" to "have been dismantled.",
    )

    /** The countries knocked out this round (1 to 3, in [World.ordered] order). */
    fun countriesDestroyed(refs: List<String>): List<String> {
        val n = refs.map(::v)
        val list = when (n.size) {
            1 -> cap(n[0])
            2 -> "${cap(n[0])} and ${n[1]}"
            else -> "${cap(n[0])}, ${n[1]} and ${n[2]}"
        }
        return if (n.size == 1) listOf(
            "$list has been destroyed and will no longer be in the war.", "The nation of ${n[0]} has been eliminated.",
            "$list has been removed from the war.", "$list has been knocked out.", "$list has been obliterated.",
        ) else listOf(
            "$list have been destroyed and will no longer be in the war.",
            "$list are no longer in the war after being nuked.", "$list have been knocked out.",
        )
    }

    // ----- The end of a round: scores and money -----

    fun roundComplete(round: Int) = "Round $round of 5 complete."
    const val SCORES = "Here's the scores."
    const val SCORE_PARTS = "Your score is made up of different parts."
    fun bankPoints(points: Int) = "This round, you got $points points for having"
    const val IN_THE_BANK = "in the bank."
    fun envPoints(n: Int) = "Your environmental contributions got you $n ${pts(n)}."
    private fun yourCities(cityPoints: Int) = if (cityPoints == 5) "last city" else "${cityPoints / 5} cities"
    fun researchAndCities(research: Int, cityPoints: Int) =
        "You got $research points for research and $cityPoints for your ${yourCities(cityPoints)}."
    fun shieldsAndCities(shields: Int, cityPoints: Int) =
        "You got $shields ${pts(shields)} for your ${if (shields == 1) "shield" else "shields"} and $cityPoints " +
            "points for your ${yourCities(cityPoints)}."
    fun shieldsResearchAndCities(shields: Int, research: Int, cityPoints: Int) =
        "You got $shields ${pts(shields)} for your shields and $research points for your research and $cityPoints " +
            "points for your ${yourCities(cityPoints)}."
    fun citiesOnly(cityPoints: Int) = "You got $cityPoints points for your ${yourCities(cityPoints)}."
    fun citiesNoUpgrades(n: Int) =
        "You have $n ${if (n == 1) "city" else "cities"}, with no ${if (n == 1) "shield" else "shields"} or research."
    fun citiesUpgraded(n: Int) = "You have $n upgraded ${if (n == 1) "city" else "cities"}."
    const val NO_EARNINGS = "You didn't earn any money this round."
    const val YOU_LOST = "You lost"
    const val THIS_ROUND = "this round."
    const val YOU_RECEIVED = "You received"
    const val IN_EARNINGS = "in earnings this round."
    const val YOU_HAVE = "You have"
    const val TO_SPEND = "to spend."
    const val LEFT = "left."
    const val LEFT_IN_BANK = "left in the bank."
    const val NOTHING = "nothing"

    fun money(amount: Long) = World.formatMillions(World.sayable(amount))
    fun points(n: Int) = n.coerceIn(0, World.POINTS_MAX).let { "$it ${pts(it)}." }

    /** Who a score line is about: "you" or a country. */
    fun subject(ref: String?) = if (ref == null) "you" else v(ref)

    /** "You are in second with" / "France are in last with". */
    fun placing(ref: String?, place: String) = "${cap(subject(ref))} are in $place with"
    fun tiePlacing(place: String) = if (place == "last") "are last with" else "are $place equal with"
    fun endPlacing(ref: String?, place: String) = "${cap(subject(ref))} came $place with"
    fun endTiePlacing(place: String) = when (place) {
        "last" -> "came last with"
        "first" -> "came joint first with"
        else -> "came $place equal with"
    }

    // ----- Game over -----

    const val GAME_OVER = "Game Over."
    const val EVERY_COUNTRY = "Every country has been destroyed!"
    fun victory(ref: String) = "You have successfully brought ${v(ref)} to victory!"
    const val LIGHTNING = "A lightning bolt is flying through the skies."
    const val WAR_STOPPED = "The war was stopped due to the environment being so heavily damaged."

    val EVERYONE_DESTROYED = listOf(
        "Every country has been blown to smithereens.", "Every country has been nuked to kingdom come.",
        "Every country has had their cities reduced to rubble.", "Every country has been devastated beyond recognition.",
        "Every country has been wiped off the face of the earth.", "Every country has been annihilated.",
        "Every country has been left in ruins.", "Every country has been erased from the map of the world.",
    )

    val WE_LOSE = listOf(
        "Uh-oh! All your cities are destroyed, so you're out of the war.",
        "Sorry, your cities got destroyed, and you can't fight anymore.",
        "Your cities are gone, so you're out of the fight, my friend.",
        "Looks like you're out of the war since all your cities are destroyed.",
        "Bad news, all your cities have been destroyed, and you can't fight anymore.",
        "Unfortunately, your cities have been destroyed, so you're out of the fight.",
        "All your cities are destroyed, so you're out of the war.",
        "Your cities have been destroyed, and you're out of the battle.",
        "Your cities have been destroyed, so you're out of the battlefield.",
        "All your cities have been destroyed, and you're out of the war.",
    )

    // ----- Lists said a name at a time -----

    /** How a list ends: "and Moscow." (the sentence ends), "and Moscow" (it carries on), "and you," (", are ..."). */
    enum class Last { END, ON, COMMA }

    /**
     * A list of names as pieces: "Paris," "Lyon" "and Moscow." The first is capitalised (a list of countries can start
     * a sentence: "The UK," ...). A single name is "Paris." or "Paris".
     */
    fun items(names: List<String>, last: Last): List<String> {
        if (names.size == 1) return listOf(cap(names[0]) + if (last == Last.END) "." else "")
        return names.mapIndexed { i, n ->
            val name = if (i == 0) cap(n) else n
            when (i) {
                names.size - 1 -> "and $name" + when (last) {
                    Last.END -> "."
                    Last.ON -> ""
                    Last.COMMA -> ","
                }
                names.size - 2 -> name
                else -> "$name,"
            }
        }
    }

    // ----- Everything Don says -----

    fun all(): List<Phrase> {
        val out = linkedMapOf<String, Phrase>()
        fun add(text: String) {
            out.getOrPut(text) { Phrase(text, speak(text)) }
        }
        fun part(text: String, before: String, after: String) {
            out.getOrPut(text) { Phrase(text, speak(text), speak(before), speak(after)) }
        }
        fun addAll(texts: Iterable<String>) = texts.forEach(::add)
        val refs = World.REFS
        val cities = World.CITIES
        val bombsRange = 1..World.BOMBS_MAX
        fun subsets(min: Int, max: Int) = (1 until (1 shl refs.size)).map { m -> refs.filterIndexed { i, _ -> m and (1 shl i) != 0 } }
            .filter { it.size in min..max }

        addAll(listOf(WELCOME, PLAY_AS, WELCOME_BACK, WHICH_COUNTRY, CHOOSE_FROM, MEET_FIRST, TECH_START, TECH,
            TECH_SPEND, TECH_DONE, ENV_START, ENV, ENV_BACK, ENV_EXTRA, SPENT_ALL, DONE_ALL, EVERY_CITY, ALL_CITIES,
            COSTS, SHIELD_OR_RESEARCH, SHIELD_OR_RESEARCH_AGAIN, REMOVE_ANY, ADD_ANY, ADD_ANY_LONG, SANCTION_ANY,
            REMOVE_FROM_ONE, REMOVE_MORE, SANCTIONED_ALL, SANCTION_ANOTHER, SANCTION_OWN, UNSANCTION_OWN, SANCTIONED_YOU,
            DIRECTED_ONE, DIRECTED_TWO, USE_IT, USE_ANOTHER, USE_ANOTHER_AGAIN, USE_ONE, USE_A_BOMB, USE_A_BOMB_LONG,
            BUY_ANY, BUY_NUCLEAR, BOMB_COST, HOW_MANY, HOW_MANY_SAY, DIDNT_CATCH, ONE_PER_CITY, OWN_COUNTRY,
            CAN_YOU_REPEAT, ANSWER, FINAL_MOVE, FINAL, SCORES, SCORE_PARTS, NO_EARNINGS, GAME_OVER, EVERY_COUNTRY,
            LIGHTNING, WAR_STOPPED))
        addAll(PICK_UP + NO_CALLS + INSTA_HANG_UP + TRIPLE_SANCTION + EVERYONE_DESTROYED + WE_LOSE)
        for (p in (0..World.PERCENT_MAX step 5)) add(envAt(p))
        for (r in 1..4) add(roundComplete(r))
        for (r in 2..4) add(callsDone(r))

        for (ref in refs) {
            addAll(listOf(leaderOf(ref), meet(ref), meetFinally(ref), meetLeader(ref), sanctionOne(ref), sanctioned(ref),
                alreadySanctioned(ref), cantSanction(ref), removeOne(ref), youRemoved(ref), noSanctionsOn(ref),
                notToUnsanction(ref), removedOnYou(ref), wantAttack(ref), wouldAttack(ref), cantBomb(ref), allSet(ref),
                noCitiesLeft(ref), notEnoughForAll(ref), sureBomb(ref), sureBombAll(ref), definitely(ref),
                callIncoming(ref), callImportant(ref), callAgain(ref), victory(ref)))
            addAll(longCall(ref) + onHold(ref) + enemyAngry(ref) + singleNoTalk(ref))
            for (lead in isBombing(ref)) part(lead, "", "London and Cardiff.")
            val own = World.land(ref).cities
            for (order in permutations(own)) add(threeCities(order[0], order[1], order[2]))
            for (n in 2..3) for (sub in combinations(own, n)) {
                add(attackCities(sub))
                add(whichCity(sub))
                if (n == 3) add(attackAll(sub))
            }
        }
        for (pair in subsets(2, 2)) addAll(twoNoTalk(pair[0], pair[1]))
        for (sub in subsets(1, 3)) addAll(countriesDestroyed(sub))
        for (sub in subsets(2, 4)) {
            addAll(listOf(sanctionList(sub), removeList(sub), removeListAgain(sub), attackCountries(sub),
                whichCountryAttack(sub)))
        }

        for (city in cities) {
            addAll(listOf(wantUpgrade(city), anyUpgradesOn(city), upgradesTo(city), anyUpgradesTo(city), howAbout(city),
                upgradesOn(city), researchFor(city), researchProductivity(city), shieldFor(city), productivity(city),
                protectedNow(city), alreadyShield(city), noMoneyShield(city), alreadyResearch(city), wouldAttackCity(city),
                wantAttackCity(city), oneLeft(city), launched(city), alreadyDestroyed(city)))
            addAll(bombSelf(city) + destroyCity(city) + destroyShield(city))
            // In lists: "You will bomb Paris, Lyon and Moscow." / "Paris and Lyon have been vaporized."
            part(picked(city), "You will bomb", "")
            part("$city,", "You will bomb", "Lyon and Moscow.")
            part(city, "You will bomb Paris,", "and Moscow.")
            part("and $city.", "You will bomb Paris, Lyon", "")
            part("and $city", "Paris, Lyon", "have been vaporized.")
        }
        for (tail in DESTROY_CITIES) part(tail, "Paris, Lyon and Moscow", "")
        for ((lead, tail) in DESTROY_SHIELDS) {
            part(lead, "", "Paris and Lyon $tail")
            part(tail, "$lead Paris and Lyon", "")
        }
        part(YOU_WILL_BOMB, "", "Paris, Lyon and Moscow.")
        part(ALSO_BOMBING, "", "Paris and Lyon.")
        COUNTDOWN.forEach { out[it] = Phrase(it, "${listOf("Three", "Two", "One")[COUNTDOWN.indexOf(it)]}.") }

        for (n in bombsRange) {
            addAll(listOf(bombsLeft(n), haveBombs(n), buyMore(n), buyMoreAgain(n), keepForLater(n), reserve(n)))
            part(nowHave(n), "", "4 million left in the bank.")
        }
        for (n in 0..World.BOMBS_MAX) add(affordUpTo(n))
        for (n in 3..World.BOMBS_MAX) add(directedAll(n))
        add(dontUse(1))
        add(dontUse(2))

        // Scores
        for (n in 1..5) add(envPoints(n))
        for (c in listOf(5, 10, 15)) {
            add(citiesOnly(c))
            for (r in listOf(2, 4, 6)) add(researchAndCities(r, c))
            for (s in 1..3) {
                add(shieldsAndCities(s, c))
                for (r in listOf(2, 4, 6)) add(shieldsResearchAndCities(s, r, c))
            }
        }
        for (n in 1..3) {
            add(citiesNoUpgrades(n))
            add(citiesUpgraded(n))
        }
        for (p in listOf(2, 4)) part(bankPoints(p), "", "12 million in the bank.")
        val places = listOf("first", "second", "third", "fourth", "fifth", "last")
        for (who in listOf<String?>(null) + refs) for (place in places) {
            part(placing(who, place), "", "12 points.")
            part(endPlacing(who, place), "", "12 points.")
        }
        for (place in places) {
            // (a comma before them: Don runs "you came" together, with no gap to cut in)
            part(tiePlacing(place), "France and you,", "12 points.")
            part(endTiePlacing(place), "France and you,", "12 points.")
        }
        for (n in 0..World.POINTS_MAX) part(points(n), "You are in second with", "")
        // Ties: "France, the UK and you, are second equal with"
        for (who in listOf<String?>(null) + refs) {
            val name = subject(who)
            part("${cap(name)},", "", "Russia and you, are second equal with 12 points.")
            part(cap(name), "", "and you, are second equal with 12 points.")
            part("$name,", "France,", "Russia and you, are second equal with 12 points.")
            part(name, "France,", "and you, are second equal with 12 points.")
            part("and $name,", "France, Russia", "are second equal with 12 points.")
            part("and $name", "France, Russia", "came second equal with 12 points.")
        }

        // Money: "You have 12 million left."
        for (lead in listOf(YOU_HAVE, YOU_LOST, YOU_RECEIVED)) part(lead, "", "12 million left.")
        for (amount in World.sayableAmounts()) part(World.formatMillions(amount), "You have", "left.")
        part(NOTHING, "You now have 3 bombs and", "left in the bank.")
        for (tail in listOf(LEFT, TO_SPEND, THIS_ROUND, IN_EARNINGS, IN_THE_BANK, LEFT_IN_BANK)) {
            part(tail, "You have 12 million", "")
        }
        return out.values.toList()
    }

    private fun <T> permutations(items: List<T>): List<List<T>> =
        if (items.size <= 1) listOf(items)
        else items.flatMap { x -> permutations(items - x).map { listOf(x) + it } }

    private fun <T> combinations(items: List<T>, n: Int): List<List<T>> =
        if (n == 0) listOf(emptyList())
        else if (items.size < n) emptyList()
        else combinations(items.drop(1), n - 1).map { listOf(items[0]) + it } + combinations(items.drop(1), n)
}
