// AudioPlayer.kt's ExoPlayers (the turn's, and one per bed, with their PlaybackParameters and volumes) and Earcons.kt's
// AudioTrack: one AVAudioEngine with a voice node, bed nodes, the voice speed, and a node for the app's short sounds.

import AVFoundation
import os

/**
 * The engine a game's audio plays through: one AVAudioEngine; a player node for the voice (the turn's clips, with
 * its pauses as gaps); and a pool of bed nodes, 6 to start with and more if a turn needs more at once. They all play
 * [ClipFormat] into [gameMix], which goes through the voice speed ([speed], a time-pitch unit: faster or slower at the
 * same pitch, bypassed at 1x so that 1x is untouched) to the main mixer. Every node starts from one anchor, so a buffer
 * scheduled at a frame of the turn plays exactly there on any node. The voice is gapless, and the beds start on the
 * very sample where they appear; at any speed they keep together, as everything goes through the one time-pitch.
 *
 * The app's short sounds (the listening sounds, a pack installed: AppCue) play on a node of their own, [cue], straight
 * into the main mixer: at 1x whatever the voice speed, and never cut by a turn stopping ([playCue]).
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
    /// The voice and the beds together, before the voice speed.
    let gameMix = AVAudioMixerNode()
    /// The voice speed: the turn faster or slower at the same pitch ([rate]); bypassed at 1x.
    let speed = AVAudioUnitTimePitch()
    /// The app's short sounds, at 1x (not through [speed]).
    let cue = AVAudioPlayerNode()
    /// Rendering offline, by hand (tests): no device, no latency, no host times.
    let offline: Bool
    private var observer: NSObjectProtocol?
    private let reconnect = OSAllocatedUnfairLock(initialState: false)

    /**
     * The voice speed (Settings › Sound and voice: 0.75 to 2): the voice and every bed, pauses and all, so music mixed
     * into a clip and the music under it stay together; the pitch stays as it is. At 1 the time-pitch is bypassed, and
     * the sound is exactly as it was (OfflineRenderTests). AudioPlayer.kt's setSpeed.
     */
    var rate: Float = 1 {
        didSet {
            speed.rate = rate
            speed.bypass = rate == 1
        }
    }

    /// Settings' music volume (0 to 1): every bed node's, on top of each bed's own (TurnSchedule's gain), at once.
    /// AudioPlayer.kt's setMusicVolume.
    var musicVolume: Float = 1 {
        didSet {
            for b in beds { b.volume = musicVolume }
        }
    }

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
        // Voice and beds -> gameMix -> the voice speed -> the main mixer; the short sounds -> the main mixer.
        engine.attach(gameMix)
        engine.attach(speed)
        engine.attach(voice)
        engine.attach(cue)
        engine.connect(gameMix, to: speed, format: ClipFormat.pcm)
        engine.connect(speed, to: engine.mainMixerNode, format: ClipFormat.pcm)
        engine.connect(voice, to: gameMix, format: ClipFormat.pcm)
        engine.connect(cue, to: engine.mainMixerNode, format: ClipFormat.pcm)
        speed.bypass = true
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

    /// At least [count] bed nodes (a turn with more beds at once than the pool has adds nodes for good), each at the
    /// music volume.
    func ensureBedNodes(_ count: Int) {
        while beds.count < count {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: gameMix, format: ClipFormat.pcm)
            node.volume = musicVolume
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

    /**
     * Starts the voice and these bed nodes (indices into [beds]) together, a moment from now, at frame 0 of the turn.
     * At 1x, at a host time. Off 1x, the nodes behind the time-pitch run on a clock of their own (as many frames as it
     * takes from them: [rate] times the output's), which host times don't map onto: at a frame of that clock instead,
     * the last they rendered (the same on each: gameMix takes from them all at once) plus the moment, at the speed.
     */
    func play(bedNodes: [Int]) {
        let nodes = [voice] + bedNodes.map { beds[$0] }
        if offline {
            // Before the next render: every node's frame 0 is that render's first frame.
            for n in nodes { n.play() }
            return
        }
        let lead = Self.lead(AVAudioSession.sharedInstance())
        let when: AVAudioTime
        if !speed.bypass, let t = voice.lastRenderTime, t.isSampleTimeValid {
            let ahead = AVAudioFramePosition((lead * Double(rate) * t.sampleRate).rounded(.up))
            when = AVAudioTime(sampleTime: t.sampleTime + ahead, atRate: t.sampleRate)
        } else {
            when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: lead))
        }
        for n in nodes { n.play(at: when) }
    }

    /// How far ahead nodes are started, so that the render thread reaches them all at once: two I/O buffers and a
    /// margin, 20 to 100 ms.
    private static func lead(_ session: AVAudioSession) -> TimeInterval {
        min(max(2 * session.ioBufferDuration + 0.01, 0.02), 0.1)
    }

    /**
     * The frame of their own clock the nodes last rendered (the voice's: gameMix takes from them all at once), what a
     * speed off 1x starts them from ([play]); nil before they have rendered.
     */
    var renderedFrame: AVAudioFramePosition? {
        guard let t = voice.lastRenderTime, t.isSampleTimeValid else { return nil }
        return t.sampleTime
    }

    /**
     * The nodes have rendered at a frame other than [stale]: what they showed as the engine started, which can be their
     * clock from before it last stopped (a call, the output changing), no frame to start them from ([play]).
     */
    func hasRendered(since stale: AVAudioFramePosition?) -> Bool {
        guard let frame = renderedFrame else { return false }
        return frame != stale
    }

    /**
     * Plays one of the app's short sounds ([buffer], [ClipFormat], a CueBank's) on the cue node, [delay] from now (or
     * the moment the engine needs, if that's longer), cutting short any it was playing: never through the voice speed,
     * and not stopped with a turn ([stopNodes]). Returns when it will have been heard out: its start, its length, the
     * output's latency and an I/O buffer, then the mic's own latency and a margin, so that what the mic records from
     * then on is clear of it (SpeechListener's gate). Nil when the engine can't run (a call has the audio).
     * Earcons.kt's play, with its marker and its tail.
     */
    func playCue(_ buffer: AVAudioPCMBuffer, delay: TimeInterval = 0.08) -> ContinuousClock.Instant? {
        do {
            try start()
        } catch {
            ClipDecoder.log.error("can't start the audio engine for a sound: \(error, privacy: .public)")
            return nil
        }
        let length = Double(buffer.frameLength) / buffer.format.sampleRate
        let now = ContinuousClock.now
        cue.stop()
        cue.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if offline {
            cue.play()
            return now + .seconds(length)
        }
        let session = AVAudioSession.sharedInstance()
        let wait = max(delay, Self.lead(session))
        cue.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: wait)))
        let heard = wait + length + session.outputLatency + session.ioBufferDuration + session.inputLatency + 0.05
        return now + .seconds(heard)
    }

    /// Stops every node at once, dropping what was scheduled (AudioPlayer.stop's player.stop and stopBeds), but the
    /// bed nodes in [keeping] (beds fading out after a turn's end, which AudioPlayer.kt's stop never touches). The cue
    /// node plays on: a listening sound isn't cut by the turn that follows it.
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

    /**
     * How far what is heard trails what the voice node renders, in the turn's frames: the output's latency and one I/O
     * buffer, and off 1x the time-pitch's own latency, all at the speed (the node's clock runs [rate] times as fast).
     */
    func latencyFrames() -> Int64 {
        guard !offline else { return 0 }
        let session = AVAudioSession.sharedInstance()
        let pitch = speed.bypass ? 0 : speed.auAudioUnit.latency
        return ClipFormat.frames((session.outputLatency + session.ioBufferDuration + pitch) * Double(rate))
    }

    /// Lets go of the audio: every node stopped, the cue node too, then the engine.
    func shutdown() {
        stopNodes()
        cue.stop()
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
