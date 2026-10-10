package com.epicaudiogames.app

import com.epicaudiogames.engine.Line

/**
 * Where the voice is as a help page (or the welcome) is read aloud: the [paragraph] of HelpPage.text being read, and how
 * many of its characters have been said ([chars]), for the topic page's highlight ([currentWord] marks the word). Plain
 * Kotlin, tested on the JVM (HelpHighlightTest). iOS: EpicAppCore's HelpHighlight.swift.
 */
data class HelpHighlight(val paragraph: Int, val chars: Int) {
    companion object {
        /**
         * In [page], with its clip number [clip] playing [seconds] in (AudioPlayer.position: the clip among the page's
         * clips, and media seconds): where the voice is. Null in a clip with no paragraph (an earcon) or before a
         * clip's first line.
         */
        fun of(page: HelpPage, clip: Int, seconds: Double): HelpHighlight? {
            val paragraph = page.clipParagraph.getOrNull(clip)?.takeIf { it >= 0 && it < page.text.size } ?: return null
            val lines = page.clipLines.getOrNull(clip) ?: return null
            val (line, chars) = at(lines, seconds) ?: return null
            // A clip of more than one line reads them as one paragraph, a space between each.
            val before = lines.take(line).sumOf { it.text.length + 1 }
            return HelpHighlight(paragraph, (before + chars).coerceAtMost(page.text[paragraph].length))
        }

        /**
         * In a clip's [lines], [seconds] in: the line being said (the last to have begun) and how many of its
         * characters have been said. With the line's word times ("w", each from the line's start), that's up to the end
         * of the word being said; without them the line's time is spread evenly over its characters, as the game's
         * transcript does (GameController.follow). Null before the first line begins.
         */
        fun at(lines: List<Line>, seconds: Double): Pair<Int, Int>? {
            val i = lines.indexOfLast { it.at <= seconds }
            if (i < 0) return null
            val line = lines[i]
            val t = seconds - line.at
            val words = line.words
            val spans = wordSpans(line.text)
            if (words != null && words.isNotEmpty() && spans.isNotEmpty()) {
                // The word being said: the last to have started (the first, before any has). Word times beyond the
                // line's words go with its last word.
                val k = words.indexOfLast { it <= t }.coerceIn(0, spans.lastIndex)
                return i to spans[k].last + 1
            }
            val progress = if (line.len > 0) (t / line.len).coerceIn(0.0, 1.0) else 1.0
            return i to (line.text.length * progress).toInt()
        }

        /** Where each word of [text] is (its characters' indices): words split at whitespace, as tools/content.py's. */
        private fun wordSpans(text: String): List<IntRange> {
            val spans = mutableListOf<IntRange>()
            var start = -1
            for ((j, ch) in text.withIndex()) {
                if (ch.isWhitespace()) {
                    if (start >= 0) spans += start until j
                    start = -1
                } else if (start < 0) {
                    start = j
                }
            }
            if (start >= 0) spans += start until text.length
            return spans
        }
    }
}
