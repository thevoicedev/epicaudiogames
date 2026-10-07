// Text.kt: reading what the player said (normalising, phrases, negation, digits and symbols).

import Foundation

/**
 * Reading what the player said (Kotlin's Text). The digit and symbol readers are the Alexa skills' own (Signal
 * Decoders' digitsSaid, sequenceSaid and lettersSaid), so the games accept the same answers.
 */
public enum SpokenText {
    /**
     * Lower case, curly apostrophes made straight, everything but letters, digits and apostrophes made spaces (one
     * space for each run), trimmed. Only a-z, 0-9 and ' are kept, character by character, so the result is ASCII.
     */
    public static func normalise(_ s: String) -> String {
        var out: [UInt8] = []
        var gap = false
        for c in s.lowercased().unicodeScalars {
            var b: UInt8
            switch c {
            case "a"..."z", "0"..."9", "'": b = UInt8(c.value)
            case "\u{2019}", "\u{2018}", "`": b = UInt8(ascii: "'")
            default:
                gap = true
                continue
            }
            if gap && !out.isEmpty { out.append(0x20) }
            gap = false
            out.append(b)
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The length of the phrase if the (normalised) text says it as whole words (an exact phrase: is it), else -1.
    public static func phraseLength(_ text: String, _ phrase: Phrase) -> Int {
        if phrase.exact { return Kt.utf16Equal(text, phrase.text) ? Kt.length(phrase.text) : -1 }
        return Kt.contains(" \(text) ", " \(phrase.text) ") ? Kt.length(phrase.text) : -1
    }

    /// The longest of the phrases the text says (the first of the longest), or nil.
    public static func longest(_ text: String, _ phrases: [Phrase]) -> Phrase? {
        phrases.filter { phraseLength(text, $0) >= 0 }.kMaxBy { Kt.length($0.text) }
    }

    /**
     * Whether the phrase is negated: "don't", "dont", "not" or "never" up to three words before it, or a "not" right
     * after it that ends the answer ("of course not", "I would not").
     */
    public static func negated(_ text: String, _ phrase: String) -> Bool {
        let pattern = "\\b(don't|dont|not|never)( [a-z0-9']+){0,3} \(NSRegularExpression.escapedPattern(for: phrase))( |$)"
        if let re = try? RegexCache.shared.regex(pattern),
           re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
            return true
        }
        return endsWith(" \(text)", " \(phrase) not")
    }

    /// Kotlin's String.endsWith: the same UTF-16 units at the end.
    private static func endsWith(_ s: String, _ suffix: String) -> Bool {
        let a = Array(s.utf16)
        let b = Array(suffix.utf16)
        return a.count >= b.count && a[(a.count - b.count)...].elementsEqual(b)
    }

    /// Phrases that say the player isn't sure.
    static let unsurePhrases = ["not sure", "unsure", "dunno", "no idea", "don't know", "dont know", "do not know"]

    /// Whether the (normalised) text says the player isn't sure: "I'm not sure", "I don't know".
    public static func unsure(_ text: String) -> Bool {
        unsurePhrases.contains { Kt.contains(" \(text) ", " \($0) ") }
    }

    static let ones: [String: Int64] = [
        "zero": 0, "oh": 0, "one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3, "four": 4,
        "for": 4, "fore": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    static let tens: [String: Int64] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
    ]

    /// Words that sound like a number but are mostly something else.
    static let homophones: Set<String> = ["oh", "won", "to", "too", "for", "fore"]

    private static func isNumber(_ t: String) -> Bool { !t.isEmpty && t.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

    private static func isNumberWord(_ t: String?) -> Bool {
        guard let t else { return false }
        return isNumber(t) || ones[t] != nil || tens[t] != nil || t == "hundred" || t == "thousand"
    }

    /// The words of normalised text (Kotlin's split(' ') without the empty pieces).
    private static func words(_ s: String) -> [String] {
        s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /**
     * The digits said, in order: "four two two one one", "4 2 2 1 1", "four twenty-two eleven" and
     * "forty two thousand two hundred and eleven" all give "42211". "To", "for", "won" and "oh" count only next to
     * another number ("for to to one one"), so "I want to play" says none.
     */
    public static func digits(_ said: String) -> String {
        // Kotlin replaces '-' with ' ' first; normalise makes it a space anyway.
        let all = words(normalise(said))
        let tokens = all.indices.filter { i in
            !homophones.contains(all[i]) || (i > 0 && isNumberWord(all[i - 1]))
                || (i + 1 < all.count && isNumberWord(all[i + 1]))
        }.map { all[$0] }
        if tokens.contains("hundred") || tokens.contains("thousand") {
            // Kotlin's Long arithmetic, which wraps.
            var total: Int64 = 0
            var current: Int64 = 0
            var any = false
            for t in tokens {
                if isNumber(t) {
                    current = current &+ (Kt.int64OrNull(t) ?? 0)
                    any = true
                } else if let n = ones[t] {
                    current = current &+ n
                    any = true
                } else if let n = tens[t] {
                    current = current &+ n
                    any = true
                } else if t == "hundred" {
                    current = (current == 0 ? 1 : current) &* 100
                } else if t == "thousand" {
                    total = total &+ (current == 0 ? 1 : current) &* 1000
                    current = 0
                }
            }
            return any ? String(total &+ current) : ""
        }
        var out = ""
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if isNumber(t) {
                out += t
            } else if let ten = tens[t] {
                if i + 1 < tokens.count, let one = ones[tokens[i + 1]], one >= 1 && one <= 9 {
                    out += String(ten + one)
                    i += 1
                } else {
                    out += String(ten)
                }
            } else if let one = ones[t] {
                out += String(one)
            }
            i += 1
        }
        return out
    }

    /**
     * The symbols said, in order, with a table such as { "l": ["left", "lift"], "r": ["right", "write"] }:
     * "left right right left" gives "lrrl". With [spelled], a word made only of one-letter symbols ("ac") counts
     * letter by letter.
     */
    public static func symbols(_ said: String, _ table: LinkedMap<[String]>, spelled: Bool = false) -> String {
        var out = ""
        for w in words(normalise(said)) {
            if let symbol = table.first(where: { $0.value.contains(w) })?.key {
                out += symbol
            } else if spelled && Kt.length(w) >= 2 && w.unicodeScalars.allSatisfy({ table.contains(String($0)) }) {
                out += w
            }
        }
        return out
    }
}
