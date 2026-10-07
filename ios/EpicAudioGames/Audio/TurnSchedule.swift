// AudioPlayer.kt's play, startBeds and fadeOutBeds (lines 63-151): what each player node plays, and when.

import Accelerate
import AVFoundation
import EpicAppCore

/**
 * A turn's audio as the player nodes play it, in frames from the turn's start (TurnTimeline's frames). The voice's
 * clips go one after another on node 0, with its pauses as gaps. Each bed goes on a bed node (1 and up), from where
 * it starts until it ends, a bed with no path stops every bed, or the turn's audio ends; there, as
 * AudioPlayer.fadeOutBeds does, it fades out in 6 steps of 25 ms. A stop() cuts it instead (the nodes stop).
 */
nonisolated struct TurnSchedule: Sendable {
    struct Segment: Equatable, Sendable {
        /// 0: the voice; 1 and up: a bed node.
        let node: Int
        let start: Int64
        let frames: Int64
        /// What plays, from its start; nil for silence (a pause that ends the turn, to finish on).
        let source: ClipSource?
        /// The bed's volume (0 to 1, as ExoPlayer clamps it); 1 for the voice.
        let gain: Float
        /// Where the fade-out starts (the turn's end), for a bed still playing there.
        let fadeFrom: Int64?
        /// The turn's audio has played when this has.
        let last: Bool

        var end: Int64 { start + frames }
    }

    /// The fade-out: 6 steps of 25 ms, each lower by a sixth of the bed's volume.
    static let fadeSteps: Int64 = 6
    static let fadeStep = ClipFormat.frames(0.025)
    static let fadeFrames = fadeStep * fadeSteps

    let timeline: TurnTimeline
    /// By start.
    let segments: [Segment]
    /// How many bed nodes it needs at once.
    let bedNodes: Int

    /// The turn's length: it finishes when its audio has played this far.
    var end: Int64 { timeline.frames }

    /// Nothing to play: the turn finishes at once.
    var isEmpty: Bool { timeline.frames == 0 }

    /// The turn laid out in [timeline], its clips' files in [sources] (by path; a clip not there isn't played).
    init(timeline: TurnTimeline, sources: [String: ClipSource]) {
        self.timeline = timeline
        let end = timeline.frames
        var voice: [Segment] = []
        for item in timeline.items where item.frames > 0 {
            guard let path = item.path, let source = sources[path] else { continue }
            voice.append(Segment(node: 0, start: item.start, frames: item.frames, source: source, gain: 1,
                                 fadeFrom: nil, last: false))
        }
        // The turn finishes when its last item has played: a clip, or a pause played as silence.
        let voiceEnd = voice.last?.end ?? 0
        if end > voiceEnd {
            voice.append(Segment(node: 0, start: voiceEnd, frames: end - voiceEnd, source: nil, gain: 1,
                                 fadeFrom: nil, last: true))
        } else if let final = voice.popLast() {
            voice.append(Segment(node: 0, start: final.start, frames: final.frames, source: final.source, gain: 1,
                                 fadeFrom: nil, last: true))
        }

        var beds: [Segment] = []
        var busyUntil: [Int64] = []
        let cues = timeline.beds
        for (k, cue) in cues.enumerated() {
            guard case .start(let path, let volume, _, let frame) = cue, frame < end,
                  let source = sources[path], source.frames > 0 else { continue }
            // It plays until it ends, the next stop of every bed, or the end of its fade.
            var stop = Int64.max
            for later in cues[(k + 1)...] {
                if case .stopAll(_, let at) = later {
                    stop = at
                    break
                }
            }
            let cut = min(frame + source.frames, stop, end + Self.fadeFrames)
            guard cut > frame else { continue }
            let node: Int
            if let free = busyUntil.firstIndex(where: { $0 <= frame }) {
                node = free
                busyUntil[free] = cut
            } else {
                node = busyUntil.count
                busyUntil.append(cut)
            }
            beds.append(Segment(node: node + 1, start: frame, frames: cut - frame, source: source,
                                gain: Float(min(max(volume, 0), 1)), fadeFrom: cut > end ? end : nil, last: false))
        }
        segments = (voice + beds).enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        bedNodes = busyUntil.count
    }

    /// A bed's gain at [frame] of the turn: its volume, lowered step by step from [fadeFrom].
    static func gain(_ gain: Float, at frame: Int64, fadeFrom: Int64?) -> Float {
        guard let fadeFrom, frame >= fadeFrom else { return gain }
        let k = min((frame - fadeFrom) / fadeStep, fadeSteps)
        return gain * Float(fadeSteps - k) / Float(fadeSteps)
    }
}

/// Decoded audio for a node, to play from a frame of the turn. Its buffer isn't changed once made.
nonisolated struct ScheduledChunk: @unchecked Sendable {
    let node: Int
    let start: Int64
    let buffer: AVAudioPCMBuffer
    /// The turn's audio has played when this has.
    let last: Bool

    var frames: Int64 { Int64(buffer.frameLength) }
}

/**
 * Decodes a turn's audio a little ahead of where it is playing: short clips whole (through the cache), long ones
 * [chunkFrames] at a time, so a two-minute mix or music bed is never all in memory. A clip that fails to decode
 * plays as silence of its length, so nothing after it moves.
 */
actor TurnFeeder {
    nonisolated static let chunkFrames = ClipFormat.frames(2)

    let schedule: TurnSchedule
    private let cache: DecodedClipCache
    /// Each segment's frames handed out so far.
    private var given: [Int64]
    private var streams: [Int: ClipStream] = [:]

    init(_ schedule: TurnSchedule, cache: DecodedClipCache) {
        self.schedule = schedule
        self.cache = cache
        given = Array(repeating: 0, count: schedule.segments.count)
    }

    /// Everything has been handed out.
    var isDone: Bool { zip(given, schedule.segments).allSatisfy { $0 >= $1.frames } }

    /// The chunks that start before [horizon] (a frame of the turn), in the order they start.
    func chunks(before horizon: Int64) async -> [ScheduledChunk] {
        var out: [ScheduledChunk] = []
        while true {
            var next: Int?
            var at = Int64.max
            for (i, s) in schedule.segments.enumerated() where given[i] < s.frames && s.start + given[i] < at {
                next = i
                at = s.start + given[i]
            }
            guard let i = next, at < horizon else { break }
            out.append(await chunk(i))
        }
        return out
    }

    private func chunk(_ i: Int) async -> ScheduledChunk {
        let s = schedule.segments[i]
        let offset = given[i]
        let at = s.start + offset
        var n = min(Self.chunkFrames, s.frames - offset)
        var buffer: AVAudioPCMBuffer?
        var shared = false
        if let source = s.source, source.frames <= DecodedClipCache.wholeLimit {
            // Short: the whole clip in one, decoded once and kept; copied only to cut or shape it.
            n = s.frames - offset
            do {
                let clip = try await cache.clip(source)
                shared = s.frames == source.frames && s.gain == 1 && s.fadeFrom == nil
                buffer = shared ? clip.buffer : Self.copy(clip.buffer, frames: n)
            } catch {
                ClipDecoder.failed(source.url, error)
            }
        } else if let source = s.source {
            buffer = read(i, source, n)
        }
        let b = buffer ?? Self.silence(n)
        if !shared { Self.shape(b, from: at, gain: s.gain, fadeFrom: s.fadeFrom) }
        given[i] = offset + Int64(b.frameLength)
        return ScheduledChunk(node: s.node, start: at, buffer: b, last: s.last && given[i] >= s.frames)
    }

    /// The next [n] frames of a long clip.
    private func read(_ i: Int, _ source: ClipSource, _ n: Int64) -> AVAudioPCMBuffer? {
        do {
            let stream = try streams[i] ?? ClipStream(source)
            streams[i] = stream
            let b = try stream.read(AVAudioFrameCount(n))
            if given[i] + n >= schedule.segments[i].frames { streams[i] = nil }
            return b
        } catch {
            ClipDecoder.failed(source.url, error)
            streams[i] = nil
            return nil
        }
    }

    /// The bed's volume and fade, applied to a buffer of its own.
    static func shape(_ b: AVAudioPCMBuffer, from frame: Int64, gain: Float, fadeFrom: Int64?) {
        guard gain != 1 || fadeFrom != nil, let p = b.floatChannelData?[0] else { return }
        let n = Int(b.frameLength)
        // Up to the fade, the volume alone.
        let plain = fadeFrom.map { Int(min(max($0 - frame, 0), Int64(n))) } ?? n
        if gain != 1, plain > 0 {
            var g = gain
            vDSP_vsmul(p, 1, &g, p, 1, vDSP_Length(plain))
        }
        for j in plain..<n {
            p[j] *= TurnSchedule.gain(gain, at: frame + Int64(j), fadeFrom: fadeFrom)
        }
    }

    static func copy(_ b: AVAudioPCMBuffer, frames: Int64) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(clamping: min(frames, Int64(b.frameLength)))
        let out = AVAudioPCMBuffer(pcmFormat: ClipFormat.pcm, frameCapacity: max(n, 1))!
        out.floatChannelData![0].update(from: b.floatChannelData![0], count: Int(n))
        out.frameLength = n
        return out
    }

    static func silence(_ frames: Int64) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(clamping: max(frames, 1))
        let out = AVAudioPCMBuffer(pcmFormat: ClipFormat.pcm, frameCapacity: n)!
        out.floatChannelData![0].update(repeating: 0, count: Int(n))
        out.frameLength = n
        return out
    }
}
