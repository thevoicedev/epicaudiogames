// GoldenBots.kt's MapWalker: MapsTest's random walk, made deterministic (fixtures/engine/README.md, section 8.1).

import EpicEngine

/**
 * MapsTest's random walk, made deterministic: each walk has its own seeded Random, shared by the bot and the
 * session's choices. It leaves and comes back every [reopen] turns, comes back after quitting, and with [entries]
 * (the chapter ends that lead into a pack) every odd walk starts at one of them.
 */
public final class MapWalker {
    public static let turns = 80
    public static let reopen = 25

    public static func seed(_ w: Int) -> Int { w + 1 }

    private let map: GameMap
    private let entries: [String]

    public init(_ map: GameMap, entries: [String] = []) {
        self.map = map
        self.entries = entries
    }

    /// Walk [w]: each turn's line to [emit] (and the turn to [onTurn]); returns how many lines.
    @discardableResult
    public func walk(
        _ w: Int, encoder: Canon.Encoder = Canon.Encoder(), onTurn: (Turn) -> Void = { _ in },
        emit: (String) -> Void
    ) throws -> Int {
        let rng = XorWowRandom(seed: Int32(MapWalker.seed(w)))
        let choose = LoggingChooser(rng)
        let lines = Canon.Turns(encoder)
        func session() -> Session { Session(map, choose: { try choose($0) }) }
        var s = session()
        var n = 0
        func record(_ input: CanonValue, _ t: Turn) throws {
            if !t.quit && t.end == nil && t.ask == nil {
                throw ConformanceError("\(map.id): a turn at \(t.node) neither asks, ends nor quits")
            }
            onTurn(t)
            emit(lines.line(n, input, choose.take(), t, s.save()))
            n += 1
        }
        let entry = !entries.isEmpty && w % 2 == 1 ? entries[(w / 2) % entries.count] : nil
        var t: Turn
        if let entry {
            // Back at a saved chapter end, as when a pack has just been bought there.
            t = try s.resume(Saved(node: entry, vars: VarStore(), ended: true))
            try record(["resume", .string(entry)], t)
        } else {
            t = try s.start()
            try record(["start"], t)
        }
        var last: String?
        for i in 0..<MapWalker.turns {
            let input: CanonValue
            if t.quit {
                // The app stores the save after a quit too (GameController.kt finishTurn): a "leave" picks up
                // again, a plain quit starts again with the map's "keep" variables.
                let saved = s.save()
                s = session()
                t = try s.open(saved)
                input = ["return"]
            } else if (i + 1) % MapWalker.reopen == 0 {
                // Leave and come back: the game as the app opens it again (Session.open).
                let saved = s.save()
                s = session()
                t = try s.open(saved)
                input = ["reopen"]
            } else if let end = t.end {
                if end.kind == "chapter", let next = end.next, map.nodes.contains(next) {
                    t = try s.nextChapter()
                    input = ["next"]
                } else {
                    let at = end.kind == "gameover" ? end.retry : nil
                    t = try s.restart(at: at)
                    input = ["restart", .opt(at)]
                }
            } else {
                guard let ask = t.ask else { throw ConformanceError("\(map.id): no question at \(t.node)") }
                let options = try inputs(ask)
                let rest = Array(options.dropFirst(3))
                let taken = rest.isEmpty ? options : rest     // inputs() lists silence, nonsense, repeat first
                let said: String?
                if try w % 2 == 1 && options.contains(where: { MapWalker.same($0, last) }) && rng.nextBoolean() {
                    said = last
                } else if try rng.nextInt(until: 4) > 0 {
                    said = taken[try rng.nextInt(until: taken.count)]
                } else {
                    said = options[try rng.nextInt(until: options.count)]
                }
                last = said
                if let said {
                    t = try s.answer(said)
                    input = ["answer", .string(said)]
                } else {
                    t = try s.silence()
                    input = ["silence"]
                }
            }
            try record(input, t)
        }
        return n
    }

    /// Kotlin's == on String?: UTF-16 unit by unit.
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): Kt.utf16Equal(x, y)
        default: false
        }
    }

    /// One answer of each kind the question takes, its buttons, nonsense, "repeat" and silence (nil).
    public func inputs(_ ask: Ask) throws -> [String?] {
        guard let repeatWord = map.words.repeat.first?.text else {
            throw ConformanceError("\(map.id): no repeat words")
        }
        var out: [String?] = [nil, "zzz", repeatWord]
        out += ask.buttons.map(\.value)
        for a in ask.answers {
            switch a.match {
            case .yes: out.append("yes")
            case .no: out.append("no")
            case .words(let phrases):
                guard let p = phrases.first else { throw ConformanceError("\(map.id): an answer with no words") }
                out.append(p.text)
            case .repeat: out.append(repeatWord)
            case .seq(let seq, let table, _, _, _):
                let words = try seq.utf16.map { c -> String in
                    let symbol = String(decoding: [c], as: UTF16.self)
                    guard let word = map.symbols[table]?[symbol]?.first else {
                        throw ConformanceError("\(map.id): no word for \(symbol) in the symbol table \(table)")
                    }
                    return word
                }
                out.append(words.joined(separator: " "))
            case .digits(let digits, _, _):
                out.append(digits.utf16.map { String(decoding: [$0], as: UTF16.self) }.joined(separator: " "))
            case .re: continue
            case .anyText: out.append("something else entirely")
            }
        }
        // Null and the non-blank strings, each once, in first-seen order (Kotlin's distinct()).
        var seen = Set<[UInt16]>()
        var sawNil = false
        return out.filter { s in
            guard let s else {
                defer { sawNil = true }
                return !sawNil
            }
            if s.utf16.allSatisfy(Kt.isWhitespace) { return false }
            return seen.insert(Array(s.utf16)).inserted
        }
    }
}
