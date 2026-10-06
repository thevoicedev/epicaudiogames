package com.epicaudiogames.engine.nuclear

/**
 * A country as the skill's COUNTRY_MAP has it: [voice] is how its name is said ("the UK"), [leader] the leader's name
 * as shown and [leaderSays] as Don says it, [who] the leader's speaker key in the transcript, [cities] in the skill's
 * order.
 */
data class Land(
    val ref: String,
    val voice: String,
    val leader: String,
    val leaderSays: String,
    val who: String,
    val cities: List<String>,
)

/** The five countries, the prices and the money as Alexa said it (Constants.js: COUNTRY_MAP, NW_ROUNDS). */
object World {
    val LANDS = listOf(
        Land("France", "France", "Alex Craimant", "Alex Cremonne", "FR", listOf("Paris", "Marseille", "Lyon")),
        Land("USA", "the USA", "Iona Butt", "Iona Butt", "US", listOf("New York", "Los Angeles", "Houston")),
        Land("UK", "the UK", "Roger Shufflebottom", "Roger Shufflebottom", "UK", listOf("London", "Edinburgh", "Cardiff")),
        Land("China", "China", "Hoo Flung Dung", "Hoo Flung Dung", "CN", listOf("Shanghai", "Beijing", "Wuhan")),
        Land("Russia", "Russia", "Yuri Poo-tin", "Yuri Poo-tin", "RU", listOf("Moscow", "St Petersburg", "Sochi")),
    )
    val REFS = LANDS.map { it.ref }
    val CITIES = LANDS.flatMap { it.cities }

    fun land(ref: String): Land = LANDS.first { it.ref == ref }
    fun landOf(city: String): Land = LANDS.first { city in it.cities }
    fun voice(ref: String): String = land(ref).voice

    /** Countries in the skill's COUNTRY_MAP order, the order lists of them are said in. */
    fun ordered(refs: Collection<String>): List<String> = REFS.filter { it in refs }

    /** A country's cities in that order. */
    fun orderedCities(names: Collection<String>): List<String> = CITIES.filter { it in names }

    const val RESEARCH = 2_000_000L
    const val SHIELD = 3_000_000L
    const val ENVIRONMENT = 1_000_000L
    const val TECH = 5_000_000L
    const val BOMB = 3_000_000L

    /** Money with a clip of its own: every 100,000 up to 40 million, then every half million up to 150 million. */
    const val MONEY_FINE = 40_000_000L
    const val MONEY_MAX = 150_000_000L

    /** The amount said for this much money: the nearest with a clip. */
    fun sayable(money: Long): Long {
        val m = money.coerceIn(0, MONEY_MAX)
        val tenth = (m + 50_000) / 100_000 * 100_000
        return if (tenth <= MONEY_FINE || tenth % 500_000 == 0L) tenth else (m + 250_000) / 500_000 * 500_000
    }

    /** All the amounts [sayable] gives. */
    fun sayableAmounts(): List<Long> =
        (0..MONEY_FINE step 100_000).toList() + ((MONEY_FINE + 500_000)..MONEY_MAX step 500_000).toList()

    /**
     * The skill's formatMillions: "12 million", "12 and a half million", "12.4 million", "half a million"; under half a
     * million, the number itself ("300,000").
     */
    fun formatMillions(num: Long): String {
        if (num < 500_000) return if (num == 0L) "0" else String.format(java.util.Locale.US, "%,d", num)
        val millions = num / 1_000_000
        val remaining = num % 1_000_000
        if (millions == 0L && remaining == 500_000L) return "half a million"
        return when {
            remaining == 500_000L -> "$millions and a half million"
            remaining > 0 -> "$millions.${remaining / 100_000} million"
            else -> "$millions million"
        }
    }

    /** "first" to "fifth". */
    fun ordinal(n: Int): String = listOf("first", "second", "third", "fourth", "fifth").getOrElse(n - 1) { "${n}th" }

    /** Points with a clip of their own (a game's score stays well under this). */
    const val POINTS_MAX = 200

    /** Bombs with lines of their own. */
    const val BOMBS_MAX = 25

    /** The environment said in steps of 5 percent, up to this. */
    const val PERCENT_MAX = 300
}
