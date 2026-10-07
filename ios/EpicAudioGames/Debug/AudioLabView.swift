// No Kotlin counterpart: the Audio Lab (Debug builds), to hear any node of any game through the app's turn player.

#if DEBUG
import EpicAppCore
import SwiftUI

/**
 * Plays any node's say or reprompt (with the map's starting variables), or a run of Don's lines, through the same
 * TurnPlaying the games use, with where the playlist is: the clip, the seconds into it, and the time since it began.
 * Opened by a long press on the game list's title.
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
                        audio?.release()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { if gameId.isEmpty { gameId = model.games.first?.id ?? "" } }
        .task(id: gameId) { await load() }
        .onDisappear { audio?.release() }
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
#endif
