// No Kotlin counterpart: a turn "played" by the clock, from the clips' lengths in the map, with no sound.

import EpicAppCore
import Foundation

/**
 * Plays a turn silently, taking as long as its clips' `dur` and its pauses say, so the transcript follows it as it
 * would the voice. For the app without its audio player, and for previews.
 */
final class SilentTurnPlayer: TurnPlaying {
    var onFinished: (@MainActor @Sendable () -> Void)?
    var onStalled: (@MainActor @Sendable () -> Void)?
    private var timeline: TurnTimeline?
    private var started = ContinuousClock.now
    /// Bumped by every play and stop, so a finish meant for a turn that was stopped is let go.
    private var generation = 0
    private var finishing: Task<Void, Never>?

    func play(_ steps: [Step]) {
        stop()
        let t = TurnTimeline(steps: steps, sampleRate: 1000) { Int64(max($0.dur, 0) * 1000) }
        timeline = t
        started = .now
        let turn = generation
        finishing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(t.frames))
            guard let self, self.generation == turn else { return }
            self.timeline = nil
            self.onFinished?()
        }
    }

    func stop() {
        generation += 1
        finishing?.cancel()
        finishing = nil
        timeline = nil
    }

    func position() -> ClipPosition? { timeline?.position(at: elapsed) }

    func clipsDone() -> Int { timeline?.clipsDone(at: elapsed) ?? 0 }

    func release() { stop() }

    /// Milliseconds since the turn started (the timeline's frames).
    private var elapsed: Int64 {
        let d = ContinuousClock.now - started
        return d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000
    }
}
