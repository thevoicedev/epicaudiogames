package com.epicaudiogames.engine

/**
 * Reading what the player said. The digit and symbol readers are the Alexa skills' own (Signal Decoders'
 * digitsSaid, sequenceSaid and lettersSaid), so the games accept the same answers.
 */
object Text {
    private val NOT_WORD = Regex("[^a-z0-9']+")

    /** Lower case, curly apostrophes made straight, everything but letters, digits and apostrophes made spaces. */
    fun normalise(s: String): String =
        s.lowercase().replace('’', '\'').replace('‘', '\'').replace('`', '\'').replace(NOT_WORD, " ").trim()

    /** The length of the phrase if the (normalised) text says it as whole words (an exact phrase: is it), else -1. */
    fun phraseLength(text: String, phrase: Phrase): Int = when {
        phrase.exact -> if (text == phrase.text) phrase.text.length else -1
        " $text ".contains(" ${phrase.text} ") -> phrase.text.length
        else -> -1
    }

    /** The longest of the phrases the text says, or null. */
    fun longest(text: String, phrases: List<Phrase>): Phrase? =
        phrases.filter { phraseLength(text, it) >= 0 }.maxByOrNull { it.text.length }

    /** Whether the phrase is negated: "don't", "dont", "not" or "never" up to three words before it. */
    fun negated(text: String, phrase: String): Boolean =
        Regex("""\b(don't|dont|not|never)( [a-z0-9']+){0,3} ${Regex.escape(phrase)}( |$)""").containsMatchIn(text)

    private val ONES = mapOf(
        "zero" to 0, "oh" to 0, "one" to 1, "won" to 1, "two" to 2, "to" to 2, "too" to 2, "three" to 3, "four" to 4,
        "for" to 4, "fore" to 4, "five" to 5, "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9, "ten" to 10,
        "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14, "fifteen" to 15, "sixteen" to 16,
        "seventeen" to 17, "eighteen" to 18, "nineteen" to 19,
    )
    private val TENS = mapOf(
        "twenty" to 20, "thirty" to 30, "forty" to 40, "fourty" to 40, "fifty" to 50, "sixty" to 60, "seventy" to 70,
        "eighty" to 80, "ninety" to 90,
    )

    private fun isNumber(t: String) = t.isNotEmpty() && t.all { it in '0'..'9' }

    /**
     * The digits said, in order: "four two two one one", "4 2 2 1 1", "four twenty-two eleven" and
     * "forty two thousand two hundred and eleven" all give "42211".
     */
    fun digits(said: String): String {
        val tokens = normalise(said.replace('-', ' ')).split(' ').filter { it.isNotEmpty() }
        if ("hundred" in tokens || "thousand" in tokens) {
            var total = 0L
            var current = 0L
            var any = false
            for (t in tokens) {
                when {
                    isNumber(t) -> { current += t.toLongOrNull() ?: 0L; any = true }
                    t in ONES -> { current += ONES.getValue(t); any = true }
                    t in TENS -> { current += TENS.getValue(t); any = true }
                    t == "hundred" -> current = (if (current == 0L) 1L else current) * 100
                    t == "thousand" -> { total += (if (current == 0L) 1L else current) * 1000; current = 0 }
                }
            }
            return if (any) (total + current).toString() else ""
        }
        val out = StringBuilder()
        var i = 0
        while (i < tokens.size) {
            val t = tokens[i]
            when {
                isNumber(t) -> out.append(t)
                t in TENS -> {
                    val ones = tokens.getOrNull(i + 1)?.let { ONES[it] }
                    if (ones != null && ones in 1..9) {
                        out.append(TENS.getValue(t) + ones)
                        i++
                    } else {
                        out.append(TENS.getValue(t))
                    }
                }
                t in ONES -> out.append(ONES.getValue(t))
            }
            i++
        }
        return out.toString()
    }

    /**
     * The symbols said, in order, with a table such as { "l": ["left", "lift"], "r": ["right", "write"] }:
     * "left right right left" gives "lrrl". With [spelled], a word made only of one-letter symbols ("ac") counts
     * letter by letter.
     */
    fun symbols(said: String, table: Map<String, List<String>>, spelled: Boolean = false): String {
        val out = StringBuilder()
        for (w in normalise(said).split(' ')) {
            if (w.isEmpty()) continue
            val symbol = table.entries.firstOrNull { w in it.value }?.key
            if (symbol != null) {
                out.append(symbol)
            } else if (spelled && w.length >= 2 && w.all { table.containsKey(it.toString()) }) {
                out.append(w)
            }
        }
        return out.toString()
    }
}
