package com.epicaudiogames.engine

/**
 * Which answer of a question the player gave (docs/MAP_FORMAT.md, "Matching what the player says"): the skill's
 * yes/no rule for mixed answers first; then rank by rank, highest first, exact checks (seq, digits, re) in order and
 * then phrases (yes, no, words, repeat); then the map's own repeat words; then "any".
 */
object Matcher {
    /** [index]: the answer taken (null: none); [repeat]: the map's own "repeat" words; [how]: for logs and tests. */
    data class Result(val index: Int?, val repeat: Boolean, val how: String)

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
        for (rank in live.map { it.value.rank }.distinct().sortedDescending()) {
            val group = live.filter { it.value.rank == rank }
            for ((i, a) in group) {
                if (exact(map, a.match, text)) return Result(i, false, a.match::class.simpleName!!.lowercase())
            }
            phrases(map, ask, group, text)?.let { return it }
        }
        if (ask.answers.none { it.match == Match.Repeat }) {
            Text.longest(text, map.words.repeat)?.let { return Result(null, true, "repeat \"${it.text}\"") }
        }
        live.firstOrNull { it.value.match == Match.AnyText }?.let { return Result(it.index, false, "any") }
        return Result(null, false, "not understood")
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
            val got = Text.digits(text)
            when {
                m.least != null -> got.length >= m.least
                m.exact -> got == m.digits
                else -> got.contains(m.digits)
            }
        }
        is Match.Re -> m.regex.containsMatchIn(text)
        else -> false
    }

    /**
     * The phrase answer given in this rank, or null. The longest phrase wins over the phrases inside it ("no
     * rehearsal" over "rehearsal"); two answers that would do different things, said apart ("follow or hide"),
     * are unclear, and the next rank is tried. A negated phrase ("don't follow") counts for its "opposite".
     */
    private fun phrases(map: GameMap, ask: Ask, group: List<IndexedValue<Answer>>, text: String): Result? {
        val hits = mutableListOf<Hit>()
        for ((i, a) in group) {
            val phrases = when (val m = a.match) {
                is Match.Yes -> map.words.yes + m.extra
                is Match.No -> map.words.no + m.extra
                is Match.Words -> m.phrases
                Match.Repeat -> map.words.repeat
                else -> continue
            }
            val phrase = Text.longest(text, phrases) ?: continue
            val opposite = a.opposite
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
