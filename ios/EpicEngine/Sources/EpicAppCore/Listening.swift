// Listener.kt: listening for one answer, as GameController.kt uses it.

/**
 * What a listener reports, on the main actor (Listener.kt's constructor callbacks): the words as they come
 * ([partial]); the recogniser's guesses, best first ([heard]; an empty list for speech it couldn't make out);
 * nobody speaking ([silence]); the sound level, 0 to 1 ([level]); listening not working here at all
 * ([unavailable]: answers are typed or tapped instead, and the mic button tries again); and passing trouble that says
 * nothing about the player ([trouble]: the mic couldn't start; the listen just ends, and the mic button tries again).
 */
public struct ListenerEvents: Sendable {
    public var partial: @MainActor @Sendable (String) -> Void
    public var heard: @MainActor @Sendable ([String]) -> Void
    public var silence: @MainActor @Sendable () -> Void
    public var level: @MainActor @Sendable (Float) -> Void
    public var unavailable: @MainActor @Sendable () -> Void
    public var trouble: @MainActor @Sendable () -> Void

    public init(
        partial: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        heard: @escaping @MainActor @Sendable ([String]) -> Void = { _ in },
        silence: @escaping @MainActor @Sendable () -> Void = {},
        level: @escaping @MainActor @Sendable (Float) -> Void = { _ in },
        unavailable: @escaping @MainActor @Sendable () -> Void = {},
        trouble: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.partial = partial
        self.heard = heard
        self.silence = silence
        self.level = level
        self.unavailable = unavailable
        self.trouble = trouble
    }
}

/// Listens for one answer with the device's speech recogniser, reporting through [events].
@MainActor
public protocol Listening: AnyObject, Sendable {
    var events: ListenerEvents { get set }

    /// Whether the device can recognise speech at all (Listener.available).
    var isAvailable: Bool { get }

    /// Listens for one answer; [hints] are words the question expects ([ListenHints]).
    func start(hints: [String])

    /// Stops listening, reporting nothing more.
    func stop()

    /// Lets go of the recogniser for good (the game closing).
    func release()
}

/// The words an answer is likely to have, to help the recogniser: the question's buttons and its answers' phrases.
public enum ListenHints {
    /// At most this many (SFSpeechRecognitionRequest.contextualStrings is meant for a short list).
    public static let limit = 100

    public static func of(_ ask: Ask?) -> [String] {
        guard let ask else { return [] }
        var out: [String] = []
        func add(_ s: String) {
            let t = Kt.trim(s)
            if !t.isEmpty && !out.contains(where: { Kt.utf16Equal($0, t) }) { out.append(t) }
        }
        for b in ask.buttons {
            add(b.label)
            add(b.value)
        }
        for a in ask.answers {
            switch a.match {
            case .yes(let extra), .no(let extra), .words(let extra): extra.forEach { add($0.text) }
            case .repeat, .seq, .digits, .re, .anyText: break
            }
        }
        return Array(out.prefix(limit))
    }
}
