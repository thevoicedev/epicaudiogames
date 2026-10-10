// SilentTurnPlayer.swift: a turn played by the clock, at the voice speed, as TurnPlayer plays it with its sound.

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The silent player's clock at the voice speed: the position in the turn's own time, the turn over in its length over
 * the speed. Each position is checked against the least and the most time that can have gone since its turn began:
 * from the latest it can have begun (play() returned) to just before it's asked, and from the earliest (play() called)
 * to just after, so a test machine slow to run the test, or play() itself, can't make it fail.
 */
@MainActor
struct SilentTurnPlayerTests {
    /// 12 s of the turn's own time: a long clip, a pause and a clip.
    let long: [Step] = [
        .play(Clip(path: "a", dur: 10, lines: [])), .pause(0.5), .play(Clip(path: "b", dur: 1.5, lines: [])),
    ]
    /// 8 s: a clip and a pause.
    let eight: [Step] = [.play(Clip(path: "a", dur: 7.5, lines: [])), .pause(0.5)]

    @Test func atTwiceTheSpeedItsClockRunsTwiceAsFast() async throws {
        let player = SilentTurnPlayer()
        defer { player.release() }
        player.speed = 2
        let turn = play(long, on: player)
        try await Task.sleep(for: .milliseconds(200))
        let (p, least, most) = try position(player, turn)
        #expect(p.clip == 0)
        #expect(p.seconds >= 2 * least - 0.01 && p.seconds <= 2 * most + 0.01,
                "\(p.seconds) s into the clip, \(least) to \(most) s after it began")
    }

    @Test func atTwiceTheSpeedATurnIsOverInHalfItsTime() async throws {
        let player = SilentTurnPlayer()
        let finished = FinishCounter()
        player.onFinished = { finished.count += 1 }
        player.speed = 2
        let start = ContinuousClock.now
        player.play(eight)
        for _ in 0..<1_000 where finished.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let took = ContinuousClock.now - start
        #expect(finished.count == 1)
        #expect(took >= .milliseconds(3_995), "finished after \(took)")
        #expect(took < .milliseconds(6_500), "finished after \(took): not in half the turn's 8 s")
        #expect(player.position() == nil)
    }

    /// A speed set while a turn plays is for the turns after it.
    @Test func aNewSpeedIsForTheTurnsAfterIt() async throws {
        let player = SilentTurnPlayer()
        defer { player.release() }
        var turn = play(long, on: player)
        player.speed = 2
        try await Task.sleep(for: .milliseconds(100))
        let (p, _, most) = try position(player, turn)
        #expect(p.seconds <= most + 0.01, "\(p.seconds) s in after \(most) s: the turn playing sped up")
        turn = play(long, on: player)
        try await Task.sleep(for: .milliseconds(100))
        let (q, least, _) = try position(player, turn)
        #expect(q.seconds >= 2 * least - 0.01, "\(q.seconds) s in after \(least) s: not twice as fast")
    }

    /// Plays [steps] on [player]: when its turn began, at the earliest (play() called) and the latest (play() returned).
    private func play(_ steps: [Step], on player: SilentTurnPlayer)
        -> (early: ContinuousClock.Instant, late: ContinuousClock.Instant) {
        let early = ContinuousClock.now
        player.play(steps)
        return (early, ContinuousClock.now)
    }

    /// Where [player] is, and the least and most seconds gone since its [turn] began, as it's asked.
    private func position(
        _ player: SilentTurnPlayer, _ turn: (early: ContinuousClock.Instant, late: ContinuousClock.Instant)
    ) throws -> (ClipPosition, Double, Double) {
        let least = seconds(ContinuousClock.now - turn.late)
        let p = try #require(player.position())
        let most = seconds(ContinuousClock.now - turn.early)
        return (p, least, most)
    }

    private func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}
