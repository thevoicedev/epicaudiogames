// The parts of a game map (GameMap.kt): lines, steps, gos, set values, phrases, matches, answers, questions, nodes.

import Foundation

/**
 * A map that can't be read or played: Kotlin's MapException, with the same message ([Kind.map]). Where the Kotlin
 * engine fails with another exception instead (bad JSON, an object where text should be, a number that isn't an
 * Int, a bad regular expression), the kind is [Kind.other] and only the failure itself is meant to match.
 */
public struct MapError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        /// Kotlin throws MapException with this message.
        case map
        /// Kotlin throws some other exception.
        case other
    }

    public let message: String
    public let kind: Kind

    public init(_ message: String, kind: Kind = .map) {
        self.message = message
        self.kind = kind
    }

    public static func other(_ message: String) -> MapError { MapError(message, kind: .other) }

    public var description: String { message }
}

/**
 * One spoken line of a clip's transcript: when it starts, how long it takes, who says it and what. [more]: the
 * sentence carries on in the next clip (a list said a name at a time), so the transcript shows them as one line.
 */
public struct Line: Equatable, Sendable {
    public let at: Double
    public let len: Double
    public let who: String
    public let text: String
    public let words: [Double]?
    public let more: Bool

    public init(at: Double, len: Double, who: String, text: String, words: [Double]? = nil, more: Bool = false) {
        self.at = at
        self.len = len
        self.who = who
        self.text = text
        self.words = words
        self.more = more
    }
}

/**
 * A clip of the game's audio (Kotlin's Step.Play): path relative to the game's content folder, without an
 * extension. [sfx]: music or sound effects, with no transcript.
 */
public struct Clip: Equatable, Sendable {
    public let path: String
    public let dur: Double
    public let lines: [Line]
    public let sfx: Bool

    public init(path: String, dur: Double, lines: [Line], sfx: Bool = false) {
        self.path = path
        self.dur = dur
        self.lines = lines
        self.sfx = sfx
    }
}

public enum Step: Equatable, Sendable {
    case play(Clip)

    /// A number variable, read out with the shared number clips.
    case num(String)

    case pause(Double)

    /**
     * A sound under the rest of the turn (music, or an effect that overlaps what follows): it starts here, plays
     * once at [volume] (0 to 1), and stops when the turn's audio ends. A [path] of nil stops every bed.
     */
    case bed(path: String?, volume: Double, dur: Double)

    /// The steps play only when the condition holds (when the turn is played).
    case when(Condition, [Step])

    /// One of these step lists, at random.
    case pick([[Step]])

    /// The steps for a variable's value ("10", "hide", "true"), or [otherwise].
    case by(variable: String, cases: LinkedMap<[Step]>, otherwise: [Step])
}

/// Where a map goes next. Equality is Kotlin's data class equality: node and deck names compare UTF-16 unit by unit.
public indirect enum Go: Equatable, Sendable {
    case to(String)
    case random([Go])
    case `if`([GoCase], otherwise: Go)
    case restart(String)
    case quit

    /// Leave the game for now, keeping the player's place: the question just answered, asked again on return.
    case leave

    /**
     * One of [nodes] that this [deck] hasn't drawn yet, at random; when all have been drawn, the deck starts again.
     * The deck's draws are kept in the variable "deck_<deck>".
     */
    case draw(nodes: [String], deck: String)

    public static func == (a: Go, b: Go) -> Bool {
        switch (a, b) {
        case let (.to(x), .to(y)), let (.restart(x), .restart(y)): Kt.utf16Equal(x, y)
        case let (.random(x), .random(y)): x == y
        case let (.if(c1, o1), .if(c2, o2)): c1 == c2 && o1 == o2
        case (.quit, .quit), (.leave, .leave): true
        case let (.draw(n1, d1), .draw(n2, d2)):
            n1.count == n2.count && zip(n1, n2).allSatisfy { Kt.utf16Equal($0, $1) } && Kt.utf16Equal(d1, d2)
        default: false
        }
    }
}

/// A condition and where it goes (Kotlin's Pair<Condition, Go>).
public struct GoCase: Equatable, Sendable {
    public let cond: Condition
    public let go: Go

    public init(_ cond: Condition, _ go: Go) {
        self.cond = cond
        self.go = go
    }
}

public enum SetValue: Sendable {
    case assign(Value)
    case add(Double)
    case rand(from: Int32, to: Int32)
    /// A computed value: "=streak * 10".
    case calc(Expr)
}

extension SetValue: Equatable {
    // Kotlin's data class equality: Doubles compare bit for bit.
    public static func == (a: SetValue, b: SetValue) -> Bool {
        switch (a, b) {
        case let (.assign(x), .assign(y)): x == y
        case let (.add(x), .add(y)): Value.number(x) == Value.number(y)
        case let (.rand(f1, t1), .rand(f2, t2)): f1 == f2 && t1 == t2
        case let (.calc(x), .calc(y)): x == y
        default: false
        }
    }
}

/// The variables an answer, an else or a node sets, in the order they're applied.
public typealias SetList = LinkedMap<SetValue>

/// A phrase to listen for, normalised. An exact phrase ("=fine" in a map) must be the whole answer.
public struct Phrase: Equatable, Hashable, Sendable {
    public let text: String
    public let exact: Bool

    public init(_ text: String, _ exact: Bool) {
        self.text = text
        self.exact = exact
    }
}

/**
 * A compiled regular expression that compares by its pattern, as Kotlin's Match.Re does. ICU (NSRegularExpression)
 * and java.util.regex read the same simple patterns the same way; MapRegexTests keeps every map's "re" answers to
 * those (no POSIX or Unicode classes, class set operations or inline flags).
 */
public struct RegexBox: Equatable, Sendable {
    public let pattern: String
    private let regex: NSRegularExpression

    /// A bad pattern fails as Kotlin's PatternSyntaxException does (a MapError of kind other).
    public init(_ pattern: String) throws {
        self.pattern = pattern
        regex = try RegexCache.shared.regex(pattern)
    }

    /// Kotlin's Regex.containsMatchIn.
    public func containsMatch(in text: String) throws -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    public static func == (a: RegexBox, b: RegexBox) -> Bool { Kt.utf16Equal(a.pattern, b.pattern) }
}

/**
 * Compiled patterns, shared: maps and Nuclear War build the same ones again and again. Keyed by the pattern's exact
 * text: ICU matches code points, so "[ñ]" written precomposed and decomposed are different patterns.
 */
final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private let lock = NSLock()
    private var compiled: [ExactKey: NSRegularExpression] = [:]

    func regex(_ pattern: String) throws -> NSRegularExpression {
        lock.lock()
        defer { lock.unlock() }
        if let r = compiled[ExactKey(pattern)] { return r }
        do {
            // No options: ICU's simple word boundaries, as java.util.regex has.
            let r = try NSRegularExpression(pattern: pattern)
            compiled[ExactKey(pattern)] = r
            return r
        } catch {
            throw MapError.other("can't compile the regular expression \(pattern)")
        }
    }
}

public enum Match: Equatable, Sendable {
    case yes(extra: [Phrase])
    case no(extra: [Phrase])
    case words([Phrase])
    case `repeat`
    case seq(seq: String, table: String, exact: Bool, spelled: Bool, least: Int?)
    case digits(digits: String, exact: Bool, least: Int?)
    case re(RegexBox)
    case anyText

    /// Kotlin's class name, lower case, as the Matcher's "how" says it.
    public var kotlinName: String {
        switch self {
        case .yes: "yes"
        case .no: "no"
        case .words: "words"
        case .repeat: "repeat"
        case .seq: "seq"
        case .digits: "digits"
        case .re: "re"
        case .anyText: "anytext"
        }
    }
}

public struct Answer: Equatable, Sendable {
    public let match: Match
    public let go: Go?
    public let set: SetList
    public let whenCond: Condition?
    public let opposite: Int?
    /// Answers of a higher rank are tried first (default 0).
    public let rank: Int

    public init(match: Match, go: Go?, set: SetList, whenCond: Condition?, opposite: Int?, rank: Int = 0) {
        self.match = match
        self.go = go
        self.set = set
        self.whenCond = whenCond
        self.opposite = opposite
        self.rank = rank
    }
}

/// An answer button (Kotlin's Button): tapping it sends [value].
public struct AnswerButton: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct Else: Equatable, Sendable {
    public let say: [Step]
    public let set: SetList
    public let go: Go?

    public init(say: [Step], set: SetList, go: Go?) {
        self.say = say
        self.set = set
        self.go = go
    }
}

public struct Ask: Equatable, Sendable {
    public let reprompt: [Step]
    public let answers: [Answer]
    public let otherwise: Else?
    public let buttons: [AnswerButton]

    public init(reprompt: [Step], answers: [Answer], otherwise: Else?, buttons: [AnswerButton]) {
        self.reprompt = reprompt
        self.answers = answers
        self.otherwise = otherwise
        self.buttons = buttons
    }
}

public struct End: Equatable, Sendable {
    public let kind: String
    public let title: String
    public let next: String?
    public let retry: String?
    public let locked: String?

    public init(kind: String, title: String, next: String?, retry: String?, locked: String?) {
        self.kind = kind
        self.title = title
        self.next = next
        self.retry = retry
        self.locked = locked
    }
}

public struct Node: Equatable, Sendable {
    public let id: String
    public let redirect: [GoCase]
    public let set: SetList
    public let say: [Step]
    public let ask: Ask?
    public let go: Go?
    public let end: End?

    public init(id: String, redirect: [GoCase], set: SetList, say: [Step], ask: Ask?, go: Go?, end: End?) {
        self.id = id
        self.redirect = redirect
        self.set = set
        self.say = say
        self.ask = ask
        self.go = go
        self.end = end
    }
}

/// [mixed]: answers made only of these yes words, no words and fillers count as their last yes or no word.
public struct Mixed: Equatable, Sendable {
    public let yes: [String]
    public let no: [String]
    public let filler: [String]

    public init(yes: [String], no: [String], filler: [String]) {
        self.yes = yes
        self.no = no
        self.filler = filler
    }
}

public struct WordLists: Equatable, Sendable {
    public let yes: [Phrase]
    public let no: [Phrase]
    public let `repeat`: [Phrase]
    public let mixed: Mixed?

    public init(yes: [Phrase], no: [Phrase], repeat: [Phrase], mixed: Mixed? = nil) {
        self.yes = yes
        self.no = no
        self.repeat = `repeat`
        self.mixed = mixed
    }
}
