// nuclear/NuclearWar.kt (lines 1-231 and 330-344): the game, its Play calls, the turn builder and the audio getters.

/**
 * Nuclear War, as the Mini Games skill plays it on a speaker: a port of alexa/lambda/Games/nuclear-war/index.js with
 * its screen paths taken out. The functions keep the skill's names (in their comments) and its rules, quirks
 * included: computer countries never buy bombs when their motive is defence, a country that bombs back always aims
 * at the first city it can, and so on. Don, the announcer, says what Alexa said ([Lines]); the leaders' calls, the
 * music and the sound effects are the skill's own recordings ([NuclearAudio]).
 *
 * Left out: coins, the daily play limit and the upsell, and "play again, or a different game?" (the app's end
 * panel). Changed: lists of countries and cities are said in the countries' fixed order; a few dead ends of the skill
 * go on instead (noted where they are).
 *
 * Every random draw goes through [random], in the Kotlin engine's order, so a seed plays the same game on both. The
 * rest of the game is in the NuclearWar+*.swift files, one per section of NuclearWar.kt.
 */
public final class NuclearWar: Play {
    public static let id = "nuclear-war"

    static let yesWords = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "alright", "all right", "of course",
        "definitely", "absolutely", "please", "go on", "go ahead", "do it", "let's do it", "pick up", "answer",
        "answer it", "why not", "i do", "i would", "yes please"]
    static let noWords = ["no", "nope", "nah", "no thanks", "no thank you", "not now", "never", "no way",
        "not really", "neither", "ignore", "ignore it", "hang up", "don't", "i don't", "nothing", "no more",
        // (a yes word with "not" isn't a yes: these say it's a no)
        "i do not", "i would not", "absolutely not", "definitely not", "of course not", "not at all"]
    static let repeatWords = ["repeat", "say that again", "say it again", "what", "pardon"]
    static let numberWords: [(String, Int)] = [
        ("zero", 0), ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6), ("seven", 7),
        ("eight", 8), ("nine", 9), ("ten", 10), ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14),
        ("fifteen", 15), ("sixteen", 16), ("seventeen", 17), ("eighteen", 18), ("nineteen", 19),
    ]
    static let tens: [(String, Int)] = [("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50)]
    static let scales: [(String, Int)] = [("hundred", 100), ("thousand", 1000)]
    static let numberPattern = "\\b(\\d+|"
        + (numberWords.map(\.0) + tens.map(\.0) + scales.map(\.0) + ["couple"]).joined(separator: "|") + ")\\b"

    static let countryWords: [(String, [String])] = [
        ("France", ["france", "french"]),
        ("USA", ["usa", "u s a", "the usa", "america", "american", "united states", "the united states",
            "united states of america", "the us", "u s"]),
        ("UK", ["uk", "u k", "the uk", "united kingdom", "the united kingdom", "britain", "great britain",
            "england", "british"]),
        ("China", ["china", "chinese"]),
        ("Russia", ["russia", "russian"]),
    ]
    /// Words that are a country only said alone: "us" is also the pronoun ("yes, tell us").
    static let countryAlone: [String: [String]] = ["USA": ["us"]]
    static let cityWords: [String: [String]] = [
        "Marseille": ["marseilles"], "Lyon": ["lyons", "leon"], "New York": ["new york city"],
        "Los Angeles": ["la", "l a"], "Wuhan": ["woohan", "wu han"],
        "St Petersburg": ["saint petersburg", "st petersburg", "petersburg"],
    ]

    /// Every text Don has said (tests check that each is one of [Lines.all]).
    public internal(set) var spoken = Set<String>()

    /// The texts Don was asked to say that have no clip in the audio (tests fail on them). Kotlin keeps this on the
    /// NuclearAudio; here each game keeps its own (docs/IOS_PARITY.md, L9).
    public internal(set) var missing = Set<String>()

    let audio: NuclearAudio
    let random: any KotlinRandom
    var st = NuclearState()
    var end: End?
    var reprompt: [Step] = []

    /// The word lists the answers are matched with (the Matcher reads them from a map).
    let words: GameMap

    /// A game with [audio] (NuclearAudio.load of clips.json, or the placeholder), drawing from [random]: by default a
    /// Kotlin XorWowRandom seeded from the system, as the app plays it.
    public init(audio: NuclearAudio, random: any KotlinRandom = XorWowRandom()) {
        self.audio = audio
        self.random = random
        words = GameMap(
            id: NuclearWar.id, title: "Nuclear War", start: "", vars: VarStore(), keep: [], repeatSays: false,
            who: audio.who,
            words: WordLists(
                yes: NuclearWar.phrases(NuclearWar.yesWords), no: NuclearWar.phrases(NuclearWar.noWords),
                repeat: NuclearWar.phrases(NuclearWar.repeatWords),
                mixed: Mixed(yes: ["yes", "yeah", "yep", "sure", "ok", "okay"], no: ["no", "nope", "nah"],
                    filler: ["um", "uh", "er", "erm", "well", "oh"])),
            symbols: LinkedMap(), nodes: LinkedMap()
        )
    }

    static func phrases(_ list: [String]) -> [Phrase] { list.map { Phrase(SpokenText.normalise($0), false) } }

    // ----- Play -----

    public var who: LinkedMap<String> { audio.who }

    /// The question, or nil at the end. Nil too where working it out fails (a save with no country of ours, say):
    /// the calls that return a turn throw there instead.
    public var ask: Ask? { try? currentAsk() }

    func currentAsk() throws -> Ask? {
        guard end == nil else { return nil }
        return Ask(reprompt: reprompt, answers: try answers().map(\.answer), otherwise: nil, buttons: try buttons())
    }

    public func start() throws -> Turn {
        let kept = st.settingsJSON()
        st = NuclearState()
        try st.takeSettings(kept)
        end = nil
        let o = Out(self)
        try playNuclearWar(o)
        return try turn(o)
    }

    /// The settings saved with the game are taken first, so a game started afresh still has them. Settings or a
    /// state that can't be read (a save from another version, say) are left out: it starts afresh.
    public func open(_ saved: Saved?) throws -> Turn {
        if case .string(let settings)? = saved?.vars["settings"] {
            try? st.takeSettings(JSONParser.parse(settings).jsonObject())
        }
        if let saved, canResume(saved) { return try resume(saved) }
        return try start()
    }

    public func canResume(_ saved: Saved) -> Bool {
        guard !saved.ended, case .string(let state)? = saved.vars["state"] else { return false }
        return saved.node != Q.gameOver.rawValue && NuclearWar.readable(state)
    }

    static func readable(_ state: String) -> Bool {
        (try? NuclearState.fromJSON(JSONParser.parse(state).jsonObject())) != nil
    }

    public func resume(_ saved: Saved) throws -> Turn {
        guard case .string(let state)? = saved.vars["state"] else {
            throw PlayError("null cannot be cast to non-null type kotlin.String")
        }
        st = try NuclearState.fromJSON(JSONParser.parse(state).jsonObject())
        end = nil
        let o = Out(self)
        try continueWar(o)
        return try turn(o)
    }

    public func save() -> Saved {
        let settings = JSONWriter.write(.object(st.settingsJSON()))
        return Saved(node: st.q.rawValue, vars: ["state": .string(st.toJSONString()), "settings": .string(settings)],
                     ended: end != nil)
    }

    public func answer(_ said: String) throws -> Turn {
        let pairs = try answers()
        let r = try Matcher.match(
            words, Ask(reprompt: reprompt, answers: pairs.map(\.answer), otherwise: nil, buttons: []), VarStore(), said)
        let o = Out(self)
        let buying = st.q == .bombPrompt || st.q == .bombNumberPrompt
        switch r.index.map({ pairs[$0].intent }) {
        case .yes?: try yes(o)
        case .no?: try no(o)
        case .number?: try pickNumber(o, number(said))
        case .name(let value)?: if buying { try pickNumber(o, nil) } else { try answerWith(o, value) }
        // While buying bombs, the skill reads anything else as a number it didn't catch. Otherwise "repeat",
        // or not understood: its fallback asks again.
        case nil: if buying && !r.repeat { try pickNumber(o, nil) } else { try continueWar(o) }
        }
        return try turn(o, Heard(said: said, answer: r.index, how: r.how))
    }

    public func silence() throws -> Turn {
        Turn(steps: reprompt, ask: try currentAsk(), end: end, quit: false, node: st.q.rawValue, visited: [])
    }

    public func restart(at: String?) throws -> Turn { try start() }

    public func nextChapter() throws -> Turn { throw PlayError("Nuclear War has no chapters") }

    public func hasChapter(_ next: String) -> Bool { false }

    /// As Session's: an answer set aside (unsure, or negated) is understood too, so the app keeps it.
    public func understands(_ said: String) throws -> Bool {
        let pairs = try answers()
        let r = try Matcher.match(
            words, Ask(reprompt: reprompt, answers: pairs.map(\.answer), otherwise: nil, buttons: []), VarStore(), said)
        return r.index != nil || r.repeat || r.aside
    }

    // ----- Turns -----

    /// A turn as it's made: steps to play and the reprompt (the skill's Response).
    final class Out {
        private let game: NuclearWar
        var steps: [Step] = []
        var reprompt: [Step] = []

        init(_ game: NuclearWar) { self.game = game }

        func don(_ text: String) {
            steps.append(game.line(text, more: false))
        }

        /// A piece of a sentence that carries on in the next one.
        func part(_ text: String) {
            steps.append(game.line(text, more: true))
        }

        func money(_ amount: Int64) { part(Lines.money(amount)) }

        /// A list said a name at a time ([Lines.items]).
        func items(_ names: [String], _ last: Lines.Last) {
            let pieces = Lines.items(names, last)
            for (i, p) in pieces.enumerated() {
                if i == pieces.count - 1 && last == .end { don(p) } else { part(p) }
            }
        }

        func clip(_ path: String?) {
            if let c = game.audio.clip(path) { steps.append(.play(c)) }
        }

        /// A sound under what follows (the skill's mixers): it plays once, until [stopBeds] or the turn's end.
        func bed(_ path: String?, _ volume: Double) {
            if let c = game.audio.clip(path) { steps.append(.bed(path: c.path, volume: volume, dur: c.dur)) }
        }

        func stopBeds() {
            steps.append(.bed(path: nil, volume: 0.0, dur: 0.0))
        }

        func pause(_ seconds: Double) {
            steps.append(.pause(seconds))
        }

        func mix(_ name: String) {
            if let c = game.audio.mix(name) { steps.append(.play(c)) }
        }

        func reprompt(_ text: String) {
            reprompt = [game.line(text, more: false)]
        }
    }

    func line(_ text: String, more: Bool) -> Step {
        spoken.insert(text)
        if !audio.has(text) { missing.insert(text) }
        let p = audio.don(text)
        guard more else { return .play(p) }
        let lines = p.lines.map { l in
            Line(at: l.at, len: l.len, who: l.who, text: l.text, words: l.words, more: true)
        }
        return .play(Clip(path: p.path, dur: p.dur, lines: lines, sfx: p.sfx))
    }

    func turn(_ o: Out, _ heard: Heard? = nil) throws -> Turn {
        if end == nil { reprompt = o.reprompt }
        return Turn(steps: o.steps, ask: try currentAsk(), end: end, quit: false, node: st.q.rawValue, visited: [],
                    heard: heard)
    }

    func finish(_ kind: String, _ title: String) {
        st.q = .gameOver
        end = End(kind: kind, title: title, next: nil, retry: nil, locked: nil)
    }

    // ----- The skill's audio getters (Audio.js), over the table in clips.json -----

    func sfx(_ name: String) -> String? { audio.path("sfx", name) }
    func theme(_ ref: String) -> String? { audio.path(ref, "Theme") }

    /// One of a leader's recorded lines of a kind, not yet played this game if there is one (getGeneralChat etc.).
    func unused(_ n: Nation, _ kind: String, _ field: String) throws -> String? {
        let options = try audio.paths(n.ref, field)
        if options.isEmpty { return nil }
        let used = n.used[kind] ?? []
        if !n.used.contains(kind) { n.used[kind] = [] }
        let fresh = options.indices.filter { !used.contains($0) }
        let i = try (fresh.isEmpty ? Array(options.indices) : fresh).kRandom(random)
        n.used[kind] = used + [i]
        return options[i]
    }

    // ----- Kotlin's library, where Swift would trap or differ -----

    /// Kotlin's repeat(n): nothing when n isn't above 0.
    func times(_ n: Int, _ body: () throws -> Void) rethrows {
        var i = 0
        while i < n {
            try body()
            i += 1
        }
    }

    /// Kotlin's list[i]: an index out of range fails (IndexOutOfBoundsException) instead of trapping.
    func at<T>(_ list: [T], _ i: Int) throws -> T { try Lines.at(list, i) }

    /// Kotlin's Long.toInt(): the low 32 bits.
    static func int(_ l: Int64) -> Int { Int(Int32(truncatingIfNeeded: l)) }

    /// Kotlin's Int arithmetic, worked out in a Swift Int: the low 32 bits of the result ([KotlinInt] for one stored).
    static func int(_ n: Int) -> Int { Int(Int32(truncatingIfNeeded: n)) }

    /// Kotlin's Double.toInt(): NaN is 0, out-of-range values saturate at Int's bounds, the rest truncate.
    static func int(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= Double(Int32.max) { return Int(Int32.max) }
        if d <= Double(Int32.min) { return Int(Int32.min) }
        return Int(d)
    }
}

extension Array {
    /// Kotlin's getOrNull.
    func getOrNull(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// Kotlin compares text by its UTF-16 units; Swift's == and contains take canonically equal text ("é" and "e" + U+0301,
// U+212A KELVIN SIGN and "K") as the same. Refs, names and flags read from a save are compared with these.

extension String {
    /// Kotlin's ==: the same UTF-16 units (and text is never equal to null).
    func kEquals(_ other: String?) -> Bool { other.map { Kt.utf16Equal(self, $0) } ?? false }
}

extension Sequence where Element == String {
    /// Kotlin's `in`: an element with the same UTF-16 units.
    func kContains(_ s: String) -> Bool { contains { Kt.utf16Equal($0, s) } }
}
