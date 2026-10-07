// GoldenBots.kt's NuclearPlayer (lines 121-179): NuclearWarTest's player, made deterministic (README section 8.2).

import EpicEngine

/**
 * NuclearWarTest's player, copied: buttons, the extra words and silence, chosen by its own seeded Random; it leaves
 * and comes back once, at turn 37, with a new game on Random(seed + 37). README section 8.2 is this code in words.
 */
public final class NuclearPlayer {
    public struct Game: Sendable {
        /// How many turn lines (the start's included).
        public let lines: Int
        /// The last turn's end title.
        public let end: String

        public init(lines: Int, end: String) {
            self.lines = lines
            self.end = end
        }
    }

    public static let reopen = 37

    public static let extras = ["yes", "no", "yeah", "nope", "shield", "research", "all of them", "next", "next round",
        "none", "3", "two", "twenty", "repeat", "banana", "france", "the uk", "america", "china", "russia", "paris",
        "new york", "moscow", "london", "shanghai", "st petersburg", ""]

    private let audio: NuclearAudio

    public init(_ audio: NuclearAudio) { self.audio = audio }

    /// Kotlin's Random(seed) for an Int seed (Int arithmetic wraps, as Kotlin's does).
    static func random(_ seed: Int) -> XorWowRandom { XorWowRandom(seed: Int32(truncatingIfNeeded: seed)) }

    /// Game [seed]: each turn's line to [emit], and the save after it to [saves].
    @discardableResult
    public func game(
        _ seed: Int, encoder: Canon.Encoder = Canon.Encoder(), saves: (Saved) -> Void = { _ in },
        emit: (String) -> Void
    ) throws -> Game {
        var rnd = LoggingRandom(NuclearPlayer.random(seed))
        var game = NuclearWar(audio: audio, random: rnd)
        let r = NuclearPlayer.random(seed &* 7919 &+ 1)
        let lines = Canon.Turns.nuclear(encoder)
        var t = try game.start()
        func record(_ n: Int, _ input: CanonValue) {
            let saved = game.save()
            emit(lines.line(n, input, .list(rnd.take().map(\.canon)), t, saved))
            saves(saved)
        }
        record(0, ["start"])
        var n = 0
        var reopened = false
        while t.end == nil {
            n += 1
            guard n < (reopened ? 900 : 600) else {
                throw ConformanceError("game \(seed) went on for \(n) turns (at \(t.node))")
            }
            guard let ask = t.ask else { throw ConformanceError("game \(seed): no question and no end at \(t.node)") }
            guard !ask.reprompt.isEmpty else { throw ConformanceError("game \(seed): no reprompt at \(t.node)") }
            let input: CanonValue
            if !reopened && n % NuclearPlayer.reopen == 0 {
                // Leave and come back: the game is saved at every question.
                let saved = game.save()
                rnd = LoggingRandom(NuclearPlayer.random(seed &+ n))
                game = NuclearWar(audio: audio, random: rnd)
                guard game.canResume(saved) else {
                    throw ConformanceError("game \(seed): can't resume at \(saved.node)")
                }
                t = try game.open(saved)
                guard t.ask != nil else {
                    throw ConformanceError("game \(seed): nothing to answer after picking up at \(saved.node)")
                }
                reopened = true
                input = ["reopen"]
            } else {
                let buttons = ask.buttons
                let said: String?
                if try r.nextInt(until: 20) == 0 {
                    said = nil
                } else if try !buttons.isEmpty && r.nextInt(until: 10) < 7 {
                    said = buttons[try r.nextInt(until: buttons.count)].value
                } else {
                    said = NuclearPlayer.extras[try r.nextInt(until: NuclearPlayer.extras.count)]
                }
                if let said {
                    t = try game.answer(said)
                    input = ["answer", .string(said)]
                } else {
                    t = try game.silence()
                    input = ["silence"]
                }
            }
            record(n, input)
        }
        guard let end = t.end else { throw ConformanceError("game \(seed): no end") }
        return Game(lines: n + 1, end: end.title)
    }

    /// The game line before a game's turn lines (games.jsonl, dump mode).
    public static func gameLine(_ seed: Int, _ game: Game) -> String {
        Canon.json(.object([("seed", .int(seed)), ("turns", .int(game.lines)), ("end", .string(game.end))]))
    }
}

extension Canon.Turns {
    /**
     * Turn lines of a Nuclear War game (Canon.kt's `Turns(freshAsks = true)`): its questions are made afresh every
     * turn, so each one's hash is worked out from its answers, not looked up by the turn's node.
     */
    public static func nuclear(_ encoder: Canon.Encoder) -> Canon.Turns {
        Canon.Turns(encoder, askHash: { _, ask in encoder.askHash(ask) })
    }
}
