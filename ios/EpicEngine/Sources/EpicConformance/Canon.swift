// Canon.kt: the fixtures' canonical encoding (fixtures/engine/README.md, sections 2 to 7), byte for byte.

import EpicEngine

/// A value as Canon.kt writes it: what its `Any?` trees hold (null, text, Boolean, Int, Double, raw JSON, lists, maps).
public indirect enum CanonValue: Sendable {
    case null
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    /// Text that is already canonical JSON, written as it is.
    case raw(String)
    case list([CanonValue])
    /// An object, its keys in this order.
    case object([(String, CanonValue)])

    public static func opt(_ s: String?) -> CanonValue { s.map(CanonValue.string) ?? .null }
    public static func opt(_ i: Int?) -> CanonValue { i.map(CanonValue.int) ?? .null }
}

extension CanonValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: CanonValue...) { self = .list(elements) }
    public init(nilLiteral: ()) { self = .null }
}

/**
 * The fixtures' canonical encoding: compact JSON with a fixed key order, doubles never as float text, FNV-1a hashes,
 * and the canonical forms of values, maps and turns. Kotlin's Canon must give the same text byte for byte.
 */
public enum Canon {
    public static let format = 1

    // ----- JSON -----

    /// The canonical JSON of a value.
    public static func json(_ v: CanonValue) -> String {
        var out = ""
        write(v, into: &out)
        return out
    }

    public static func write(_ v: CanonValue, into out: inout String) {
        switch v {
        case .null: out.append("null")
        case .string(let s): quote(s, into: &out)
        case .bool(let b): out.append(b ? "true" : "false")
        case .int(let i): out.append(String(i))
        case .double(let d): double(d, into: &out)
        case .raw(let text): out.append(text)
        case .list(let items):
            out.append("[")
            for (i, e) in items.enumerated() {
                if i > 0 { out.append(",") }
                write(e, into: &out)
            }
            out.append("]")
        case .object(let fields):
            out.append("{")
            for (i, (k, e)) in fields.enumerated() {
                if i > 0 { out.append(",") }
                quote(k, into: &out)
                out.append(":")
                write(e, into: &out)
            }
            out.append("}")
        }
    }

    /// `"`, `\` and controls escaped (controls as \u00xx, lowercase); everything else as itself.
    public static func quote(_ s: String, into out: inout String) {
        out.append("\"")
        if !s.utf8.contains(where: { $0 < 0x20 || $0 == 0x22 || $0 == 0x5C }) {
            out.append(s)
        } else {
            for c in s.unicodeScalars {
                switch c.value {
                case 0x22: out.append("\\\"")
                case 0x5C: out.append("\\\\")
                case 0..<0x20:
                    out.append("\\u00")
                    out.unicodeScalars.append(hexDigits[Int(c.value >> 4)])
                    out.unicodeScalars.append(hexDigits[Int(c.value & 15)])
                default: out.unicodeScalars.append(c)
                }
            }
        }
        out.append("\"")
    }

    private static let hexDigits = Array("0123456789abcdef".unicodeScalars)

    private static let two53 = 9_007_199_254_740_992.0

    /// A whole double as an integer; anything else as "x" and its IEEE bits (every NaN as the canonical NaN).
    public static func double(_ d: Double, into out: inout String) {
        if d.isFinite && d == d.rounded(.down) && abs(d) < two53 && !(d == 0 && d.sign == .minus) {
            out.append(String(Int64(d)))
        } else {
            out.append("\"x")
            out.append(FNV.hex(d.isNaN ? 0x7ff8_0000_0000_0000 : d.bitPattern))
            out.append("\"")
        }
    }

    /// The hash of a value: FNV-1a of its canonical JSON, as 16 hex digits.
    public static func hash(_ v: CanonValue) -> String { FNV.hex(FNV.hash(json(v))) }

    /// Parsed fixture JSON written canonically again: every value inside a fixture is canonical, so this gives back
    /// its exact text (strings re-escaped the canonical way, numbers and literals as written).
    public static func reencode(_ j: JSON) -> String {
        var out = ""
        reencode(j, into: &out)
        return out
    }

    private static func reencode(_ j: JSON, into out: inout String) {
        switch j {
        case .null: out.append("null")
        case .string(let s): quote(s, into: &out)
        case .literal(let text): out.append(text)
        case .array(let items):
            out.append("[")
            for (i, e) in items.enumerated() {
                if i > 0 { out.append(",") }
                reencode(e, into: &out)
            }
            out.append("]")
        case .object(let o):
            out.append("{")
            var first = true
            for (k, e) in o {
                if !first { out.append(",") }
                first = false
                quote(k, into: &out)
                out.append(":")
                reencode(e, into: &out)
            }
            out.append("}")
        }
    }

    // ----- Values -----

    /// A variable's value: ["n", double], ["b", bool], ["s", text]; null when missing.
    public static func value(_ v: Value?) -> CanonValue {
        switch v {
        case nil: .null
        case .number(let d): [.string("n"), .double(d)]
        case .bool(let b): [.string("b"), .bool(b)]
        case .string(let s): [.string("s"), .string(s)]
        }
    }

    /// A variable list, in the variables' order.
    public static func vars(_ vars: VarStore) -> CanonValue {
        .list(vars.map { [.string($0.key), value($0.value)] })
    }

    /// What changed: new or different values in the current order, then the gone ones (null) in the old order.
    public static func delta(_ prev: VarStore, _ cur: VarStore) -> CanonValue {
        var out: [CanonValue] = []
        // Value's equality is the canonical one: Doubles bit for bit (every NaN the same, -0.0 not 0.0).
        for (k, v) in cur where prev[k] != v {
            out.append([.string(k), value(v)])
        }
        for k in prev.keys where !cur.contains(k) {
            out.append([.string(k), .null])
        }
        return .list(out)
    }

    // ----- Files -----

    /// The header every fixture starts with (README section 4).
    public static func header(gamesSha256: String, engineSha256: String) -> [(String, CanonValue)] {
        [("format", .int(format)), ("games_sha256", .string(gamesSha256)), ("engine_sha256", .string(engineSha256))]
    }
}

extension Canon {
    /**
     * The map canon (README section 6), with clip and ask hashes cached as Canon.kt caches them. One per walk, test
     * or thread: it isn't thread-safe.
     */
    public final class Encoder {
        private var clipHashes: [ClipKey: String] = [:]
        private var askHashes: [String: String] = [:]

        public init() {}

        public func line(_ l: Line) -> CanonValue {
            [.double(l.at), .double(l.len), .string(l.who), .string(l.text),
             l.words.map { .list($0.map(CanonValue.double)) } ?? .null, .bool(l.more)]
        }

        public func clip(_ c: Clip) -> CanonValue {
            [.string(c.path), .double(c.dur), .bool(c.sfx), .list(c.lines.map(line))]
        }

        public func clipHash(_ c: Clip) -> String {
            let key = ClipKey(c)
            if let h = clipHashes[key] { return h }
            let h = Canon.hash(clip(c))
            clipHashes[key] = h
            return h
        }

        public func step(_ s: Step) -> CanonValue {
            switch s {
            case .play(let c):
                return [.string("p"), .string(c.path), .string(String(c.lines.map { $0.more ? "1" : "0" }.joined())),
                        .string(clipHash(c))]
            case .num(let variable): return [.string("n"), .string(variable)]
            case .pause(let seconds): return [.string("z"), .double(seconds)]
            case .bed(let path, let volume, let dur): return [.string("b"), .opt(path), .double(volume), .double(dur)]
            case .when(let cond, let steps): return [.string("w"), .string(cond.source), self.steps(steps)]
            case .pick(let options): return [.string("k"), .list(options.map(steps))]
            case .by(let variable, let cases, let otherwise):
                return [.string("y"), .string(variable), .list(cases.map { [.string($0.key), steps($0.value)] }),
                        steps(otherwise)]
            }
        }

        public func steps(_ list: [Step]) -> CanonValue { .list(list.map(step)) }

        public func go(_ g: Go?) -> CanonValue {
            switch g {
            case nil: return .null
            case .to(let node)?: return [.string("to"), .string(node)]
            case .random(let targets)?: return [.string("random"), .list(targets.map(go))]
            case .if(let cases, let otherwise)?:
                return [.string("if"), .list(cases.map { [.string($0.cond.source), go($0.go)] }), go(otherwise)]
            case .restart(let node)?: return [.string("restart"), .string(node)]
            case .quit?: return [.string("quit")]
            case .leave?: return [.string("leave")]
            case .draw(let nodes, let deck)?:
                return [.string("draw"), .list(nodes.map(CanonValue.string)), .string(deck)]
            }
        }

        public func sets(_ set: SetList) -> CanonValue {
            .list(set.map { k, v in
                let value: CanonValue = switch v {
                case .assign(let x): [.string("="), Canon.value(x)]
                case .add(let amount): [.string("+"), .double(amount)]
                case .rand(let from, let to): [.string("rand"), .int(Int(from)), .int(Int(to))]
                case .calc(let expr): [.string("calc"), .string(expr.source)]
                }
                return [.string(k), value]
            })
        }

        public func phrase(_ p: Phrase) -> CanonValue { [.string(p.text), .bool(p.exact)] }

        public func phrases(_ list: [Phrase]) -> CanonValue { .list(list.map(phrase)) }

        public func match(_ m: Match) -> CanonValue {
            switch m {
            case .yes(let extra): [.string("yes"), phrases(extra)]
            case .no(let extra): [.string("no"), phrases(extra)]
            case .words(let list): [.string("words"), phrases(list)]
            case .repeat: [.string("repeat")]
            case .seq(let seq, let table, let exact, let spelled, let least):
                [.string("seq"), .string(seq), .string(table), .bool(exact), .bool(spelled), .opt(least)]
            case .digits(let digits, let exact, let least):
                [.string("digits"), .string(digits), .bool(exact), .opt(least)]
            case .re(let r): [.string("re"), .string(r.pattern)]
            case .anyText: [.string("any")]
            }
        }

        public func answer(_ a: Answer) -> CanonValue {
            [match(a.match), go(a.go), sets(a.set), .opt(a.whenCond?.source), .opt(a.opposite), .int(a.rank)]
        }

        public func otherwise(_ e: Else?) -> CanonValue {
            guard let e else { return .null }
            return [steps(e.say), sets(e.set), go(e.go)]
        }

        public func buttons(_ list: [AnswerButton]) -> CanonValue {
            .list(list.map { [.string($0.label), .string($0.value)] })
        }

        public func ask(_ a: Ask?) -> CanonValue {
            guard let a else { return .null }
            return [steps(a.reprompt), .list(a.answers.map(answer)), otherwise(a.otherwise), buttons(a.buttons)]
        }

        public func end(_ e: End?) -> CanonValue {
            guard let e else { return .null }
            return [.string(e.kind), .string(e.title), .opt(e.next), .opt(e.retry), .opt(e.locked)]
        }

        public func node(_ n: Node) -> CanonValue {
            [.string(n.id), .list(n.redirect.map { [.string($0.cond.source), go($0.go)] }), sets(n.set), steps(n.say),
             ask(n.ask), go(n.go), end(n.end)]
        }

        public func mapHeader(_ m: GameMap) -> CanonValue {
            let mixed: CanonValue = m.words.mixed.map { x in
                .object([("yes", strings(x.yes)), ("no", strings(x.no)), ("filler", strings(x.filler))])
            } ?? .null
            return .object([
                ("id", .string(m.id)),
                ("title", .string(m.title)),
                ("start", .string(m.start)),
                ("vars", Canon.vars(m.vars)),
                ("keep", strings(m.keep)),
                ("repeatSays", .bool(m.repeatSays)),
                ("who", .list(m.who.map { [.string($0.key), .string($0.value)] })),
                ("words", .object([
                    ("yes", phrases(m.words.yes)),
                    ("no", phrases(m.words.no)),
                    ("repeat", phrases(m.words.repeat)),
                    ("mixed", mixed),
                ])),
                ("symbols", .list(m.symbols.map { t, table in
                    [.string(t), .list(table.map { [.string($0.key), strings($0.value)] })]
                })),
            ])
        }

        public func map(_ m: GameMap) -> CanonValue { [mapHeader(m), .list(m.nodes.map { node($0.value) })] }

        /// The hash of an Ask's answers and else (a turn writes its buttons and reprompt out).
        public func askHash(_ a: Ask) -> String { Canon.hash([.list(a.answers.map(answer)), otherwise(a.otherwise)]) }

        /// [askHash], cached by the node the question belongs to (a map's asks are its nodes').
        public func askHash(_ a: Ask, at node: String) -> String {
            if let h = askHashes[node] { return h }
            let h = askHash(a)
            askHashes[node] = h
            return h
        }

        private func strings(_ list: [String]) -> CanonValue { .list(list.map(CanonValue.string)) }
    }

    /**
     * Turn lines of one walk or game (README section 7): each line's save delta is against the line before.
     * [askHash] gives a turn's question's hash; by default a map's, cached by the turn's node.
     */
    public final class Turns {
        public let encoder: Encoder
        private let askHash: (Turn, Ask) -> String
        private var prev = VarStore()

        public init(_ encoder: Encoder, askHash: ((Turn, Ask) -> String)? = nil) {
            self.encoder = encoder
            self.askHash = askHash ?? { turn, ask in encoder.askHash(ask, at: turn.node) }
        }

        public func line(_ t: Int, _ input: CanonValue, _ rng: CanonValue, _ turn: Turn, _ saved: Saved) -> String {
            let e = encoder
            let ask: CanonValue = turn.ask.map { a in
                .object([("b", e.buttons(a.buttons)), ("r", e.steps(a.reprompt)), ("a", .string(askHash(turn, a)))])
            } ?? .null
            let heard: CanonValue = turn.heard.map { h in [.string(h.said), .opt(h.answer), .string(h.how)] } ?? .null
            let o: CanonValue = .object([
                ("t", .int(t)),
                ("in", input),
                ("rng", rng),
                ("node", .string(turn.node)),
                ("visited", .list(turn.visited.map(CanonValue.string))),
                ("quit", .bool(turn.quit)),
                ("keep", .bool(turn.keep)),
                ("end", e.end(turn.end)),
                ("heard", heard),
                ("steps", e.steps(turn.steps)),
                ("ask", ask),
                ("save", .object([
                    ("node", .string(saved.node)),
                    ("ended", .bool(saved.ended)),
                    ("vars", .string(Canon.hash(Canon.vars(saved.vars)))),
                    ("delta", Canon.delta(prev, saved.vars)),
                ])),
            ])
            prev = saved.vars
            return Canon.json(o)
        }

        /// The next line follows a save that isn't one of these lines (one Kotlin wrote): its delta is against [vars].
        public func after(_ vars: VarStore) {
            prev = vars
        }
    }
}

/// A clip as a dictionary key, compared bit for bit (Swift's Double equality would make 0.0 and -0.0 one key).
struct ClipKey: Hashable {
    let clip: Clip

    init(_ clip: Clip) { self.clip = clip }

    static func == (a: ClipKey, b: ClipKey) -> Bool {
        let x = a.clip
        let y = b.clip
        guard Kt.utf16Equal(x.path, y.path), x.dur.bitPattern == y.dur.bitPattern, x.sfx == y.sfx,
              x.lines.count == y.lines.count else { return false }
        for (l, m) in zip(x.lines, y.lines) {
            guard l.at.bitPattern == m.at.bitPattern, l.len.bitPattern == m.len.bitPattern, l.more == m.more,
                  Kt.utf16Equal(l.who, m.who), Kt.utf16Equal(l.text, m.text) else { return false }
            switch (l.words, m.words) {
            case (nil, nil): break
            case let (p?, q?):
                guard p.count == q.count, zip(p, q).allSatisfy({ $0.bitPattern == $1.bitPattern }) else { return false }
            default: return false
            }
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(clip.path)
        hasher.combine(clip.dur.bitPattern)
        hasher.combine(clip.lines.count)
        for l in clip.lines {
            hasher.combine(l.at.bitPattern)
            hasher.combine(l.text)
        }
    }
}
