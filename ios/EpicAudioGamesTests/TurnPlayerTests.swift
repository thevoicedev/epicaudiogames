// AudioPlayer.kt's onFinished and its `playing` guard: a turn finishes once, later than play(), never after a stop.

import AVFoundation
import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * TurnPlayer on the device's engine (the simulator's output, in real time), with short clips of a quiet constant
 * level. GameController counts on these: onFinished comes once per turn played to its end, after play() returns;
 * never for a turn that was stopped or replaced, however its nodes' handlers come back (stopping a node calls every
 * one of them).
 */
@MainActor
@Suite(.serialized)
struct TurnPlayerTests {
    let content: LevelClips
    let player: TurnPlayer
    let finished = FinishCounter()

    /// 0.45 s: a bed, a clip, a pause and a clip.
    let turn: [Step] = [.bed(path: "bed", volume: 0.5, dur: 2), .play(Clip(path: "a", dur: 0.15, lines: [])),
                        .pause(0.1), .play(Clip(path: "b", dur: 0.2, lines: []))]

    init() throws {
        content = try LevelClips()
        try content.clip("a", level: 0.02, seconds: 0.15)
        try content.clip("b", level: 0.03, seconds: 0.2)
        try content.clip("bed", level: 0.01, seconds: 2)
        player = TurnPlayer(resolver: content.resolver, cache: DecodedClipCache())
        let finished = finished
        player.onFinished = { finished.count += 1 }
    }

    @Test func anEmptyTurnFinishesOnceAfterPlayReturns() async throws {
        defer { player.release() }
        player.play([])
        #expect(finished.count == 0)        // handler.post: not from inside play()
        #expect(await wait { finished.count == 1 })
        player.play([.num("score"), .pause(0), .bed(path: "bed", volume: 1, dur: 2)])
        #expect(finished.count == 1)
        #expect(await wait { finished.count == 2 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(finished.count == 2)
        #expect(player.position() == nil)
    }

    /// L5: a clip with no file takes no time; a turn of nothing else finishes at once.
    @Test func aTurnOfMissingClipsFinishes() async throws {
        defer { player.release() }
        player.play([.play(Clip(path: "nowhere", dur: 3, lines: [])), .bed(path: "nor-here", volume: 1, dur: 1)])
        #expect(finished.count == 0)
        #expect(await wait { finished.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(finished.count == 1)
    }

    @Test func aTurnFinishesOnceWhenItsAudioHasPlayed() async throws {
        defer { player.release() }
        let start = ContinuousClock.now
        player.play(turn)
        #expect(player.position() == ClipPosition(clip: 0, seconds: 0))     // as soon as it's playing
        #expect(await wait { finished.count == 1 })
        let took = ContinuousClock.now - start
        #expect(took >= .milliseconds(400), "finished after \(took)")
        #expect(took < .seconds(3))
        try await Task.sleep(for: .milliseconds(400))
        #expect(finished.count == 1)
        #expect(player.position() == nil)
        // Played to its end, the playlist stays on its last item: one clip before it.
        #expect(player.clipsDone() == 1)
    }

    @Test func positionFollowsTheVoiceThroughAPause() async throws {
        defer { player.release() }
        player.play([.play(Clip(path: "a", dur: 0.15, lines: [])), .pause(0.3),
                     .play(Clip(path: "b", dur: 0.2, lines: []))])
        var clips: [Int] = []
        var pauseAfter: [Int] = []
        while finished.count == 0 {
            if let p = player.position() {
                if clips.last != p.clip { clips.append(p.clip) }
                #expect(p.seconds >= 0 && p.seconds < 0.21)
            } else {
                pauseAfter.append(player.clipsDone())
            }
            try await Task.sleep(for: .milliseconds(10))
            if clips.count > 50 { break }
        }
        #expect(clips == [0, 1])
        #expect(pauseAfter.contains(1), "the pause wasn't seen: \(pauseAfter)")
        #expect(!pauseAfter.contains(0))
    }

    @Test func aStoppedTurnNeverFinishes() async throws {
        defer { player.release() }
        player.play(turn)
        player.stop()                    // while its files are opened
        try await Task.sleep(for: .milliseconds(700))
        #expect(finished.count == 0)
        player.play(turn)
        #expect(await wait { player.position().map { $0.clip == 0 && $0.seconds > 0 } ?? false })
        player.stop()                    // while it plays: the nodes call their handlers
        #expect(player.position() == nil)
        #expect(player.clipsDone() == 0)
        player.play(turn)
        try await Task.sleep(for: .milliseconds(380))
        player.skip()                    // in its last clip
        try await Task.sleep(for: .milliseconds(700))
        #expect(finished.count == 0)
    }

    /// 100 answers and skips in a row, some while the turn's files open, some while it plays: only the turn left
    /// to play finishes, once.
    @Test func rapidPlaysAndStopsFinishOnlyTheLastTurnOnce() async throws {
        defer { player.release() }
        for i in 0..<100 {
            player.play(i % 10 == 5 ? [] : turn)
            if i % 4 == 0 { try await Task.sleep(for: .milliseconds(5 * (i % 7))) }
            if i % 3 != 0 { player.stop() }          // else the next play() replaces it
            #expect(finished.count == 0, "turn \(i)")
        }
        player.play(turn)
        #expect(await wait { finished.count == 1 })
        try await Task.sleep(for: .milliseconds(700))
        #expect(finished.count == 1)
    }

    @Test func aTurnReplacedWhilePlayingNeverFinishes() async throws {
        defer { player.release() }
        player.play(turn)
        try await Task.sleep(for: .milliseconds(150))
        player.play([.play(Clip(path: "a", dur: 0.15, lines: []))])
        #expect(await wait { finished.count == 1 })
        try await Task.sleep(for: .milliseconds(600))
        #expect(finished.count == 1)
    }

    @Test func releaseLetsGoOfTheEngine() async throws {
        player.play(turn)
        #expect(await wait { player.engine?.isRunning == true })
        player.release()
        #expect(player.engine == nil)
        try await Task.sleep(for: .milliseconds(700))
        #expect(finished.count == 0)
    }

    /// The game's session: active for a turn, then let go once its engine has stopped (else "busy").
    @Test func theSessionPlaysAndLetsGo() async throws {
        defer { player.release() }
        let session = AudioSessionController { _ in }
        try session.activate()
        #expect(AVAudioSession.sharedInstance().category == .playAndRecord)
        #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.defaultToSpeaker))
        player.play(turn)
        #expect(await wait { finished.count == 1 })
        let engine = try #require(player.engine)
        #expect(engine.isRunning)
        #expect(session.deactivate(stopping: [engine]))
        #expect(!engine.isRunning)
        // The next turn starts the engine again.
        try session.activate()
        player.play(turn)
        #expect(await wait { finished.count == 2 })
        #expect(session.deactivate(stopping: [engine]))
    }

    /// L2: a turn whose engine won't start (a call has the audio) stalls: the game is told, and no finish comes.
    @Test func aTurnThatCantStartStalls() async throws {
        defer { player.release() }
        let stalled = FinishCounter()
        player.onStalled = { stalled.count += 1 }
        player.startEngine = { _ in throw NSError(domain: NSOSStatusErrorDomain, code: 560_557_684) }
        player.play(turn)
        #expect(await wait { stalled.count == 1 })
        try await Task.sleep(for: .milliseconds(600))
        #expect(finished.count == 0)
        #expect(stalled.count == 1)
        #expect(player.position() == nil)
        // Once the audio can play again, the next turn does.
        player.startEngine = { try $0.start() }
        player.play(turn)
        #expect(await wait { finished.count == 1 })
        #expect(stalled.count == 1)
    }

    /// ExoPlayer's position holds where the voice stopped: the engine stopping under a turn (before the game hears
    /// of it) leaves the highlight where it was, rather than at the turn's first line.
    @Test func thePositionHoldsWhenTheEngineStops() async throws {
        defer { player.release() }
        player.play([.play(Clip(path: "bed", dur: 2, lines: []))])
        #expect(await wait { (player.position()?.seconds ?? 0) > 0.3 })
        let before = try #require(player.position())
        player.engine?.stop()
        let after = try #require(player.position())
        #expect(after.clip == before.clip)
        #expect(after.seconds >= before.seconds)
        #expect(after.seconds > 0.3)
    }

    /// AudioPlayer.fadeOutBeds: a bed still playing at the turn's end fades out over 150 ms, and neither a stop (an
    /// answer tapped just then) nor the next turn cuts it; the game closing lets it finish too.
    @Test func aBedFadingOutIsntCut() async throws {
        defer { player.release() }
        player.play([.bed(path: "bed", volume: 1, dur: 2), .play(Clip(path: "a", dur: 0.15, lines: []))])
        #expect(await wait { finished.count == 1 })
        let fading = player.fading
        #expect(fading.count == 1)
        let graph = try #require(player.graph)
        #expect(player.tail != nil)
        player.stop()
        #expect(fading.allSatisfy { graph.beds[$0].isPlaying })
        player.play(turn)                // its bed goes on another node
        #expect(fading.allSatisfy { graph.beds[$0].isPlaying })
        #expect(await wait(.seconds(2)) { player.fading.isEmpty })
        #expect(fading.allSatisfy { !graph.beds[$0].isPlaying })
        #expect(await wait { finished.count == 2 })
        // Released while a bed fades: the engine runs until the fade has played.
        player.play([.bed(path: "bed", volume: 1, dur: 2), .play(Clip(path: "a", dur: 0.15, lines: []))])
        #expect(await wait { finished.count == 3 })
        let last = try #require(player.engine)
        player.release()
        #expect(player.engine == nil)
        #expect(last.isRunning)
        #expect(await wait(.seconds(2)) { !last.isRunning })
    }

    /// L2 even when the session can't be made active as the game opens (a call has it): its events are reported, so
    /// the next interruption still pauses the game.
    @Test func eventsAreReportedEvenIfTheSessionCantBeActive() async throws {
        let got = EventLog()
        let session = AudioSessionController(setUp: { _ in
            throw NSError(domain: NSOSStatusErrorDomain, code: 560_557_684)
        }) { got.events.append($0) }
        #expect(throws: (any Error).self) { try session.activate() }
        #expect(session.isObserving)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: UInt(1)])
        #expect(await wait { got.events == [.interruptionBegan] })
        session.deactivate(stopping: [])
        #expect(!session.isObserving)
    }

    @Test func interruptionsAreRead() {
        typealias Session = AudioSessionController
        #expect(Session.interruption([AVAudioSessionInterruptionTypeKey: UInt(1)]) == .interruptionBegan)
        #expect(Session.interruption([AVAudioSessionInterruptionTypeKey: UInt(0),
                                      AVAudioSessionInterruptionOptionKey: UInt(1)])
                == .interruptionEnded(shouldResume: true))
        #expect(Session.interruption([AVAudioSessionInterruptionTypeKey: UInt(0)])
                == .interruptionEnded(shouldResume: false))
        #expect(Session.interruption([:]) == nil)
    }

    /// Spike A's start latency, on the simulator: from play() until the voice is heard (its clock, less the output's
    /// latency, past frame 0), with the engine stopped (cold), then running (warm). Printed; a device is what counts.
    @Test func startLatency() async throws {
        defer { player.release() }
        var took: [Duration] = []
        for _ in 0..<3 {
            let start = ContinuousClock.now
            player.play(turn)
            #expect(await wait { (player.position()?.seconds ?? 0) > 0 })
            took.append(ContinuousClock.now - start)
            player.stop()
        }
        print("TurnPlayerTests: start latency cold \(took[0]), warm \(took[1]) and \(took[2])")
        #expect(took.allSatisfy { $0 < .seconds(1) })
    }

    /// Whether [condition] holds within [timeout], looked at every 10 ms.
    private func wait(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

@MainActor
final class EventLog {
    var events: [AudioSessionController.Event] = []
}
