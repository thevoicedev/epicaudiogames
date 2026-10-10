// AudioPlayer.kt's playlist (gapless) and beds, rendered offline: every frame of a turn where TurnTimeline puts it.

import AVFoundation
import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * Turns played as TurnPlayer plays them (laid out, decoded ahead in chunks, scheduled at their frames on one voice
 * node and the bed nodes) through an AVAudioEngine in manual rendering mode, then checked frame by frame. The clips
 * are constant levels, so the mix at every frame is known exactly: a gap, an overlap, a bed a frame late or a chunk
 * seam out of place would all show. The expected mix is worked out here from TurnTimeline and Android's rules
 * (AudioPlayer.startBeds and fadeOutBeds), not from TurnSchedule.
 */
@MainActor
struct OfflineRenderTests {
    /// A Nuclear War turn: the theme under everything at 0.2, a phone ring, a pause, then Don's sentence in 30
    /// pieces, one of them missing; every bed stops, and an alarm starts that is still playing when the turn ends.
    @Test func donsSentenceInPiecesIsGaplessWithItsBeds() async throws {
        let content = try LevelClips()
        try content.clip("music/theme", level: 0.5, seconds: 20)
        try content.clip("sfx/ring", level: 0.05, seconds: 1.5)
        try content.clip("sfx/alarm", level: 0.4, seconds: 3)
        var steps: [Step] = [.bed(path: "music/theme", volume: 0.2, dur: 20),
                             .bed(path: "sfx/ring", volume: 1, dur: 1.5), .pause(1.0)]
        for i in 0..<30 {
            let path = "don/piece\(i)"
            // 0.08 to 0.7 s, no two neighbours alike.
            try content.clip(path, level: 0.3 + 0.01 * Float(i % 7), frames: 4_000 + (i * 7_919) % 30_000)
            if i == 24 {
                steps += [.bed(path: nil, volume: 0, dur: 0), .bed(path: "sfx/alarm", volume: 0.5, dur: 3)]
            }
            steps.append(.play(Clip(path: path, dur: 0, lines: [])))
            if i == 12 { steps.append(.play(Clip(path: "don/missing", dur: 0.5, lines: []))) }
        }
        let render = try await OfflineRender(steps, content)
        #expect(render.turn.timeline.clipCount == 31)
        #expect(render.turn.bedNodes == 2)
        render.expectMix(content.expected(steps))
        #expect(render.finishes == 1)
    }

    /// A Leaning Tower of Pizza turn: a 40 s music bed (decoded 2 s at a time) under lines with 0.5 s pauses
    /// between them; the bed comes again halfway and carries on rather than restarting.
    @Test func aLongBedUnderLinesAndPausesStaysInStep() async throws {
        let content = try LevelClips()
        try content.clip("music/long", level: 0.25, seconds: 40)
        var steps: [Step] = [.bed(path: "music/long", volume: 0.6, dur: 40)]
        for i in 0..<20 {
            let path = "lines/line\(i)"
            try content.clip(path, level: 0.5 + 0.02 * Float(i % 5), frames: 19_200 + (i * 4_801) % 33_600)
            if i == 10 { steps.append(.bed(path: "music/long", volume: 1, dur: 40)) }
            steps += [.play(Clip(path: path, dur: 0, lines: [])), .pause(0.5)]
        }
        try content.clip("lines/last", level: 0.45, seconds: 0.8)
        steps.append(.play(Clip(path: "lines/last", dur: 0, lines: [])))
        let render = try await OfflineRender(steps, content)
        #expect(render.turn.bedNodes == 1)
        #expect(render.turn.timeline.items.count == 41)
        render.expectMix(content.expected(steps))
        #expect(render.finishes == 1)
    }

    /// A turn that ends in a pause finishes when the pause has played; a bed stopped before it ends isn't faded.
    @Test func aTurnEndingInAPauseFinishesAfterIt() async throws {
        let content = try LevelClips()
        try content.clip("a", level: 0.5, seconds: 0.4)
        try content.clip("bed", level: 0.3, seconds: 5)
        let steps: [Step] = [.bed(path: "bed", volume: 1, dur: 5), .play(Clip(path: "a", dur: 0, lines: [])),
                             .bed(path: nil, volume: 0, dur: 0), .pause(0.75)]
        let render = try await OfflineRender(steps, content)
        #expect(render.turn.end == ClipFormat.frames(1.15))
        render.expectMix(content.expected(steps))
        #expect(render.finishes == 1)
    }

    /// More beds at once than the pool's 6: it grows, and every bed plays where it should.
    @Test func moreBedsThanThePoolAllPlay() async throws {
        let content = try LevelClips()
        var steps: [Step] = []
        for i in 0..<8 {
            try content.clip("bed\(i)", level: 0.01 * Float(i + 1), seconds: 2)
            steps.append(.bed(path: "bed\(i)", volume: 1, dur: 2))
        }
        try content.clip("voice", level: 0.5, seconds: 1)
        steps.append(.play(Clip(path: "voice", dur: 1, lines: [])))
        let render = try await OfflineRender(steps, content)
        #expect(render.turn.bedNodes == 8)
        render.expectMix(content.expected(steps))
        #expect(render.finishes == 1)
    }

    /// Clips at 24, 32, 44.1 and 48 kHz (speech, mixes, recordings, Opus) converted to 48 kHz: each takes the
    /// frames TurnTimeline gave it, and the voice never drops out between them.
    @Test func clipsAtEveryRateJoinWithoutGaps() async throws {
        let content = try LevelClips()
        let rates: [Double] = [24_000, 32_000, 44_100, 48_000]
        var steps: [Step] = []
        for i in 0..<16 {
            let level: Float = i % 2 == 0 ? 0.3 : 0.6
            let rate = rates[i % 4]
            try content.clip("mixed/\(i)", level: level, frames: Int(rate * (0.2 + 0.05 * Double(i % 5))), rate: rate)
            steps.append(.play(Clip(path: "mixed/\(i)", dur: 0, lines: [])))
        }
        let render = try await OfflineRender(steps, content)
        let items = render.turn.timeline.items
        for (i, item) in items.enumerated() {
            let rate = rates[i % 4]
            #expect(item.frames == ClipDecoder.outputFrames(Int64(rate * (0.2 + 0.05 * Double(i % 5))), rate: rate))
            // Its middle is its level: it is where the timeline put it.
            let middle = render.mix[Int(item.start + item.frames / 2)]
            #expect(abs(middle - (i % 2 == 0 ? 0.3 : 0.6)) < 0.01, "item \(i): \(middle)")
        }
        let voice = render.mix[0..<Int(render.turn.end)]
        let lowest = voice.min() ?? 0
        #expect(lowest > 0.05, "the voice drops to \(lowest) between clips")
        #expect(render.mix[Int(render.turn.end)...].allSatisfy { abs($0) < 1e-6 })
    }

    /// The real decoders on the bundled content: 30 of Don's Opus lines in a row play back to back, each where
    /// the timeline says, with no silence between them but the clips' own. (Don's pieces are cut out of whole
    /// sentences between words, so some start or end on silence of their own, up to 45 ms here: "0 points" ends on
    /// 41 ms of it. With the placeholder clips, that was only their 5 ms fades.)
    @Test(.enabled(if: BundledClips.content != nil, "no content was bundled"))
    func donsBundledLinesPlayBackToBack() async throws {
        let content = try #require(BundledClips.content)
        let tts = content.appendingPathComponent("nuclear-war/tts")
        let names = try FileManager.default.contentsOfDirectory(atPath: tts.path).filter { $0.hasSuffix(".opus") }
            .sorted().prefix(30)
        try #require(names.count == 30)
        let steps = names.map { Step.play(Clip(path: "tts/" + $0.dropLast(5), dur: 0, lines: [])) }
        let resolver = ContentResolver(gameId: "nuclear-war", content: content, packs: [])
        let render = try await OfflineRender(steps, resolver: resolver)
        let items = render.turn.timeline.items
        #expect(items.allSatisfy { !$0.missing && $0.frames > 0 })
        #expect(render.turn.end == items.map(\.frames).reduce(0, +))
        // The clips themselves, decoded whole and laid end to end: the mix must be exactly that.
        var own: [Float] = []
        for item in items {
            let url = try #require(resolver.url(item.path ?? ""), "no file for \(item.path ?? "")")
            own += DecodeTests.samples(try ClipDecoder.decode(ClipDecoder.open(url)))
        }
        try #require(own.count == Int(render.turn.end))
        let voice = render.mix[0..<own.count]
        let worst = zip(voice, own).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 1e-3, "the mix differs from the clips end to end by \(worst)")
        func longestSilence(_ samples: some Collection<Float>) -> Int {
            var longest = 0
            var run = 0
            for x in samples {
                run = abs(x) < 1e-4 ? run + 1 : 0
                longest = max(longest, run)
            }
            return longest
        }
        let longest = longestSilence(voice)
        let clipsOwn = longestSilence(own)
        #expect(longest <= clipsOwn + Int(ClipFormat.frames(0.001)),
                "\(longest) silent frames in a row, where the clips have \(clipsOwn)")
        for item in items {
            let middle = render.mix[Int(item.start + item.frames / 4)..<Int(item.start + item.frames * 3 / 4)]
            #expect(middle.contains { abs($0) > 0.01 }, "silent: \(item.path ?? "")")
        }
        #expect(render.finishes == 1)
    }

    /**
     * At 1.5 times the voice speed (Settings), the time-pitch plays the whole turn faster, the voice and the beds alike
     * (both go through it): a tone on the voice and the same tone on a bed, at the same frame of the turn, come out
     * together, at about that frame / 1.5, and the turn's sound is over sooner. (At 1x the time-pitch is bypassed: the
     * renders above are exact.)
     */
    @Test func atASpeedTheVoiceAndTheBedsKeepTogether() async throws {
        let content = try LevelClips()
        try content.tone("burst", seconds: 0.2)
        try content.clip("quiet", level: 0, seconds: 0.2)
        // The tone 0.6 s into the turn: on the voice, then (the voice silent) on a bed.
        let voice: [Step] = [.pause(0.6), .play(Clip(path: "burst", dur: 0, lines: [])), .pause(0.4)]
        let bed: [Step] = [.pause(0.6), .bed(path: "burst", volume: 1, dur: 0.2),
                           .play(Clip(path: "quiet", dur: 0, lines: [])), .pause(0.4)]
        let a = try await OfflineRender(voice, content, speed: 1.5)
        let b = try await OfflineRender(bed, content, speed: 1.5)
        let onVoice = try #require(OfflineRender.loud(a.mix).first, "the voice's tone never came")
        let onBed = try #require(OfflineRender.loud(b.mix).first, "the bed's tone never came")
        #expect(abs(onVoice - onBed) <= Int(ClipFormat.frames(0.005)), "voice at \(onVoice), bed at \(onBed)")
        // About 0.6 s / 1.5 = 0.4 s in, give or take the time-pitch's own latency.
        let expected = Int(ClipFormat.frames(0.6 / 1.5))
        #expect(abs(onVoice - expected) < Int(ClipFormat.frames(0.1)), "at \(onVoice), not about \(expected)")
        // Over by about 0.8 s / 1.5, well before the 0.8 s it takes at 1x.
        let end = try #require(OfflineRender.loud(a.mix).last)
        #expect(end < Int(ClipFormat.frames(0.75)), "the tone ended at \(end)")
        #expect(end - onVoice > Int(ClipFormat.frames(0.1)), "the tone lasted \(end - onVoice) frames")
        #expect(a.finishes == 1)
        #expect(b.finishes == 1)
    }
}

/// A turn rendered offline, as TurnPlayer plays it.
@MainActor
struct OfflineRender {
    let turn: TurnSchedule
    let mix: [Float]
    let finishes: Int

    init(_ steps: [Step], _ content: LevelClips, speed: Float = 1) async throws {
        try await self.init(steps, resolver: content.resolver, speed: speed)
    }

    /// Renders the turn and [after] seconds past its end, at the voice speed [speed] (1: the time-pitch bypassed).
    init(_ steps: [Step], resolver: ContentResolver, after: Double = 0.25, speed: Float = 1) async throws {
        let cache = DecodedClipCache()
        let turn = await TurnPlayer.prepare(steps, resolver: resolver, cache: cache)
        let graph = try AudioGraph(offline: true)
        defer { graph.shutdown() }
        graph.rate = speed
        let feeder = TurnFeeder(turn, cache: cache)
        graph.ensureBedNodes(turn.bedNodes)
        try graph.start()
        let finished = FinishCounter()
        func schedule(_ chunks: [ScheduledChunk]) {
            for c in chunks {
                if c.last { graph.schedule(c) { finished.count += 1 } } else { graph.schedule(c) }
            }
        }
        schedule(await feeder.chunks(before: TurnPlayer.lookahead))
        graph.play(beds: turn.bedNodes)
        // Off 1x the output is the turn's length over the speed; renders are kept short, as the time-pitch takes that
        // many times more frames from the nodes behind it.
        let total = Int((Double(turn.end) / Double(speed)).rounded(.up)) + Int(ClipFormat.frames(after))
        let step = speed == 1 ? 4_096 : 1_024
        let out = try #require(AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat, frameCapacity: 4_096))
        var mix: [Float] = []
        mix.reserveCapacity(total)
        while mix.count < total {
            let status = try graph.engine.renderOffline(AVAudioFrameCount(min(step, total - mix.count)), to: out)
            try #require(status == .success)
            mix += UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength))
            let heard = Int64((Double(mix.count) * Double(speed)).rounded(.up))
            schedule(await feeder.chunks(before: heard + TurnPlayer.lookahead))
        }
        #expect(await feeder.isDone)
        // The finish comes through the main queue.
        for _ in 0..<20 where finished.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        self.turn = turn
        self.mix = mix
        finishes = finished.count
    }

    /// The frames of [mix] louder than [threshold], in order.
    static func loud(_ mix: [Float], threshold: Float = 0.1) -> [Int] {
        mix.indices.filter { abs(mix[$0]) > threshold }
    }

    /// The mix is [expected] at every frame (to a float's rounding: the mixer adds in its own order).
    func expectMix(_ expected: [Float]) {
        #expect(mix.count == expected.count)
        var wrong = 0
        var first: Int?
        for i in 0..<min(mix.count, expected.count) where abs(mix[i] - expected[i]) > 1e-5 {
            wrong += 1
            if first == nil { first = i }
        }
        if let f = first {
            let around = (max(f - 2, 0)...min(f + 2, mix.count - 1)).map { "\($0): \(mix[$0]) vs \(expected[$0])" }
            Issue.record("\(wrong) frames differ, first at \(f) (\(Double(f) / 48_000) s): \(around)")
        }
    }
}

@MainActor
final class FinishCounter {
    var count = 0
}

/**
 * Clips at constant levels, written as float CAF files at their rate under Content/test/, and the resolver that
 * finds them. A clip at 48 kHz plays its level exactly, so a mix of them is known at every frame.
 */
final class LevelClips {
    let scratch: AudioScratch
    let resolver: ContentResolver
    private(set) var levels: [String: (level: Float, frames: Int64)] = [:]

    init() throws {
        scratch = try AudioScratch()
        let content = scratch.url.appendingPathComponent("Content")
        try FileManager.default.createDirectory(at: content.appendingPathComponent("test"),
                                                withIntermediateDirectories: true)
        resolver = ContentResolver(gameId: "test", content: content, packs: [], extensions: [".caf"])
    }

    func clip(_ path: String, level: Float, seconds: Double) throws {
        try clip(path, level: level, frames: Int(ClipFormat.frames(seconds)))
    }

    func clip(_ path: String, level: Float, frames: Int, rate: Double = 48_000) throws {
        let url = scratch.url.appendingPathComponent("Content/test/\(path).caf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.floatChannelData![0].update(repeating: level, count: frames)
        buffer.frameLength = AVAudioFrameCount(frames)
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: buffer)
            if #available(iOS 18, *) { file.close() }     // else when it goes
        }
        levels[path] = (level, ClipDecoder.outputFrames(Int64(frames), rate: rate))
    }

    /**
     * A tone (a sine of [frequency] at [level]) for [seconds], at 48 kHz: a sound a time-pitch keeps as it is, where it
     * may smear a constant level. Not in [expected]: only its own frames are known.
     */
    func tone(_ path: String, seconds: Double, frequency: Double = 1_000, level: Float = 0.5) throws {
        let frames = Int(ClipFormat.frames(seconds))
        let url = scratch.url.appendingPathComponent("Content/test/\(path).caf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        let samples = buffer.floatChannelData![0]
        for i in 0..<frames {
            samples[i] = level * Float(sin(2 * Double.pi * frequency * Double(i) / 48_000))
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: buffer)
            if #available(iOS 18, *) { file.close() }
        }
    }

    /// A 16-bit mono WAV at 48 kHz, [seconds] of a constant [level]: a short sound's file, as tools/app_audio.py writes
    /// the app's (the listening sounds: CueBank reads them).
    static func wav(_ url: URL, seconds: Double, level: Float = 0.3) throws {
        let frames = Int(ClipFormat.frames(seconds))
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.floatChannelData![0].update(repeating: level, count: frames)
        buffer.frameLength = AVAudioFrameCount(frames)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: buffer)
            if #available(iOS 18, *) { file.close() }
        }
    }

    /**
     * The mix the turn should make, from TurnTimeline and AudioPlayer.kt's rules: the clips one after another;
     * each bed from its item until it ends, the next bed with no path, or 150 ms past the turn's end, fading by a
     * sixth of its volume every 25 ms from the end (fadeOutBeds); and [after] seconds rendered past the end.
     */
    func expected(_ steps: [Step], after: Double = 0.25) -> [Float] {
        let timeline = TurnTimeline(steps: steps, sampleRate: 48_000) { levels[$0.path]?.frames }
        let end = timeline.frames
        var mix = [Float](repeating: 0, count: Int(end + ClipFormat.frames(after)))
        for item in timeline.items {
            guard let path = item.path, let level = levels[path]?.level else { continue }
            for f in item.start..<item.end { mix[Int(f)] += level }
        }
        for (k, cue) in timeline.beds.enumerated() {
            guard case .start(let path, let volume, _, let frame) = cue, let bed = levels[path] else { continue }
            var stop = Int64.max
            for case .stopAll(_, let at) in timeline.beds[(k + 1)...] {
                stop = at
                break
            }
            let step: Int64 = 1_200    // 25 ms
            let last = min(frame + bed.frames, stop, end + 6 * step)
            for f in frame..<max(last, frame) {
                var gain = Float(volume)
                if f >= end, last > end { gain = gain * Float(6 - (f - end) / step) / 6 }
                mix[Int(f)] += bed.level * gain
            }
        }
        return mix
    }
}
