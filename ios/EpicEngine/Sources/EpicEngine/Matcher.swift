// Matcher.kt: which answer of a question the player gave.

/**
 * Which answer of a question the player gave (docs/MAP_FORMAT.md, "Matching what the player says"): the skill's
 * yes/no rule for mixed answers first; then rank by rank, highest first, exact checks (seq, digits, re) in order and
 * then phrases (yes, no, words, repeat); then the map's own repeat words; then "any".
 */
public enum Matcher {
    /**
     * [index]: the answer taken (nil: none); [repeat]: the map's own "repeat" words; [how]: for logs and tests;
     * [aside]: none taken, but the answer was heard: it isn't sure, or a phrase in it doesn't count (negated).
     */
    public struct Result: Equatable, Sendable {
        public let index: Int?
        public let `repeat`: Bool
        public let how: String
        public let aside: Bool

        public init(index: Int?, repeat: Bool, how: String, aside: Bool = false) {
            self.index = index
            self.repeat = `repeat`
            self.how = how
            self.aside = aside
        }
    }

    /// One answer's phrase found in what was said. Compared by identity, as Kotlin's `!==` does.
    private final class Hit {
        let index: Int
        let phrase: Phrase
        let start: Int
        let negated: Bool

        init(_ index: Int, _ phrase: Phrase, _ start: Int, _ negated: Bool) {
            self.index = index
            self.phrase = phrase
            self.start = start
            self.negated = negated
        }

        var end: Int { start + Kt.length(phrase.text) }
        func overlaps(_ o: Hit) -> Bool { start < o.end && o.start < end }
    }

    /// Fails as the Kotlin engine does: a seq answer's missing symbol table (MapError), an "opposite" that isn't
    /// one of the question's answers, or a regular expression java.util.regex throws on (PlayError).
    public static func match(_ map: GameMap, _ ask: Ask, _ vars: VarStore, _ said: String) throws -> Result {
        let text = SpokenText.normalise(said)
        if text.isEmpty { return Result(index: nil, repeat: false, how: "nothing") }
        let live = ask.answers.enumerated().filter { $0.element.whenCond?.test(vars) ?? true }
        if let yes = mixed(map, text) {
            if let answer = live.first(where: { yes ? isYes($0.element.match) : isNo($0.element.match) }) {
                return Result(index: answer.offset, repeat: false, how: "mixed: \(yes ? "yes" : "no")")
            }
            if live.contains(where: { isYes($0.element.match) || isNo($0.element.match) }) {
                return Result(index: nil, repeat: false, how: "mixed, no such answer")
            }
        }
        var aside = SpokenText.unsure(text)
        let ranks = live.map(\.element.rank).uniqued().sorted(by: >)
        for rank in ranks {
            let group = live.filter { $0.element.rank == rank }
            for (i, a) in group where try exact(map, a.match, text) {
                return Result(index: i, repeat: false, how: a.match.kotlinName)
            }
            if let r = try phrases(map, ask, group, text, setAside: { aside = true }) { return r }
        }
        if !ask.answers.contains(where: { if case .repeat = $0.match { true } else { false } }) {
            if let p = SpokenText.longest(text, map.words.repeat) {
                return Result(index: nil, repeat: true, how: "repeat \"\(p.text)\"")
            }
        }
        if let any = live.first(where: { if case .anyText = $0.element.match { true } else { false } }) {
            return Result(index: any.offset, repeat: false, how: "any")
        }
        return Result(index: nil, repeat: false, how: "not understood", aside: aside)
    }

    private static func isYes(_ m: Match) -> Bool { if case .yes = m { true } else { false } }
    private static func isNo(_ m: Match) -> Bool { if case .no = m { true } else { false } }

    /**
     * An answer of two or more words that are all yes words, no words or fillers: true if its last yes or no word is a
     * yes, false if a no ("no yes" is a yes, "yeah no" a no). Nil otherwise.
     */
    public static func mixed(_ map: GameMap, _ text: String) -> Bool? {
        guard let m = map.words.mixed else { return nil }
        // A phrase of two words ("why not") stands in as one marker word: U+0001 for yes, U+0002 for no.
        var t = " \(text) "
        for p in (m.yes + m.no) where p.utf16.contains(0x20) {
            t = replace(t, " \(p) ", m.yes.contains(p) ? " \u{1} " : " \u{2} ")
        }
        let words = Kt.trim(t).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count < 2 { return nil }
        func isYes(_ w: String) -> Bool { w == "\u{1}" || m.yes.contains(w) }
        func isNo(_ w: String) -> Bool { w == "\u{2}" || m.no.contains(w) }
        if !words.allSatisfy({ isYes($0) || isNo($0) || m.filler.contains($0) }) { return nil }
        guard let last = words.last(where: { isYes($0) || isNo($0) }) else { return nil }
        return isYes(last)
    }

    /// Kotlin's String.replace(old, new): every occurrence, left to right, without overlaps.
    private static func replace(_ s: String, _ old: String, _ new: String) -> String {
        let h = Array(s.utf16)
        let o = Array(old.utf16)
        let n = Array(new.utf16)
        var out: [UInt16] = []
        var i = 0
        var found = false
        while i < h.count {
            if i + o.count <= h.count && h[i..<(i + o.count)].elementsEqual(o) {
                out += n
                i += o.count
                found = true
            } else {
                out.append(h[i])
                i += 1
            }
        }
        return found ? String(decoding: out, as: UTF16.self) : s
    }

    /// The (normalised) text without the map's repeat words in it, in their order (an exact one: all of it, or none).
    private static func withoutRepeats(_ map: GameMap, _ text: String) -> String {
        var t = " \(text) "
        for p in map.words.repeat {
            if p.exact {
                if Kt.utf16Equal(text, p.text) { return "" }
            } else {
                while Kt.contains(t, " \(p.text) ") { t = replace(t, " \(p.text) ", " ") }
            }
        }
        return Kt.trim(t)
    }

    private static func exact(_ map: GameMap, _ m: Match, _ text: String) throws -> Bool {
        switch m {
        case let .seq(seq, table, exact, spelled, least):
            guard let t = map.symbols[table] else { throw MapError("no symbol table \(table)") }
            let got = SpokenText.symbols(text, t, spelled: spelled)
            if let least { return Kt.length(got) >= least }
            return exact ? Kt.utf16Equal(got, seq) : Kt.contains(got, seq)
        case let .digits(digits, exact, least):
            // The map's repeat words aren't numbers: "one more time" is a repeat, not a 1.
            let got = SpokenText.digits(withoutRepeats(map, text))
            if let least { return Kt.length(got) >= least }
            return exact ? Kt.utf16Equal(got, digits) : Kt.contains(got, digits)
        case .re(let regex):
            return try regex.containsMatch(in: text)
        default:
            return false
        }
    }

    /**
     * The phrase answer given in this rank, or nil. The longest phrase wins over the phrases inside it ("no
     * rehearsal" over "rehearsal"); two answers that would do different things, said apart ("follow or hide"),
     * are unclear, and the next rank is tried. A negated phrase ("don't follow", "of course not") counts for its
     * "opposite", or else not at all. An answer that isn't sure ("I'm not sure", "I don't know") counts only for a
     * phrase that says so itself, so it is never a yes or a no. [setAside] hears of a phrase said that doesn't count.
     */
    private static func phrases(
        _ map: GameMap, _ ask: Ask, _ group: [(offset: Int, element: Answer)], _ text: String,
        setAside: () -> Void
    ) throws -> Result? {
        let unsure = SpokenText.unsure(text)
        var hits: [Hit] = []
        for (i, a) in group {
            let phrases: [Phrase]
            switch a.match {
            case .yes(let extra): phrases = map.words.yes + extra
            case .no(let extra): phrases = map.words.no + extra
            case .words(let p): phrases = p
            case .repeat: phrases = map.words.repeat
            default: continue
            }
            let opposite = a.opposite
            let said = phrases.filter { SpokenText.phraseLength(text, $0) >= 0 }
            let counted = said.filter {
                (!unsure || SpokenText.unsure($0.text)) && (opposite != nil || $0.exact || !SpokenText.negated(text, $0.text))
            }
            guard let phrase = counted.kMaxBy({ Kt.length($0.text) }) else {
                if !said.isEmpty { setAside() }
                continue
            }
            let negated = opposite != nil && !phrase.exact && SpokenText.negated(text, phrase.text)
            let start = phrase.exact ? 0 : Kt.indexOf(" \(text) ", " \(phrase.text) ")
            hits.append(Hit(negated ? opposite! : i, phrase, start, negated))
        }
        guard let winner = hits.kMaxBy({ Kt.length($0.phrase.text) }) else { return nil }
        func action(_ h: Hit) throws -> (Go?, SetList) {
            guard ask.answers.indices.contains(h.index) else {
                throw PlayError("Index \(h.index) out of bounds for length \(ask.answers.count)")
            }
            let a = ask.answers[h.index]
            return (a.go, a.set)
        }
        for h in hits where h !== winner {
            let (go, set) = try action(h)
            let (winnerGo, winnerSet) = try action(winner)
            if (go != winnerGo || set != winnerSet)
                && (!h.overlaps(winner) || Kt.length(h.phrase.text) == Kt.length(winner.phrase.text)) {
                return nil
            }
        }
        return Result(index: winner.index, repeat: false, how: (winner.negated ? "not " : "") + "\"\(winner.phrase.text)\"")
    }
}
