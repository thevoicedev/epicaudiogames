// AudioPlayer.kt: plays a turn's clips, pauses and beds, and says where the voice is.

import AVFoundation
import EpicAppCore

/**
 * Plays a turn from the game's content (ContentResolver: its installed packs first, then Content/<id>/). Its clips
 * and pauses play one after another, and its beds (music and overlapping sounds) play underneath, each from where
 * it appears in the turn until the turn's audio ends. [position] says which clip is playing and where, so the
 * transcript can follow it. One is made for each game opened, as Android's AudioPlayer is.
 *
 * A turn is laid out (TurnTimeline) once its clips' files are open. It is then decoded a few seconds ahead of where
 * it plays (TurnFeeder) and scheduled on the AudioGraph's nodes at its frames. It finishes when its last item has
 * played (that buffer's .dataPlayedBack). Every play() and stop() starts a new generation, so a turn that was
 * stopped or replaced never finishes, however late its handlers come (stopping a node calls them all).
 */
final class TurnPlayer: TurnPlaying {
    var onFinished: (@MainActor @Sendable () -> Void)?
    var onStalled: (@MainActor @Sendable () -> Void)?

    /// How far ahead of the voice a turn is decoded and scheduled, and how often that is topped up.
    static let lookahead = ClipFormat.frames(4)
    static let topUp: Duration = .milliseconds(250)

    let resolver: ContentResolver
    private let cache: DecodedClipCache
    private(set) var graph: AudioGraph?
    /// Starts the graph's engine (tests make it fail, as a call holding the audio does).
    var startEngine: (AudioGraph) throws -> Void = { try $0.start() }

    private var generation: UInt64 = 0
    private var playing = false
    /// The turn playing, or the one that played to its end; nil while its files are opened, and after a stop.
    private var turn: TurnSchedule?
    /// Its first item is a clip (what [position] says while its files are opened, as ExoPlayer does once prepared).
    private var startsWithClip = false
    /// Its nodes have been started.
    private var started = false
    private var latency: Int64 = 0
    /// The frame last heard: where the voice stopped, if the engine stops under it (ExoPlayer's position holds).
    private var lastHeard: Int64 = 0
    private var feeding: Task<Void, Never>?
    /// The physical bed node (an index into the graph's beds) for each of the turn's (TurnSchedule's 1, 2, …).
    private var bedSlots: [Int] = []
    /// Bed nodes still fading out after the last turn's natural end, as AudioPlayer.fadeOutBeds' players do: a stop
    /// or the next turn leaves them be, and they stop once the fade has played.
    private(set) var fading: Set<Int> = []
    private var fadeEnds: ContinuousClock.Instant?
    private var fadeTask: Task<Void, Never>?

    init(resolver: ContentResolver, cache: DecodedClipCache = .shared, graph: AudioGraph? = nil) {
        self.resolver = resolver
        self.cache = cache
        self.graph = graph
    }

    /// The engine, for AudioSessionController.deactivate to stop first; nil before the first turn and after release.
    var engine: AVAudioEngine? { graph?.engine }

    /// Plays a turn's steps (clips, pauses and beds; other steps are already resolved by the engine).
    func play(_ steps: [Step]) {
        halt()                  // AudioPlayer.play's stopBeds(), and any turn still playing
        generation &+= 1
        let gen = generation
        playing = true
        guard let first = steps.first(where: Self.isItem) else {
            // Nothing to play: it finishes, but after play() returns (handler.post).
            Task { [weak self] in self?.finish(gen) }
            return
        }
        if case .play = first { startsWithClip = true } else { startsWithClip = false }
        feeding = Task { [weak self] in await self?.run(steps, gen) }
    }

    func stop() {
        generation &+= 1
        halt()
    }

    /// The clip playing (its index among the turn's clips) and the seconds into it; nil in a pause or when idle.
    func position() -> ClipPosition? {
        guard playing else { return nil }
        guard let turn else { return startsWithClip ? ClipPosition(clip: 0, seconds: 0) : nil }
        return turn.timeline.position(at: heard())
    }

    /// How many clips come before the item playing (for the transcript when a pause is playing).
    func clipsDone() -> Int {
        guard let turn else { return 0 }
        // Once played to its end, the playlist stays on its last item, as ExoPlayer's does.
        return turn.timeline.clipsDone(at: playing ? heard() : turn.end)
    }

    /// Lets go of the engine (the game closing). A play() after it makes a new one. Beds still fading out finish
    /// first, as AudioPlayer.release leaves them (see [tail]).
    func release() {
        stop()
        guard let old = graph else { return }
        graph = nil
        fadeTask?.cancel()
        fading = []
        if let wait = tail {
            Task {
                try? await Task.sleep(for: wait)
                old.shutdown()
            }
        } else {
            old.shutdown()
        }
        fadeEnds = nil
    }

    /// A new engine for the next turn: after the media services restart, the old one is no use (and nothing on it
    /// is still playing).
    func resetEngine() {
        fadeEnds = nil
        release()
    }

    /// How long the last turn's beds go on fading out, if they are (the engine must run that long).
    var tail: Duration? {
        guard let fadeEnds else { return nil }
        let left = fadeEnds - .now
        return left > .zero ? left : nil
    }

    // ----- Playing a turn -----

    private func run(_ steps: [Step], _ gen: UInt64) async {
        let turn = await Self.prepare(steps, resolver: resolver, cache: cache)
        guard gen == generation else { return }
        self.turn = turn
        if turn.isEmpty {
            // Every clip missing (L5): nothing to wait for.
            finish(gen)
            return
        }
        let graph = self.graph ?? AudioGraph()
        self.graph = graph
        let feeder = TurnFeeder(turn, cache: cache)
        let first = await feeder.chunks(before: Self.lookahead)
        guard gen == generation else { return }
        do {
            try startEngine(graph)
        } catch {
            // No audio at all (a call has it): the game waits for a tap, as after an interruption (L2).
            ClipDecoder.log.error("can't start the audio engine: \(error, privacy: .public)")
            stall(gen)
            return
        }
        // The beds go on nodes that aren't still fading out the last turn's.
        graph.ensureBedNodes(fading.count + turn.bedNodes)
        bedSlots = Array((0..<graph.beds.count).filter { !fading.contains($0) }.prefix(turn.bedNodes))
        latency = graph.latencyFrames()
        lastHeard = 0
        for c in first { schedule(c, gen) }
        graph.play(bedNodes: bedSlots)
        started = true
        while gen == generation, playing, !(await feeder.isDone) {
            do { try await Task.sleep(for: Self.topUp) } catch { return }
            guard gen == generation, playing else { return }
            let more = await feeder.chunks(before: max(graph.frame() ?? 0, 0) + Self.lookahead)
            guard gen == generation else { return }
            for c in more { schedule(c, gen) }
        }
    }

    private func schedule(_ chunk: ScheduledChunk, _ gen: UInt64) {
        // A bed's node is the one picked for it this turn.
        let chunk = chunk.node == 0 ? chunk
            : ScheduledChunk(node: bedSlots[chunk.node - 1] + 1, start: chunk.start, buffer: chunk.buffer, last: chunk.last)
        guard chunk.last else {
            graph?.schedule(chunk)
            return
        }
        graph?.schedule(chunk) { @MainActor [weak self] in self?.finish(gen) }
    }

    /// The turn's audio has played to its end (or it had none): once, and only for the turn playing.
    private func finish(_ gen: UInt64) {
        guard gen == generation, playing else { return }
        let turn = turn
        playing = false
        started = false
        feeding?.cancel()
        feeding = nil
        // The beds fade out by themselves: their last 150 ms were scheduled faded (TurnSchedule). Nothing cuts them.
        if let turn { fadeOut(turn) }
        onFinished?()
    }

    /// The turn's audio couldn't start: the game is told, and no finish comes.
    private func stall(_ gen: UInt64) {
        guard gen == generation, playing else { return }
        halt()
        onStalled?()
    }

    /// The bed nodes still playing at the turn's end keep playing their fade, then stop.
    private func fadeOut(_ turn: TurnSchedule) {
        let nodes = Set(turn.segments.filter { $0.node > 0 && $0.fadeFrom != nil }.map { bedSlots[$0.node - 1] })
        guard !nodes.isEmpty, let graph else { return }
        let wait = Duration.seconds(Double(TurnSchedule.fadeFrames + latency) / ClipFormat.sampleRate)
            + .milliseconds(50)
        fading.formUnion(nodes)
        let ends = ContinuousClock.now + wait
        fadeEnds = max(fadeEnds ?? ends, ends)
        fadeTask?.cancel()
        fadeTask = Task { [weak self, weak graph] in
            try? await Task.sleep(until: ends)
            guard let self, let graph, self.graph === graph, !Task.isCancelled else { return }
            graph.stopBeds(self.fading)
            self.fading = []
        }
    }

    private func halt() {
        playing = false
        started = false
        turn = nil
        feeding?.cancel()
        feeding = nil
        graph?.stopNodes(keeping: fading)
    }

    /// The frame of the turn being heard: the node's clock less the output's latency. If the engine has stopped
    /// under the turn (before the game hears of it), where it stopped.
    private func heard() -> Int64 {
        guard started else { return 0 }
        guard let frame = graph?.frame() else { return lastHeard }
        lastHeard = frame - latency
        return lastHeard
    }

    private static func isItem(_ step: Step) -> Bool {
        switch step {
        case .play: true
        case .pause(let seconds): seconds > 0
        default: false
        }
    }

    /// The turn laid out at 48 kHz, its clips' files found and opened (off the main actor: a turn can have 40).
    @concurrent
    nonisolated static func prepare(_ steps: [Step], resolver: ContentResolver,
                                    cache: DecodedClipCache) async -> TurnSchedule {
        var sources: [String: ClipSource] = [:]
        var tried: Set<String> = []
        for step in steps {
            let path: String
            switch step {
            case .play(let clip): path = clip.path
            case .bed(let bed?, _, _): path = bed
            default: continue
            }
            guard tried.insert(path).inserted, let url = resolver.url(path) else { continue }
            sources[path] = await cache.source(url)
        }
        let timeline = TurnTimeline(steps: steps, sampleRate: ClipFormat.sampleRate) { sources[$0.path]?.frames }
        return TurnSchedule(timeline: timeline, sources: sources)
    }
}
