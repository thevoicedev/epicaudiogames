package com.epicaudiogames.app

/**
 * A transcript line cut around the word being spoken: what's been said [before] it, the [word] itself (highlighted),
 * and what's still to come [after] it (shown as it is, or hidden but keeping its place). Together they're the line.
 */
data class CurrentWord(val before: String, val word: String, val after: String)

/**
 * Where the voice is in [text], [saidChars] characters in (GameController.activeChars): the word it's saying, the one
 * the next character to say is in. So a line just begun has its first word and a line said to its end its last;
 * with the next character a space, it's the word just said. Words are split at whitespace, their punctuation with
 * them. iOS: EpicAppCore's Transcript.swift, currentWord.
 */
fun currentWord(text: String, saidChars: Int): CurrentWord {
    var end = saidChars.coerceIn(0, text.length)
    // Inside a word: on to its end.
    while (end < text.length && !text[end].isWhitespace()) end++
    // Back over any spaces, to the end of the word before them.
    while (end > 0 && text[end - 1].isWhitespace()) end--
    if (end == 0) {
        // Only spaces so far: the first word, wherever it starts.
        var start = 0
        while (start < text.length && text[start].isWhitespace()) start++
        var stop = start
        while (stop < text.length && !text[stop].isWhitespace()) stop++
        return CurrentWord(text.substring(0, start), text.substring(start, stop), text.substring(stop))
    }
    var start = end
    while (start > 0 && !text[start - 1].isWhitespace()) start--
    return CurrentWord(text.substring(0, start), text.substring(start, end), text.substring(end))
}
