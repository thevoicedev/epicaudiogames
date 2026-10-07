// AlexaReplayTest.kt: replays the walks tools/parity.js recorded in the real Alexa skills.

import Foundation
import Testing

@testable import EpicEngine

/**
 * Replays the walks that tools/parity.js recorded in the real Alexa skill: every turn must play the same clips, in
 * the same order, and end or leave the game at the same time. Where the skill picked a random branch, the engine
 * is given the same pick. Skipped when there are no recordings (they need the all-minigames-sites repo).
 */
struct AlexaReplayTests {
    /// A turn where a map deliberately differs from the skill. The walk stops there.
    private struct Known {
        let why: String
        let applies: (_ at: String, _ said: String, _ alexa: [String], _ ours: [String]) -> Bool
    }

    private let known = [
        Known(
            why: "Signal Decoders: the skill also hears \"one\" (a follow word) in \"the second one\" and asks again; the "
                + "map takes the longer phrase, hide, which is why the skill lists \"the second one\" as a hide word"
        ) { at, said, _, _ in
            at == "ai-choice" && said == "the second one"
        },
        Known(
            why: "Frootopia: the app has stories 2 to 5 (in a pack), so story 1's ending plays its teaser for story 2, as "
                + "the skill does when its series is switched on (FROOTOPIA_SERIES)"
        ) { _, _, alexa, ours in
            ours == alexa + ["scenes/fr-sting"]
        },
        // fixed: the skills took "of course not" and "I'm not sure" as a yes, and "I don't know" as a no
        Known(
            why: "A negated phrase without an opposite (\"of course not\", \"probably not\", \"let's not hide\") doesn't "
                + "count, and an answer that isn't sure (\"I'm not sure\", \"I don't know\") is neither yes nor no"
        ) { _, said, _, _ in
            let t = SpokenText.normalise(said)
            return SpokenText.unsure(t)
                || t.split(separator: " ").contains { ["don't", "dont", "not", "never"].contains(String($0)) }
        },
        // fixed: the skills' digit reader took "to", "for", "won" and "oh" for numbers anywhere ("I want to play" was 2)
        Known(why: "\"To\", \"too\", \"for\", \"fore\", \"won\" and \"oh\" are numbers only next to another number") {
            _, said, _, _ in
            SpokenText.normalise(said).split(separator: " ").contains {
                ["to", "too", "for", "fore", "won", "oh"].contains(String($0))
            }
        },
        // fixed: Noodle Rush's skill asked again on everyday yeses and noes ("okay", "let's do it", "no way")
        Known(
            why: "Noodle Rush takes more ways to say yes and no (\"okay\", \"let's do it\", \"no way\", \"I'm ready\"), "
                + "where the skill only asked the question again"
        ) { _, said, alexa, _ in
            Self.noodleRushWords.contains(SpokenText.normalise(said)) && alexa.count == 1
                && alexa[0].hasPrefix("prompts/")
        },
    ]

    /// The exact-match answers Noodle Rush's map gained after the recordings were made.
    private static let noodleRushWords = Set([
        "all right", "alright", "i do", "i don't", "i don't want to", "i want to", "i would", "i wouldn't",
        "i'm ready", "im ready", "let's do it", "let's go", "let's play", "lets do it", "lets go", "lets play",
        "no i don't", "no i wouldn't", "no thank you", "no way", "not now", "ok", "okay", "ready", "sure thing",
        "yeah i'm ready", "yeah let's go", "yes i do", "yes i want to", "yes i would", "yes i'm ready",
        "yes let's go", "yes let's play",
    ].map { SpokenText.normalise($0) })

    private static let knownStop = "known"

    /// tools/cache/parity, next to games/.
    private static var recordings: URL? { TestRepo.root?.appendingPathComponent("tools/cache/parity") }

    /// The recordings, by name.
    private static func files() -> [URL] {
        guard let dir = recordings else { return [] }
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasSuffix(".json") }
            .sorted { Kt.utf16Less($0.lastPathComponent, $1.lastPathComponent) }
    }

    @Test(.enabled(if: !AlexaReplayTests.files().isEmpty, "no recordings in tools/cache/parity (run node tools/parity.js)"))
    func mapsPlayWhatAlexaPlays() throws {
        let files = Self.files()
        var problems: [String] = []
        for file in files {
            let root = try JSONParser.parse(Data(contentsOf: file)).jsonObject()
            let id = try value(root, "game").primitiveContent()
            let map = try GameMap.load(TestRepo.games().appendingPathComponent("\(id)/map.json"))
            let walks = try value(root, "walks").jsonArray().map { w in
                try value(w.jsonObject(), "turns").jsonArray().map { try $0.jsonObject() }
            }
            var agreed = 0
            var stopped = 0
            var mine: [String] = []
            for (w, turns) in walks.enumerated() {
                switch try replay(map, turns) {
                case nil: agreed += 1
                case Self.knownStop?: stopped += 1
                case let problem?: mine.append("\(id) walk \(w + 1): \(problem)")
                }
            }
            problems += mine.prefix(8)
            print(
                "\(id): \(walks.reduce(0) { $0 + $1.count }) turns in \(walks.count) walks: \(agreed) the same as Alexa"
                    + (stopped > 0 ? ", \(stopped) the same up to a known difference" : ""))
        }
        #expect(problems.isEmpty, Comment(rawValue: "\n" + problems.prefix(15).joined(separator: "\n")))
    }

    /// Kotlin's getValue: the key's value, or a failure.
    private func value(_ o: JSONObject, _ key: String) throws -> JSON {
        try #require(o[key], "no \"\(key)\" in \(JSON.object(o).kotlinxDescription.prefix(200))")
    }

    /// Kotlin's List.toString: "[a, b]".
    private func listText(_ list: [String]) -> String { "[" + list.joined(separator: ", ") + "]" }

    /// Nil if the engine plays the walk exactly as Alexa did, else what differed.
    private func replay(_ map: GameMap, _ turns: [JSONObject]) throws -> String? {
        var session = Session(map) { _ in 0 }
        let first = try #require(turns.first)
        let at = try first["node"].map { try $0.primitiveContent() }
        if try value(first, "said").primitiveContent() == "@at", let at {
            try session.restore(Saved(node: at, vars: [:], ended: false))      // a grid cell: straight to the question
        } else if let why = try differs(session.start(), first) {
            return "launch: \(why)"
        }
        for i in 1..<Swift.max(1, turns.count) {
            let recorded = turns[i]
            let said = try value(recorded, "said").primitiveContent()
            let saved = session.save()
            var firstTry: String? = nil
            var next: Session? = nil
            for k in 0..<4 {
                let s = Session(map) { n in k % n }
                try s.restore(saved)
                let turn = try said == "@next" ? s.nextChapter() : s.answer(said)
                let why = try differs(turn, recorded)
                if why == nil {
                    next = s
                    break
                }
                if firstTry == nil { firstTry = "(heard: \(turn.heard?.how ?? "null")) \(why!)" }
            }
            guard let next else {
                let alexa = try value(recorded, "clips").jsonArray().map { try $0.primitiveContent() }
                let s = Session(map) { _ in 0 }
                try s.restore(saved)
                let ours = try (said == "@next" ? s.nextChapter() : s.answer(said)).steps.compactMap {
                    if case .play(let p) = $0 { p.path } else { nil }
                }
                if known.contains(where: { $0.applies(saved.node, said, alexa, ours) }) { return Self.knownStop }
                return "turn \(i + 1) at \(saved.node), \"\(said)\": \(firstTry ?? "null")"
            }
            session = next
        }
        return nil
    }

    private func differs(_ turn: Turn, _ recorded: JSONObject) throws -> String? {
        let alexa = try value(recorded, "clips").jsonArray().map { try $0.primitiveContent() }
        let ours = turn.steps.compactMap { if case .play(let p) = $0 { p.path } else { nil } }
        let phase = turn.quit ? "left" : turn.end != nil ? "over" : "playing"
        let alexaPhase = try value(recorded, "phase").primitiveContent()
        if ours != alexa { return "Alexa played \(listText(alexa)), the map \(listText(ours))" }
        if phase != alexaPhase {
            let state = try recorded["state"].map { try $0.primitiveContent() } ?? "null"
            return "Alexa is \(alexaPhase) (\(state)), the map \(phase)"
        }
        return nil
    }
}
