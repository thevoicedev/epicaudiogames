// Listener.kt's recogniser endpointing and onError (lines 53-84): when an answer is over, and what an error means.

/**
 * When listening for one answer is over. Android's recogniser decides that itself; iOS's goes on listening until it
 * is told the audio has ended, so the listener asks this on every tick (and tells it each partial result):
 * - no words for [noSpeech]: a silence, as Android's ERROR_SPEECH_TIMEOUT is;
 * - words that haven't changed for [settle], or listening for [cap]: the answer is over, and the recogniser is
 *   told so ([Decision.endAudio]); its final result comes next;
 * - no final result [finalWait] after that: the last words heard are the answer (or, with none, a silence).
 */
public struct Endpointer: Sendable {
    public static let noSpeech: Duration = .seconds(6)
    public static let settle: Duration = .milliseconds(1200)
    public static let cap: Duration = .seconds(20)
    public static let finalWait: Duration = .seconds(3)

    public enum Decision: Equatable, Sendable {
        case wait
        /// Nobody spoke.
        case silence
        /// The words have stopped: the recogniser is to finish (SFSpeechAudioBufferRecognitionRequest.endAudio).
        case endAudio
        /// The recogniser never finished: the last words are the answer.
        case giveUp
    }

    private let started: ContinuousClock.Instant
    private var changed: ContinuousClock.Instant?
    private var ended: ContinuousClock.Instant?
    private var done = false
    /// The words heard so far (the latest partial result).
    public private(set) var words = ""

    public init(at now: ContinuousClock.Instant) {
        started = now
    }

    /// The recogniser's words so far.
    public mutating func partial(_ text: String, at now: ContinuousClock.Instant) {
        let t = Kt.trim(text)
        if t.isEmpty || t == words { return }
        words = t
        changed = now
    }

    /// What to do now. Each decision but [Decision.wait] is given once.
    public mutating func tick(at now: ContinuousClock.Instant) -> Decision {
        if done { return .wait }
        if let ended {
            if now - ended < Self.finalWait { return .wait }
            done = true
            return .giveUp
        }
        guard let changed else {
            if now - started < Self.noSpeech { return .wait }
            done = true
            return .silence
        }
        if now - changed < Self.settle && now - started < Self.cap { return .wait }
        ended = now
        return .endAudio
    }

    /// The recogniser has been told the audio has ended.
    public var endingAudio: Bool { ended != nil && !done }
}

/// What a listen came to, for the game (Listener.kt's callbacks).
public enum ListenOutcome: Equatable, Sendable {
    /// The recogniser's guesses, best first; none for speech it couldn't make out (Android's ERROR_NO_MATCH).
    case heard([String])
    /// Nobody answered (Android's ERROR_SPEECH_TIMEOUT, and the errors it doesn't tell apart).
    case silence
    /// Listening can't work here: answers are typed or tapped instead, and the mic button tries again.
    case unavailable
    /// Passing trouble that says nothing about the player (Android's busy recogniser, or the mic in use): the listen
    /// just ends, with no silence counted; the mic button listens again.
    case trouble
    /// Nothing to report: a cancellation (the game stopped listening), or trouble that followed an interruption or a
    /// route change while listening (the game pauses for those itself). Never makes the mic unavailable.
    case ignore
}

extension Endpointer {
    /// SFSpeechRecognizer's error domains and the codes the app tells apart.
    public enum ErrorCode {
        public static let assistantDomain = "kAFAssistantErrorDomain"
        public static let localDomain = "kLSRErrorDomain"
        public static let speechDomain = "SFSpeechErrorDomain"
        public static let urlDomain = "NSURLErrorDomain"
        /// kAFAssistantErrorDomain: no speech detected.
        public static let noSpeech = 1110
        /// kAFAssistantErrorDomain: the task was cancelled.
        public static let cancelled = 216
        /// kLSRErrorDomain: the request was cancelled.
        public static let requestCancelled = 301
        /// kLSRErrorDomain: no recogniser assets for the language, Siri and Dictation turned off, or no recogniser.
        public static let unavailableLocal: Set<Int> = [102, 201, 300]
    }

    /**
     * What an error from the recogniser means (Listener.kt's onError). [onDevice]: recognition runs on the device (a
     * network error then can't happen). [interrupted]: the audio session was interrupted or its route changed while
     * listening. [words]: what was heard before the error, once the recogniser was told the audio had ended.
     */
    public static func outcome(
        domain: String, code: Int, onDevice: Bool, interrupted: Bool, words: String? = nil
    ) -> ListenOutcome {
        if domain == ErrorCode.assistantDomain && code == ErrorCode.cancelled { return .ignore }
        if domain == ErrorCode.localDomain && code == ErrorCode.requestCancelled { return .ignore }
        if interrupted { return .ignore }
        if let words, !Kt.trim(words).isEmpty { return .heard([Kt.trim(words)]) }
        if domain == ErrorCode.localDomain && ErrorCode.unavailableLocal.contains(code) { return .unavailable }
        // A recogniser on a server, with no network: answers are typed or tapped (Android's ERROR_NETWORK).
        if domain == ErrorCode.urlDomain && !onDevice { return .unavailable }
        return .silence
    }

    /**
     * What the recogniser's final result means: its guesses; none, after words came while listening, is speech it
     * couldn't make out (Android's ERROR_NO_MATCH); none and no words at all is a silence, as Listener.kt reads a
     * NO_MATCH with no partial words (some recognisers end a silent listen so).
     */
    public static func outcome(final guesses: [String], words: String) -> ListenOutcome {
        if !guesses.isEmpty { return .heard(guesses) }
        return Kt.trim(words).isEmpty ? .silence : .heard([])
    }
}
