// TurnTimeline.swift: AudioPlayer.kt's playlist (clips and pauses), its beds, position and clipsDone, in frames.

import Testing

@testable import EpicAppCore

struct TurnTimelineTests {
    private static let rate = 48_000.0
    /// Decoded lengths in frames at 48 kHz: a is 1 s, b 0.5 s, c 0.25 s; anything else has no audio.
    private static let lengths: [String: Int64] = ["a": 48_000, "b": 24_000, "c": 12_000]

    private func timeline(_ steps: [Step]) -> TurnTimeline {
        TurnTimeline(steps: steps, sampleRate: Self.rate) { Self.lengths[$0.path] }
    }

    @Test func clipsAndPausesOneAfterAnother() {
        let t = timeline([clip("a"), .pause(0.5), clip("b"), .num("score"), .pause(0), .pause(-1), clip("c")])
        #expect(t.items.map(\.clip) == [0, nil, 1, 2])
        #expect(t.items.map(\.path) == ["a", nil, "b", "c"])
        #expect(t.items.map(\.start) == [0, 48_000, 72_000, 96_000])
        #expect(t.items.map(\.frames) == [48_000, 24_000, 24_000, 12_000])
        #expect(t.frames == 108_000)
        #expect(t.seconds == 2.25)
        #expect(t.clipCount == 3)
        #expect(!t.isEmpty)
        #expect(t.beds.isEmpty)
    }

    /// SilenceMediaSource takes whole microseconds; the frames are whole too, and the starts their running sum.
    @Test func pausesAreWholeFrames() {
        let third = TurnTimeline(steps: Array(repeating: .pause(1.0 / 3), count: 3), sampleRate: 48_000) { _ in 0 }
        #expect(third.items.map(\.frames) == [15_999, 15_999, 15_999])
        #expect(third.items.map(\.start) == [0, 15_999, 31_998])
        let cd = TurnTimeline(steps: [.pause(1.0 / 3), .pause(0.5)], sampleRate: 44_100) { _ in 0 }
        #expect(cd.items.map(\.frames) == [14_699, 22_050])
        let many = TurnTimeline(steps: Array(repeating: .pause(0.1), count: 1000), sampleRate: 48_000) { _ in 0 }
        #expect(many.frames == 4_800_000)
    }

    @Test func emptyTurn() {
        let t = timeline([bed("music"), .num("n")])
        #expect(t.isEmpty)
        #expect(t.beds.isEmpty)       // play() returns before startBeds
        #expect(t.frames == 0)
        #expect(t.item(at: 0) == nil)
        #expect(t.position(at: 0) == nil)
        #expect(t.clipsDone(at: 0) == 0)
    }

    /// [null, X] at item 0: every bed stops, then X starts, once (Android takes item 0's beds twice: L4).
    @Test func stopThenStartAtTheFirstItemIsTakenOnce() {
        let t = timeline([bed(nil), bed("music", 0.2), clip("a")])
        #expect(t.beds == [.stopAll(item: 0, frame: 0), .start(path: "music", volume: 0.2, item: 0, frame: 0)])
    }

    @Test func aBedStartsAtTheItemAfterIt() {
        let t = timeline([clip("a"), bed("ring", 0.8), .pause(1), clip("b"), bed("alarm"), clip("c")])
        #expect(t.beds == [
            .start(path: "ring", volume: 0.8, item: 1, frame: 48_000),
            .start(path: "alarm", volume: 0.5, item: 3, frame: 120_000),
        ])
    }

    @Test func aBedAfterTheLastItemNeverStarts() {
        let t = timeline([bed("music"), clip("a"), bed("late"), bed(nil)])
        #expect(t.beds == [.start(path: "music", volume: 0.5, item: 0, frame: 0)])
    }

    /// A bed already playing carries on (at its first volume); after a stop it can start again.
    @Test func aBedAlreadyStartedCarriesOn() {
        let t = timeline([bed("m", 0.3), clip("a"), bed("m", 0.9), clip("b"), bed(nil), bed("m", 0.4), clip("c")])
        #expect(t.beds == [
            .start(path: "m", volume: 0.3, item: 0, frame: 0),
            .stopAll(item: 2, frame: 72_000),
            .start(path: "m", volume: 0.4, item: 2, frame: 72_000),
        ])
        // A bed that has played to its end is still "playing": it doesn't start again in this turn.
        let again = timeline([bed("ding"), clip("a"), clip("b"), bed("ding"), clip("c")])
        #expect(again.beds == [.start(path: "ding", volume: 0.5, item: 0, frame: 0)])
    }

    @Test func positionAndClipsDone() {
        let t = timeline([clip("a"), .pause(0.5), clip("b")])
        // Before the first frame (the output's latency taken off), ExoPlayer is at the first item's start.
        #expect(t.position(at: -500) == ClipPosition(clip: 0, seconds: 0))
        #expect(t.position(at: 0) == ClipPosition(clip: 0, seconds: 0))
        #expect(t.position(at: 24_000) == ClipPosition(clip: 0, seconds: 0.5))
        #expect(t.position(at: 47_999) == ClipPosition(clip: 0, seconds: 47_999 / 48_000))
        #expect(t.position(at: 48_000) == nil)                         // the pause
        #expect(t.clipsDone(at: 48_000) == 1)
        #expect(t.position(at: 84_000) == ClipPosition(clip: 1, seconds: 0.25))
        #expect(t.clipsDone(at: 84_000) == 1)
        #expect(t.position(at: 96_000) == nil)                         // ended
        #expect(t.clipsDone(at: 96_000) == 1)                          // ExoPlayer stays on the last item
        #expect(t.clipsDone(at: 0) == 0)
        #expect(t.item(at: 1_000_000) == 2)
    }

    /// A clip with no audio takes no time (it's passed at once, its lines shown), and its beds start where it is.
    @Test func aClipWithNoAudioIsPassed() {
        let t = timeline([clip("a"), bed("m"), clip("gone"), clip("b"), clip("gone too")])
        #expect(t.items.map(\.missing) == [false, true, false, true])
        #expect(t.items.map(\.frames) == [48_000, 0, 24_000, 0])
        #expect(t.items.map(\.start) == [0, 48_000, 48_000, 72_000])
        #expect(t.frames == 72_000)
        #expect(t.position(at: 48_000) == ClipPosition(clip: 2, seconds: 0))
        #expect(t.clipsDone(at: 48_000) == 2)
        #expect(t.position(at: 71_999) == ClipPosition(clip: 2, seconds: 23_999 / 48_000))
        #expect(t.position(at: 72_000) == nil)
        #expect(t.beds == [.start(path: "m", volume: 0.5, item: 1, frame: 48_000)])
        let nothing = timeline([clip("gone"), bed("m")])
        #expect(!nothing.isEmpty)
        #expect(nothing.frames == 0)
        #expect(nothing.position(at: 0) == nil)
    }
}
