// AudioPlayer.kt's calls (lines 27-120), as GameController.kt uses them: what plays a turn's audio.

/**
 * Plays a turn from the game's content: its clips and pauses one after another, and its beds underneath, each from
 * where it appears in the turn until the turn's audio ends ([TurnTimeline] lays it out). [position] says which clip
 * is playing and where, so the transcript can follow it. The app's TurnPlayer plays it on the device; tests use fakes.
 */
@MainActor
public protocol TurnPlaying: AnyObject, Sendable {
    /**
     * Called when a turn's audio has played to its end, once, and later than [play] (on the main actor), even for a
     * turn with nothing to play; never for a turn that was stopped. Beds fade out with a natural end.
     */
    var onFinished: (@MainActor @Sendable () -> Void)? { get set }

    /**
     * Called instead of [onFinished] when a turn's audio can't play at all (the audio engine won't start: a call has
     * the audio), once, later than [play]. The game then waits for a tap, as after an interruption (L2).
     */
    var onStalled: (@MainActor @Sendable () -> Void)? { get set }

    /// Plays a turn's steps (clips, pauses and beds; the engine has resolved the rest), stopping any turn playing.
    func play(_ steps: [Step])

    /// Stops the turn at once, beds and all, without calling [onFinished].
    func stop()

    /// The clip playing (its index among the turn's clips) and the seconds into it; nil in a pause or when idle.
    func position() -> ClipPosition?

    /// How many clips come before the item playing (for the transcript while a pause plays).
    func clipsDone() -> Int

    /// Lets go of the audio for good (the game closing).
    func release()
}

extension TurnPlaying {
    /// Cuts the voice short. As on Android this is [stop]: the controller then finishes the turn itself
    /// (GameController.skip), so [onFinished] isn't called for it.
    public func skip() { stop() }
}

/// What a game controller plays a game with besides the game: its saves, its audio and its listening. Tests give it
/// fakes.
public struct GameDependencies: Sendable {
    public let saves: any SaveStore
    public let audio: any TurnPlaying
    public let listener: any Listening

    public init(saves: any SaveStore, audio: any TurnPlaying, listener: any Listening) {
        self.saves = saves
        self.audio = audio
        self.listener = listener
    }
}
