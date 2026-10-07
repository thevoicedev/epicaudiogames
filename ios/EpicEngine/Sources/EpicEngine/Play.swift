// Play.kt and Session.kt's Turn, Heard and Saved: a game being played, as the app drives it.

/**
 * What the app does after each call: play [steps] in order, then wait for an answer to [ask], show the end screen
 * for [end], or leave the game ([quit]; with [keep], the place is kept). [visited] lists the nodes this turn went
 * through.
 */
public struct Turn: Equatable, Sendable {
    public let steps: [Step]
    public let ask: Ask?
    public let end: End?
    public let quit: Bool
    public let node: String
    public let visited: [String]
    public let heard: Heard?
    public let keep: Bool

    public init(
        steps: [Step], ask: Ask?, end: End?, quit: Bool, node: String, visited: [String], heard: Heard? = nil,
        keep: Bool = false
    ) {
        self.steps = steps
        self.ask = ask
        self.end = end
        self.quit = quit
        self.node = node
        self.visited = visited
        self.heard = heard
        self.keep = keep
    }
}

/// How an answer was understood: the index of the answer taken (nil: not understood) and why.
public struct Heard: Equatable, Sendable {
    public let said: String
    public let answer: Int?
    public let how: String

    public init(said: String, answer: Int?, how: String) {
        self.said = said
        self.answer = answer
        self.how = how
    }
}

/// What the app saves to pick a game up again. [ended]: at an end, or left with a plain quit.
public struct Saved: Equatable, Sendable {
    public let node: String
    public let vars: VarStore
    public let ended: Bool

    public init(node: String, vars: VarStore, ended: Bool) {
        self.node = node
        self.vars = vars
        self.ended = ended
    }
}

/**
 * A call the game can't take where the Kotlin engine throws IllegalStateException, IllegalArgumentException or
 * IndexOutOfBoundsException (an answer when no question is waiting, a next chapter that isn't there, an empty
 * random range). The app recovers from it instead of crashing (docs/IOS_PARITY.md, L1).
 */
public struct PlayError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/**
 * A game being played, as the app drives it: a map's [Session], or a game written in code (Nuclear War). Each call
 * returns the [Turn] to play next.
 */
public protocol Play: AnyObject {
    /// Speaker keys to the names shown in the transcript.
    var who: LinkedMap<String> { get }

    /// The question waiting for an answer, if there is one.
    var ask: Ask? { get }

    func start() throws -> Turn

    /// Whether a save can be picked up again: it waits at a question (or, in a map game, at a chapter end).
    func canResume(_ saved: Saved) -> Bool

    func resume(_ saved: Saved) throws -> Turn

    /// The game from a save (or from the start): picked up again where it can be, else started.
    func open(_ saved: Saved?) throws -> Turn

    func answer(_ said: String) throws -> Turn

    /// The player said nothing: the reprompt, and the same question again.
    func silence() throws -> Turn

    /// Starts again, at [at] (or the start).
    func restart(at: String?) throws -> Turn

    /// After a chapter's end: its next chapter.
    func nextChapter() throws -> Turn

    /// Whether a chapter end's next chapter is in this game (its pack installed).
    func hasChapter(_ next: String) -> Bool

    func save() -> Saved

    /// Whether the question takes this answer, or hears it as one that doesn't count ("I'm not sure", "of course
    /// not"): to choose among the recogniser's guesses.
    func understands(_ said: String) throws -> Bool
}

extension Play {
    public func open(_ saved: Saved?) throws -> Turn {
        if let saved, canResume(saved) { return try resume(saved) }
        return try start()
    }

    /// Starts again at the start (Kotlin's `restart()` with its default argument).
    public func restart() throws -> Turn { try restart(at: nil) }
}
