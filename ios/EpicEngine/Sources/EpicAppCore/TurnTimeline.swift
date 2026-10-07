// AudioPlayer.kt's play, position, clipsDone and startBeds (lines 63-137): a turn's playlist and beds, timed in frames.

/// Where the voice is: the clip playing (its index among the turn's clips) and the seconds into it.
public struct ClipPosition: Equatable, Sendable {
    public let clip: Int
    public let seconds: Double

    public init(clip: Int, seconds: Double) {
        self.clip = clip
        self.seconds = seconds
    }
}

/**
 * A turn's audio laid out in frames at one sample rate: its clips and pauses one after another (the items), and its
 * beds, which start where they appear in the turn and play under the rest of it. Each item starts on a whole frame,
 * the sum of the lengths before it, so a long turn doesn't drift.
 *
 * The beds follow AudioPlayer.startBeds as the playlist reaches each item: a bed starts at the item it comes before;
 * a bed with no path stops every bed; a bed already playing in this turn carries on rather than starting again (until
 * a stop); a bed after the last item never starts; a turn with no items has no beds. Each item's beds are taken once:
 * on Android, item 0's are taken twice (the playlist's first transition, then play()), so a stop and a start at item
 * 0 restart that bed (docs/IOS_PARITY.md, L4).
 */
public struct TurnTimeline: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        /// The clip's index among the turn's clips (its Step.play steps, in order); nil for a pause.
        public let clip: Int?
        /// The clip's path; nil for a pause.
        public let path: String?
        public let start: Int64
        public let frames: Int64
        /// A clip with no audio (missing or undecodable): it takes no time, and its lines show as it's passed (L5).
        public let missing: Bool

        public var end: Int64 { start + frames }
    }

    /// A bed starting, or every bed stopping, where the playlist reaches an item.
    public enum BedCue: Equatable, Sendable {
        case start(path: String, volume: Double, item: Int, frame: Int64)
        case stopAll(item: Int, frame: Int64)
    }

    public let sampleRate: Double
    public let items: [Item]
    /// The beds' starts and stops, in the order they happen.
    public let beds: [BedCue]
    /// How many clips the turn has (its Step.play steps): the transcript's clips.
    public let clipCount: Int

    /**
     * The turn's steps laid out at [sampleRate]. [frames] gives a clip's length in frames at that rate (its decoded
     * length); nil when it has no audio. Steps other than clips, pauses and beds are already resolved by the engine.
     */
    public init(steps: [Step], sampleRate: Double, frames: (Clip) throws -> Int64?) rethrows {
        self.sampleRate = sampleRate
        var items: [Item] = []
        var bedsAt: [Int: [(path: String?, volume: Double)]] = [:]
        var clipIndex = 0
        var at: Int64 = 0
        for s in steps {
            switch s {
            case .play(let clip):
                let length = try frames(clip)
                let n = max(length ?? 0, 0)
                items.append(Item(clip: clipIndex, path: clip.path, start: at, frames: n, missing: length == nil))
                clipIndex += 1
                at += n
            case .pause(let seconds):
                // SilenceMediaSource((seconds * 1_000_000).toLong()): whole microseconds, then whole frames.
                if seconds > 0 {
                    let micros = Kt.saturatingLong(seconds * 1_000_000)
                    let n = max(Kt.saturatingLong((Double(micros) * sampleRate / 1_000_000).rounded(.down)), 0)
                    items.append(Item(clip: nil, path: nil, start: at, frames: n, missing: false))
                    at += n
                }
            case .bed(let path, let volume, _):
                bedsAt[items.count, default: []].append((path, volume))
            case .num, .when, .pick, .by:
                break
            }
        }
        self.items = items
        clipCount = clipIndex

        var cues: [BedCue] = []
        var playing: [String] = []
        for (i, item) in items.enumerated() {
            for b in bedsAt[i] ?? [] {
                guard let path = b.path else {
                    playing.removeAll()
                    cues.append(.stopAll(item: i, frame: item.start))
                    continue
                }
                if playing.contains(where: { Kt.utf16Equal($0, path) }) { continue }   // it carries on
                playing.append(path)
                cues.append(.start(path: path, volume: b.volume, item: i, frame: item.start))
            }
        }
        beds = cues
    }

    /// The turn's length in frames.
    public var frames: Int64 { items.last?.end ?? 0 }

    public var seconds: Double { Double(frames) / sampleRate }

    /// Whether the turn has nothing to play (no clips or pauses): it finishes at once.
    public var isEmpty: Bool { items.isEmpty }

    /**
     * The item the playlist is at, [frame] frames after the turn started: the last to have started (a clip with no
     * audio is passed at once). Before the start, the first; at or after the end, the last, as ExoPlayer stays on it.
     */
    public func item(at frame: Int64) -> Int? {
        guard !items.isEmpty else { return nil }
        let f = max(frame, 0)
        var low = 0
        var high = items.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if items[mid].start <= f { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The clip playing and the seconds into it; nil in a pause and once the turn's audio has ended.
    public func position(at frame: Int64) -> ClipPosition? {
        guard frame < frames, let i = item(at: frame), let clip = items[i].clip else { return nil }
        return ClipPosition(clip: clip, seconds: Double(max(frame, 0) - items[i].start) / sampleRate)
    }

    /// How many clips come before the item the playlist is at (the transcript shows their lines during a pause).
    public func clipsDone(at frame: Int64) -> Int {
        guard let i = item(at: frame) else { return 0 }
        return items[..<i].reduce(0) { $0 + ($1.clip == nil ? 0 : 1) }
    }
}
