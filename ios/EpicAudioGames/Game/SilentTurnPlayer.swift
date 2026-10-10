// No Kotlin counterpart: a turn "played" by the clock, from the clips' lengths in the map, with no sound.

import EpicAppCore
import Foundation

/**
 * Plays a turn silently, taking as long as its clips' `dur` and its pauses say, so the transcript follows it as it
 * would the voice. For the app without its audio player, and for previews. At a voice speed other than 1 its clock
 * runs that much faster or slower, as TurnPlayer's audio does: [position] stays in the turn's own time.
 */
final class SilentTurnPlayer: TurnPlaying {
    var onFinished: (@MainActor @Sendable () -> Void)?
    var onStalled: (@MainActor @Sendable () -> Void)?
    /// The voice speed (Settings › Sound and voice), for the turns played from now on.
    var speed: Double = 1
    private var timeline: TurnTimeline?
    private var started = ContinuousClock.now
    /// The turn playing's speed.
    private var rate: Double = 1
    /// Bumped by every play and stop, so a finish meant for a turn that was stopped is let go.
    private var generation = 0
    private var finishing: Task<Void, Never>?

    func play(_ steps: [Step]) {
        stop()
        let t = TurnTimeline(steps: steps, sampleRate: 1000) { Int64(max($0.dur, 0) * 1000) }
        timeline = t
        started = .now
        rate = speed > 0 ? speed : 1
        let turn = generation
        let length = Duration.milliseconds(Double(t.frames) / rate)
        finishing = Task { [weak self] in
            try? await Task.sleep(for: length)
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

    /// The turn's own milliseconds since it started (the timeline's frames): the time gone, at the turn's speed.
    private var elapsed: Int64 {
        let d = ContinuousClock.now - started
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        return Int64(ms * rate)
    }
}
