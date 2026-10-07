// AudioPlayer.kt's ExoPlayers (the turn's, and one per bed): one AVAudioEngine with a voice node and bed nodes.

import AVFoundation
import os

/**
 * The engine a game's audio plays through: one AVAudioEngine; a player node for the voice (the turn's clips, with
 * its pauses as gaps); and a pool of bed nodes, 6 to start with and more if a turn needs more at once. They all play
 * [ClipFormat] into the main mixer. Every node starts from one anchor, so a buffer scheduled at a frame of the turn
 * plays exactly there on any node. The voice is gapless, and the beds start on the very sample where they appear.
 *
 * Nonisolated: AVAudioEngine calls its completion handlers and posts its notifications on its own threads, and a
 * closure made in main-actor code traps there (Swift 6 checks its isolation when it runs). So the handlers are made
 * here, read only thread-safe state, and reach the main actor through DispatchQueue.main. Its methods are called
 * from the main actor (TurnPlayer), or from a test.
 */
nonisolated final class AudioGraph: @unchecked Sendable {
    static let initialBedNodes = 6

    let engine = AVAudioEngine()
    let voice = AVAudioPlayerNode()
    private(set) var beds: [AVAudioPlayerNode] = []
    /// Rendering offline, by hand (tests): no device, no latency, no host times.
    let offline: Bool
    private var observer: NSObjectProtocol?
    private let reconnect = OSAllocatedUnfairLock(initialState: false)

    /// A graph that plays to the device.
    convenience init() {
        // Only manual rendering can fail to set up.
        try! self.init(offline: false)
    }

    /// A graph rendered by hand ([offline]: engine.renderOffline), [ClipFormat] out.
    init(offline: Bool, maximumFrameCount: AVAudioFrameCount = 4096) throws {
        self.offline = offline
        if offline {
            try engine.enableManualRenderingMode(.offline, format: ClipFormat.pcm, maximumFrameCount: maximumFrameCount)
        }
        engine.attach(voice)
        engine.connect(voice, to: engine.mainMixerNode, format: ClipFormat.pcm)
        ensureBedNodes(Self.initialBedNodes)
        if !offline {
            // The engine stops itself when the output changes (sample rate, channels): reconnect before restarting.
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [reconnect] _ in
                reconnect.withLock { $0 = true }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// At least [count] bed nodes (a turn with more beds at once than the pool has adds nodes for good).
    func ensureBedNodes(_ count: Int) {
        while beds.count < count {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: ClipFormat.pcm)
            beds.append(node)
        }
    }

    /// Starts the engine if it isn't running: a configuration change, an interruption or the app going to the
    /// background can leave it stopped without saying so.
    func start() throws {
        if !offline, reconnect.withLock({ let r = $0; $0 = false; return r }) {
            let output = engine.outputNode.outputFormat(forBus: 0)
            let format = output.sampleRate > 0
                ? AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: output.channelCount) : nil
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        }
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch where !offline {
            // An interruption leaves the session inactive, and the engine won't start until it is active again.
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        }
    }

    /**
     * Schedules a chunk at its frame of the turn. For the turn's last chunk, [finished] is called on the main actor
     * once it has played, unless the voice was stopped, or the engine stopped, first.
     */
    func schedule(_ chunk: ScheduledChunk, finished: (@MainActor @Sendable () -> Void)? = nil) {
        let node = chunk.node == 0 ? voice : beds[chunk.node - 1]
        let when = AVAudioTime(sampleTime: AVAudioFramePosition(chunk.start), atRate: ClipFormat.sampleRate)
        guard let finished else {
            node.scheduleBuffer(chunk.buffer, at: when, options: [], completionHandler: nil)
            return
        }
        let end = chunk.start + chunk.frames
        // Rendering by hand, nothing is "played back": rendered is played.
        let type: AVAudioPlayerNodeCompletionCallbackType = offline ? .dataRendered : .dataPlayedBack
        node.scheduleBuffer(chunk.buffer, at: when, options: [], completionCallbackType: type) { [weak self] _ in
            // Not a thing here may touch the nodes: stop() calls this on the audio thread and waits for it.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A stopped node calls it too, and so can an engine that stopped: neither is the end.
                    guard let self, self.hasPlayed(to: end) else { return }
                    finished()
                }
            }
        }
    }

    /// Starts the voice and the first [beds] bed nodes together, a moment from now, at frame 0 of the turn.
    func play(beds count: Int) {
        play(bedNodes: Array(0..<min(count, beds.count)))
    }

    /// Starts the voice and these bed nodes (indices into [beds]) together, a moment from now, at frame 0 of the turn.
    func play(bedNodes: [Int]) {
        let nodes = [voice] + bedNodes.map { beds[$0] }
        if offline {
            // Before the next render: every node's frame 0 is that render's first frame.
            for n in nodes { n.play() }
            return
        }
        let session = AVAudioSession.sharedInstance()
        let lead = min(max(2 * session.ioBufferDuration + 0.01, 0.02), 0.1)
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead))
        for n in nodes { n.play(at: when) }
    }

    /// Stops every node at once, dropping what was scheduled (AudioPlayer.stop's player.stop and stopBeds), but the
    /// bed nodes in [keeping] (beds fading out after a turn's end, which AudioPlayer.kt's stop never touches).
    func stopNodes(keeping: Set<Int> = []) {
        voice.stop()
        for (i, b) in beds.enumerated() where !keeping.contains(i) { b.stop() }
    }

    /// Stops these bed nodes (their fade has played).
    func stopBeds(_ nodes: Set<Int>) {
        for i in nodes where i < beds.count { beds[i].stop() }
    }

    /// The frame of the turn the voice node is rendering (not yet heard: see [latencyFrames]); nil when it isn't.
    func frame() -> Int64? {
        guard voice.isPlaying, let t = voice.lastRenderTime, t.isSampleTimeValid,
              let p = voice.playerTime(forNodeTime: t), p.isSampleTimeValid else { return nil }
        if p.sampleRate == ClipFormat.sampleRate { return p.sampleTime }
        return Int64((Double(p.sampleTime) * ClipFormat.sampleRate / p.sampleRate).rounded(.down))
    }

    /// How far what is heard trails what is rendered: the output's latency and one I/O buffer.
    func latencyFrames() -> Int64 {
        guard !offline else { return 0 }
        let session = AVAudioSession.sharedInstance()
        return ClipFormat.frames(session.outputLatency + session.ioBufferDuration)
    }

    /// Lets go of the audio: every node stopped, then the engine.
    func shutdown() {
        stopNodes()
        engine.stop()
    }

    /// A render cycle's worth of frames: how early a .dataPlayedBack can come before the player's clock gets there.
    private static let endSlack = ClipFormat.frames(0.5)

    private func hasPlayed(to end: Int64) -> Bool {
        if offline { return voice.isPlaying }
        guard engine.isRunning, let at = frame() else { return false }
        return at >= end - Self.endSlack
    }
}
