// No Kotlin counterpart: the Audio Lab (Debug builds), to hear any node of any game through the app's turn player, and
// the app's own sounds.

#if DEBUG
import AVFoundation
import EpicAppCore
import Speech
import SwiftUI

/**
 * Plays any node's say or reprompt (with the map's starting variables), or a run of Don's lines, through the same
 * TurnPlaying the games use, with where the playlist is: the clip, the seconds into it, and the time since it began.
 * And the app's own sounds (AppAudio): the intro's sting, the short sounds, the help pages read aloud with the word
 * being read, the voice speed, and the mic's gate after the listening sound. Opened by a long press on the game list's
 * title.
 */
struct AudioLabView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var gameId = ""
    @State private var loaded: LoadedGame?
    @State private var problem: String?
    @State private var filter = ""
    @State private var audio: (any TurnPlaying)?
    @State private var playing = Playing()
    @State private var gate = GateMeter()

    /// What was last played, and when.
    struct Playing {
        var label = ""
        var steps: [Step] = []
        var started: Date?
        var finished: Date?
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    Picker("Game", selection: $gameId) {
                        ForEach(model.games) { Text($0.title).tag($0.id) }
                    }
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    }
                }
                Section("Playing") {
                    readout
                    Button("Stop", role: .destructive) { stop() }
                }
                appSounds
                switch loaded {
                case .map(let map):
                    nodes(map)
                case .nuclearWar(let audio):
                    Section("Nuclear War") {
                        Button("A Don sentence (15 lines)") { donSentence(audio) }
                    }
                case nil:
                    EmptyView()
                }
            }
            .navigationTitle("Audio Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        gate.stop()
                        model.appAudio.stopAll()
                        audio?.release()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { if gameId.isEmpty { gameId = model.games.first?.id ?? "" } }
        .task(id: gameId) { await load() }
        .onDisappear {
            gate.stop()
            model.appAudio.stopAll()
            audio?.release()
        }
    }

    // ----- The app's own sounds -----

    @ViewBuilder private var appSounds: some View {
        let app = model.appAudio
        Section("App sounds") {
            Button("The intro's sting") {
                AppAudio.introPlayed = false
                if !app.playIntro(onDone: {}) { problem = "No sting: none picked, or another app's audio playing" }
            }
            ForEach(AppCue.allCases, id: \.self) { cue in
                Button("Sound: \(cue.rawValue)") { app.playSound(cue) }
            }
            Picker("Voice speed", selection: voiceSpeed) {
                ForEach(AppSettings.voiceSpeeds, id: \.self) { Text(speedWords($0)).tag($0) }
            }
            ForEach(pages, id: \.self) { clip in
                Button("Read: \(title(clip))") { app.play(clip) }
                    .disabled(!app.hasClip(clip))
            }
            Button("Stop reading", role: .destructive) { app.stopClip() }
            Text(reading).font(.caption.monospaced())
        }
        Section("The mic's gate") {
            Button("The listening sound, then the mic from its gate") { gate.run(audio as? TurnPlayer) }
            if !gate.note.isEmpty { Text(gate.note).font(.caption) }
            ProgressView(value: Double(gate.level))
        }
    }

    /// The voice speed (Settings'), for the game's turns played here and the pages alike.
    private var voiceSpeed: Binding<Double> {
        Binding(get: { model.settings.voiceSpeed }, set: { speed in
            model.settings.voiceSpeed = speed
            (audio as? TurnPlayer)?.speed = speed
        })
    }

    /// The pages the app reads aloud: the welcome, the voice speed's sample, and each help topic.
    private var pages: [AppClip] {
        [.welcome, .sample] + (model.appAudio.manifest?.help.map { AppClip.help($0.id) } ?? [])
    }

    private func title(_ clip: AppClip) -> String {
        switch clip {
        case .welcome: "Welcome"
        case .sample: "The voice speed's sample"
        case .help(let id): model.appAudio.manifest?.topic(id)?.title ?? id
        }
    }

    /// The page being read, and the word marked in it.
    private var reading: String {
        let app = model.appAudio
        guard let clip = app.clipPlaying else { return "Nothing being read" }
        guard let h = app.highlight, let page = page(clip), page.text.indices.contains(h.paragraph) else {
            return "\(title(clip)): starting"
        }
        let word = Transcript.currentWord(page.text[h.paragraph], saidChars: h.chars).word
        return "\(title(clip)): paragraph \(h.paragraph), \(h.chars) characters, “\(word)”"
    }

    private func page(_ clip: AppClip) -> HelpPage? {
        switch clip {
        case .welcome, .sample: model.appAudio.manifest?.welcome
        case .help(let id): model.appAudio.manifest?.topic(id)
        }
    }

    // ----- Readout -----

    private var readout: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(playing.label.isEmpty ? "Nothing yet" : playing.label).font(.headline)
                Text(position(at: context.date)).font(.body.monospacedDigit())
                ForEach(Array(clips.enumerated()), id: \.offset) { i, clip in
                    Text("\(i). \(clip.path)  dur \(String(format: "%.3f", clip.dur)) s")
                        .font(.caption.monospaced())
                        .foregroundStyle(i == audio?.position()?.clip ? Color.accentColor : Color.secondary)
                }
            }
        }
    }

    private var clips: [Clip] {
        playing.steps.compactMap { if case .play(let clip) = $0 { clip } else { nil } }
    }

    private func position(at now: Date) -> String {
        guard let started = playing.started, let audio else { return "–" }
        let elapsed = String(format: "%.3f", (playing.finished ?? now).timeIntervalSince(started))
        if playing.finished != nil { return "finished after \(elapsed) s" }
        guard let p = audio.position() else { return "a pause, after \(audio.clipsDone()) clips · \(elapsed) s" }
        return "clip \(p.clip) at \(String(format: "%.3f", p.seconds)) s · \(elapsed) s"
    }

    // ----- Nodes -----

    @ViewBuilder private func nodes(_ map: GameMap) -> some View {
        Section("Nodes") {
            TextField("Filter", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ForEach(map.nodes.keys.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }, id: \.self) {
                id in
                if let node = map.nodes[id] {
                    HStack {
                        Text(id).font(.body.monospaced())
                        Spacer()
                        Button("Say") { play(map, node, reprompt: false) }
                            .buttonStyle(.borderless)
                            .disabled(node.say.isEmpty)
                        if node.ask != nil {
                            Button("Reprompt") { play(map, node, reprompt: true) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    // ----- Playing -----

    private func load() async {
        stop()
        audio?.release()
        audio = nil
        loaded = nil
        problem = nil
        guard let info = model.games.first(where: { $0.id == gameId }), let loader = model.loader else { return }
        let installed = model.packs.installed(info)
        do {
            loaded = try await loader.load(info, installed: installed)
            let player = model.makeAudio(info, installed)
            player.onFinished = { playing.finished = Date() }
            audio = player
        } catch {
            problem = "\(error)"
        }
    }

    private func play(_ map: GameMap, _ node: Node, reprompt: Bool) {
        do {
            // The node as the game would reach it from the start: the map's variables.
            let session = Session(map)
            try session.restore(Saved(node: node.id, vars: map.vars, ended: false))
            let steps = try session.resolve(reprompt ? node.ask?.reprompt ?? [] : node.say)
            start("\(node.id) · \(reprompt ? "reprompt" : "say")", steps)
        } catch {
            problem = "\(error)"
        }
    }

    /// Fifteen of Don's lines in a row, from a random place in the script: the seams between his clips.
    private func donSentence(_ nuclear: NuclearAudio) {
        guard let lines = try? Lines.all().map(\.text).filter({ nuclear.has($0) }), !lines.isEmpty else {
            problem = "No Don lines with clips"
            return
        }
        let from = Int.random(in: 0..<max(lines.count - 15, 1))
        let steps = lines[from..<min(from + 15, lines.count)].map { Step.play(nuclear.don($0)) }
        start("Don, lines \(from)–\(from + steps.count - 1)", Array(steps))
    }

    private func start(_ label: String, _ steps: [Step]) {
        playing = Playing(label: label, steps: steps, started: Date(), finished: nil)
        problem = nil
        audio?.play(steps)
    }

    private func stop() {
        audio?.stop()
        if playing.started != nil && playing.finished == nil { playing.finished = Date() }
    }
}

/**
 * The Audio Lab's look at the mic's gate: the listening sound on the lab's player (its cue node, as a game plays it),
 * then the mic (in the game's own session) heard from when the sound will have been heard out, as a game's listen is:
 * when that is, and the level of what comes through. With the speaker loud, nothing of the sound should show.
 */
@Observable
final class GateMeter {
    private(set) var level: Float = 0
    private(set) var note = ""
    @ObservationIgnored private var mic: MicInput?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var session: AudioSessionController?
    @ObservationIgnored private var engines: [AVAudioEngine] = []
    @ObservationIgnored private var ending: Task<Void, Never>?

    /// The sound on [player], then four seconds of the mic from the gate on.
    func run(_ player: TurnPlayer?) {
        stop()
        guard let player else {
            note = "Pick a game first: its player plays the sound"
            return
        }
        guard MicPermission.granted else {
            note = "The microphone isn't allowed"
            return
        }
        let session = AudioSessionController { _ in }
        self.session = session
        let mic = MicInput()
        do {
            try session.activate()
            try mic.start()
        } catch {
            note = "Can't listen: \(error)"
            stop()
            return
        }
        self.mic = mic
        let tapped = ContinuousClock.now
        guard let after = player.play(.listenStart) else {
            note = "The listening sound can't play"
            stop()
            return
        }
        engines = [player.engine, mic.engine].compactMap { $0 }
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request
        note = "The mic is heard from \(Int((after - tapped) / .milliseconds(1))) ms after the tap"
        let meter = self
        mic.feed(request, from: SpeechListener.hostTime(after)) { level in
            DispatchQueue.main.async { MainActor.assumeIsolated { meter.level = level } }
        }
        ending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.stop()
        }
    }

    func stop() {
        ending?.cancel()
        ending = nil
        if let request { mic?.unfeed(request) }
        request = nil
        mic?.stop()
        mic = nil
        session?.deactivate(stopping: engines)
        session = nil
        engines = []
        level = 0
    }
}
#endif
