// HelpHighlight.kt: where the voice is as a help page (or the welcome) is read aloud.

/**
 * Where the voice is as a help page (or the welcome) is read aloud: the [paragraph] of HelpPage.text being read, and
 * how many of its characters have been said ([chars], in UTF-16 units as Kotlin's String.length counts them), for the
 * topic page's highlight (Transcript.currentWord marks the word). Tested with the real welcome (HelpHighlightTests).
 * Android's HelpHighlight.kt.
 */
public struct HelpHighlight: Equatable, Sendable {
    public let paragraph: Int
    public let chars: Int

    public init(paragraph: Int, chars: Int) {
        self.paragraph = paragraph
        self.chars = chars
    }

    /**
     * In [page], with its clip number [clip] playing [seconds] in (TurnPlayer's position: the clip among the page's
     * clips, and the clip's own seconds, whatever the voice speed): where the voice is. Nil in a clip with no
     * paragraph (an earcon) or before a clip's first line.
     */
    public static func of(_ page: HelpPage, clip: Int, seconds: Double) -> HelpHighlight? {
        guard page.clipParagraph.indices.contains(clip) else { return nil }
        let paragraph = page.clipParagraph[clip]
        guard paragraph >= 0 && paragraph < page.text.count else { return nil }
        let clips = page.clipLines
        guard clips.indices.contains(clip), let (line, chars) = at(clips[clip], seconds: seconds) else { return nil }
        // A clip of more than one line reads them as one paragraph, a space between each.
        let before = clips[clip].prefix(line).reduce(0) { $0 + $1.text.utf16.count + 1 }
        return HelpHighlight(paragraph: paragraph, chars: min(before + chars, page.text[paragraph].utf16.count))
    }

    /**
     * In a clip's [lines], [seconds] in: the line being said (the last to have begun) and how many of its characters
     * have been said. With the line's word times ("w", each from the line's start), that's up to the end of the word
     * being said; without them the line's time is spread evenly over its characters, as the game's transcript does
     * (Transcript.follow). Nil before the first line begins.
     */
    public static func at(_ lines: [Line], seconds: Double) -> (line: Int, chars: Int)? {
        guard let i = lines.lastIndex(where: { $0.at <= seconds }) else { return nil }
        let line = lines[i]
        let t = seconds - line.at
        let spans = wordSpans(line.text)
        if let words = line.words, !words.isEmpty, !spans.isEmpty {
            // The word being said: the last to have started (the first, before any has). Word times beyond the line's
            // words go with its last word.
            let k = min(max(words.lastIndex(where: { $0 <= t }) ?? -1, 0), spans.count - 1)
            return (i, spans[k].upperBound)
        }
        let progress = line.len > 0 ? coerceIn(t / line.len, 0, 1) : 1
        return (i, toInt(Double(line.text.utf16.count) * progress))
    }

    /// Where each word of [text] is (its UTF-16 units): words split at whitespace (Kotlin's), as tools/content.py's.
    private static func wordSpans(_ text: String) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var start = -1
        var j = 0
        for unit in text.utf16 {
            if Kt.isWhitespace(unit) {
                if start >= 0 { spans.append(start..<j) }
                start = -1
            } else if start < 0 {
                start = j
            }
            j += 1
        }
        if start >= 0 { spans.append(start..<j) }
        return spans
    }

    /// Kotlin's Double.coerceIn: NaN goes through.
    private static func coerceIn(_ x: Double, _ low: Double, _ high: Double) -> Double {
        if x < low { return low }
        if x > high { return high }
        return x
    }

    /// Kotlin's Double.toInt(): NaN is 0, the rest truncated and saturated.
    private static func toInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        return Int(d)
    }
}
