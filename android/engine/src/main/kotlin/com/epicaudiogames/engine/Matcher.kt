package com.epicaudiogames.engine

/**
 * Which answer of a question the player gave (docs/MAP_FORMAT.md, "Matching what the player says"): the skill's
 * yes/no rule for mixed answers first; then rank by rank, highest first, exact checks (seq, digits, re) in order and
 * then phrases (yes, no, words, repeat); then the map's own repeat words; then "any".
 */
object Matcher {
    /**
     * [index]: the answer taken (null: none); [repeat]: the map's own "repeat" words; [how]: for logs and tests;
     * [aside]: none taken, but the answer was heard: it isn't sure, or a phrase in it doesn't count (negated).
     */
    data class Result(val index: Int?, val repeat: Boolean, val how: String, val aside: Boolean = false)

    private class Hit(val index: Int, val phrase: Phrase, val start: Int, val negated: Boolean) {
        val end get() = start + phrase.text.length
        fun overlaps(o: Hit) = start < o.end && o.start < end
    }

    fun match(map: GameMap, ask: Ask, vars: Map<String, Any>, said: String): Result {
        val text = Text.normalise(said)
        if (text.isEmpty()) return Result(null, false, "nothing")
        val live = ask.answers.withIndex().filter { (_, a) -> a.whenCond?.test(vars) ?: true }
        mixed(map, text)?.let { yes ->
            val answer = live.firstOrNull { (_, a) -> if (yes) a.match is Match.Yes else a.match is Match.No }
            if (answer != null) return Result(answer.index, false, "mixed: ${if (yes) "yes" else "no"}")
            if (live.any { (_, a) -> a.match is Match.Yes || a.match is Match.No }) return Result(null, false, "mixed, no such answer")
        }
        var aside = Text.unsure(text)
        for (rank in live.map { it.value.rank }.distinct().sortedDescending()) {
            val group = live.filter { it.value.rank == rank }
            for ((i, a) in group) {
                if (exact(map, a.match, text)) return Result(i, false, a.match::class.simpleName!!.lowercase())
            }
            phrases(map, ask, group, text) { aside = true }?.let { return it }
        }
        if (ask.answers.none { it.match == Match.Repeat }) {
            Text.longest(text, map.words.repeat)?.let { return Result(null, true, "repeat \"${it.text}\"") }
        }
        live.firstOrNull { it.value.match == Match.AnyText }?.let { return Result(it.index, false, "any") }
        return Result(null, false, "not understood", aside)
    }

    /**
     * An answer of two or more words that are all yes words, no words or fillers: true if its last yes or no word is a
     * yes, false if a no ("no yes" is a yes, "yeah no" a no). Null otherwise.
     */
    fun mixed(map: GameMap, text: String): Boolean? {
        val m = map.words.mixed ?: return null
        var t = " $text "
        for (p in (m.yes + m.no).filter { ' ' in it }) t = t.replace(" $p ", if (p in m.yes) "  " else "  ")
        val words = t.trim().split(' ').filter { it.isNotEmpty() }
        if (words.size < 2) return null
        fun isYes(w: String) = w == "" || w in m.yes
        fun isNo(w: String) = w == "" || w in m.no
        if (!words.all { isYes(it) || isNo(it) || it in m.filler }) return null
        val last = words.lastOrNull { isYes(it) || isNo(it) } ?: return null
        return isYes(last)
    }

    private fun exact(map: GameMap, m: Match, text: String): Boolean = when (m) {
        is Match.Seq -> {
            val table = map.symbols[m.table] ?: throw MapException("no symbol table ${m.table}")
            val got = Text.symbols(text, table, m.spelled)
            when {
                m.least != null -> got.length >= m.least
                m.exact -> got == m.seq
                else -> got.contains(m.seq)
            }
        }
        is Match.Digits -> {
            // The map's repeat words aren't numbers: "one more time" is a repeat, not a 1.
            val got = Text.digits(withoutRepeats(map, text))
            when {
                m.least != null -> got.length >= m.least
                m.exact -> got == m.digits
                else -> got.contains(m.digits)
            }
        }
        is Match.Re -> m.regex.containsMatchIn(text)
        else -> false
    }

    /** The (normalised) text without the map's repeat words in it, in their order (an exact one: all of it, or none). */
    private fun withoutRepeats(map: GameMap, text: String): String {
        var t = " $text "
        for (p in map.words.repeat) {
            if (p.exact) {
                if (text == p.text) return ""
            } else {
                while (t.contains(" ${p.text} ")) t = t.replace(" ${p.text} ", " ")
            }
        }
        return t.trim()
    }

    /**
     * The phrase answer given in this rank, or null. The longest phrase wins over the phrases inside it ("no
     * rehearsal" over "rehearsal"); two answers that would do different things, said apart ("follow or hide"),
     * are unclear, and the next rank is tried. A negated phrase ("don't follow", "of course not") counts for its
     * "opposite", or else not at all. An answer that isn't sure ("I'm not sure", "I don't know") counts only for a
     * phrase that says so itself, so it is never a yes or a no. [setAside] hears of a phrase said that doesn't count.
     */
    private fun phrases(
        map: GameMap, ask: Ask, group: List<IndexedValue<Answer>>, text: String, setAside: () -> Unit,
    ): Result? {
        val unsure = Text.unsure(text)
        val hits = mutableListOf<Hit>()
        for ((i, a) in group) {
            val phrases = when (val m = a.match) {
                is Match.Yes -> map.words.yes + m.extra
                is Match.No -> map.words.no + m.extra
                is Match.Words -> m.phrases
                Match.Repeat -> map.words.repeat
                else -> continue
            }
            val opposite = a.opposite
            val said = phrases.filter { Text.phraseLength(text, it) >= 0 }
            val counted = said.filter {
                (!unsure || Text.unsure(it.text)) && (opposite != null || it.exact || !Text.negated(text, it.text))
            }
            val phrase = counted.maxByOrNull { it.text.length }
            if (phrase == null) {
                if (said.isNotEmpty()) setAside()
                continue
            }
            val negated = opposite != null && !phrase.exact && Text.negated(text, phrase.text)
            hits += Hit(if (negated) opposite!! else i, phrase, if (phrase.exact) 0 else " $text ".indexOf(" ${phrase.text} "), negated)
        }
        if (hits.isEmpty()) return null
        val winner = hits.maxBy { it.phrase.text.length }
        fun action(h: Hit) = ask.answers[h.index].let { Pair(it.go, it.set) }
        val rival = hits.firstOrNull { it !== winner && action(it) != action(winner) &&
            (!it.overlaps(winner) || it.phrase.text.length == winner.phrase.text.length) }
        if (rival != null) return null
        return Result(winner.index, false, (if (winner.negated) "not " else "") + "\"${winner.phrase.text}\"")
    }
}
