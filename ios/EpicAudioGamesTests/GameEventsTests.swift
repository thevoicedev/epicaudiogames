// GameEventsTest.kt: what a game tells the usage data, through GameController's onEvent.

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/// A question, a chapter end, a second chapter, a game over (GameEventsTest.kt's game).
private let cakeJSON = """
{
 "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
 "who": { "NARRATOR": "Narrator", "PIP": "Pip" },
 "words": { "yes": ["=yes"], "no": ["=no"], "repeat": ["say that again"] },
 "nodes": {
  "q1": {
   "say": [ { "play": "scenes/q1", "dur": 2, "lines": [
     { "at": 0, "len": 2, "who": "PIP", "text": "Do you want cake?" } ] } ],
   "ask": {
    "reprompt": [ { "play": "prompts/q1", "dur": 1, "lines": [
      { "at": 0, "len": 1, "who": "NARRATOR", "text": "Cake? Say yes or no." } ] } ],
    "answers": [ { "yes": true, "go": "c1end" }, { "no": true, "go": "over" } ],
    "else": "c1end",
    "buttons": [ { "label": "Yes please, cake", "value": "yes" }, { "label": "No", "value": "no" } ]
   }
  },
  "c1end": {
   "say": [ { "play": "scenes/c1end", "dur": 2, "lines": [
     { "at": 0, "len": 2, "who": "NARRATOR", "text": "Cake for everyone." } ] } ],
   "end": { "kind": "chapter", "title": "Chapter One", "next": "c2" }
  },
  "c2": {
   "say": [ { "play": "scenes/c2", "dur": 2, "lines": [
     { "at": 0, "len": 2, "who": "PIP", "text": "More cake?" } ] } ],
   "ask": {
    "reprompt": [ { "play": "prompts/c2", "dur": 1, "lines": [
      { "at": 0, "len": 1, "who": "PIP", "text": "More? Yes or no." } ] } ],
    "answers": [ { "yes": true, "go": "over" } ],
    "else": "over",
    "buttons": [ { "label": "Yes", "value": "yes" } ]
   }
  },
  "over": {
   "say": [ { "play": "scenes/over", "dur": 2, "lines": [
     { "at": 0, "len": 2, "who": "NARRATOR", "text": "Too much cake." } ] } ],
   "end": { "kind": "gameover", "title": "Oh no", "retry": "q1" }
  }
 }
}
"""

/// A free part that ends where a pack (not installed) carries on.
private let lockedJSON = """
{
 "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
 "nodes": {
  "q1": {
   "say": [ { "play": "scenes/q1", "dur": 1, "lines": [
     { "at": 0, "len": 1, "who": "NARRATOR", "text": "Ready?" } ] } ],
   "ask": { "answers": [ { "yes": true, "go": "free_end" } ], "else": "free_end" }
  },
  "free_end": {
   "say": [],
   "end": { "kind": "chapter", "title": "Part one", "next": "more1", "locked": "test-cake-more" }
  }
 }
}
"""

/**
 * What a game tells the usage data (GameController's onEvent; docs/DESIGN.md › Usage data): opened (and whether where
 * it was left), each end reached once (not again when it opens at one), the free part's end with the pack that has
 * what's next, the next chapter, a restart, the mic's answer, the game going wrong, and as it closes how it went: its
 * turns and time, and how many answers were typed, tapped and spoken and how many questions went unanswered (counts,
 * never the answers). Every event is one the whitelist takes. The fake audio of GameControllerTests: each turn plays
 * out when the test says. Android: GameEventsTest.kt.
 */
@MainActor
struct GameEventsTests {
    let audio = FakeAudio()
    let listener = FakeListener()
    let cues = FakeCues()
    let saves = FakeSaves()
    let events = TrackedEvents()
    let left = GameControllerTests.Counter()
    let info = GameInfo(id: "test-cake", title: "Cake", blurb: "", free: "", packs: [])

    /// A game on [json] (or [play]), opened, its first turn playing; the mic as [mic] says, not opening by itself.
    private func open(_ json: String = cakeJSON, play: (any Play)? = nil, mic: Bool = false) throws -> GameController {
        let map = try GameMap.parse(data: Data(json.utf8))
        let events = events
        let left = left
        let game = GameController(
            info: info, game: play ?? Session(map), fresh: { Session(map) },
            dependencies: GameDependencies(saves: saves, audio: audio, listener: listener, cues: cues),
            onLeave: { _ in left.count += 1 }, listensByItself: { false },
            onEvent: { name, props in events.add(Event(name: name, props: props)) })
        game.micAllowed = mic
        game.doubleTap = .zero          // the tests tap at once
        game.open()
        return game
    }

    /// The events since the last call; each one the whitelist takes.
    private func taken() -> [Event] {
        let got = events.take()
        for e in got { #expect(Events.problem(e.name, e.props) == nil, "\(e)") }
        return got
    }

    @Test func aPlayOfTheGameAsUsageData() throws {
        let game = try open()
        #expect(taken() == [Events.gameOpen("test-cake", resumed: false)])
        game.answer("yes")                                  // typed, cutting the voice short
        audio.finish()
        #expect(taken() == [Events.gameEnd("test-cake", kind: "chapter", node: "c1end")])
        game.nextChapter()
        #expect(taken() == [Events.chapterNext("test-cake", next: "c2")])
        audio.finish()
        game.tap(AnswerButton(label: "Yes", value: "yes"))  // tapped
        audio.finish()
        #expect(taken() == [Events.gameEnd("test-cake", kind: "gameover", node: "over")])
        game.playAgain()
        #expect(taken() == [Events.gameRestart("test-cake")])
        game.answer("stop")                                 // a pause, not an answer
        game.micAnswered(granted: false)
        #expect(taken() == [Events.micPermission(granted: false, where: .game)])
        game.close()
        let gone = taken()
        #expect(gone.count == 1)
        let leave = try #require(gone.first)
        #expect(leave.name == "game_leave")
        #expect(leave.props["game"] as? String == "test-cake")
        #expect(leave.props["node"] as? String == "q1")
        #expect(leave.props["turns"] as? Int == 5)          // q1, c1end, c2, over, q1 again
        #expect(leave.props["answers_typed"] as? Int == 1)
        #expect(leave.props["answers_tapped"] as? Int == 1)
        #expect(leave.props["answers_voice"] as? Int == 0)
        #expect(leave.props["silences"] as? Int == 0)
        #expect((0...60).contains(leave.props["seconds"] as? Int ?? -1))
        // Closed again: it's said once.
        game.close()
        #expect(taken().isEmpty)
    }

    /// Spoken answers and questions that went unanswered are counted, as the recogniser reports them.
    @Test func spokenAnswersAndSilencesAreCounted() throws {
        let game = try open(mic: true)
        _ = taken()
        audio.finish()
        game.listen()
        listener.events.silence()                           // nobody answered: the question again
        audio.finish()
        game.listen()
        listener.events.heard(["yes"])                      // spoken
        audio.finish()
        #expect(taken() == [Events.gameEnd("test-cake", kind: "chapter", node: "c1end")])
        game.close()
        let leave = try #require(taken().last)
        #expect(leave.props["answers_voice"] as? Int == 1)
        #expect(leave.props["answers_typed"] as? Int == 0)
        #expect(leave.props["silences"] as? Int == 1)
        #expect(leave.props["turns"] as? Int == 3)          // q1, its reprompt, c1end
    }

    @Test func openedAtAnEndReachedBeforeItIsntReachedAgain() throws {
        let first = try open()
        first.answer("yes")
        audio.finish()
        first.close()
        _ = taken()
        // Opened again, at the chapter's end with its next chapter here: picked up, but no second game_end.
        let again = try open()
        #expect(taken() == [Events.gameOpen("test-cake", resumed: true)])
        audio.finish()
        #expect(again.end?.kind == "chapter")
        #expect(taken().isEmpty)
        again.nextChapter()
        #expect(taken() == [Events.chapterNext("test-cake", next: "c2")])
    }

    @Test func theFreePartsEndSaysWhichPackHasWhatsNext() throws {
        let game = try open(lockedJSON)
        _ = taken()
        game.answer("yes")
        audio.finish()
        #expect(taken() == [
            Events.gameEnd("test-cake", kind: "chapter", node: "free_end"),
            Events.lockedEnd("test-cake", pack: "test-cake-more"),
        ])
    }

    @Test func aGameThatGoesWrongSaysWhere() async throws {
        let broken = FailingPlay(Session(try GameMap.parse(data: Data(cakeJSON.utf8))))
        broken.failAnswers = true
        let game = try open(play: broken)
        _ = taken()
        game.answer("yes")
        #expect(taken() == [Events.gameError("test-cake", node: "q1")])
        for _ in 0..<100 where left.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(left.count == 1)
    }

    /// A save that can't be opened (L11): the game starts afresh, so it isn't where it was left; and a save that can,
    /// at a question, is.
    @Test func aSaveThatCantBeOpenedStartsAfresh() throws {
        let broken = FailingPlay(Session(try GameMap.parse(data: Data(cakeJSON.utf8))))
        broken.failOpeningSaves = true
        saves.store("test-cake", Saved(node: "q1", vars: [:], ended: false))
        let game = try open(play: broken)
        #expect(taken() == [Events.gameOpen("test-cake", resumed: false)])
        game.close()
        _ = taken()
        saves.store("test-cake", Saved(node: "q1", vars: [:], ended: false))
        _ = try open()
        #expect(taken() == [Events.gameOpen("test-cake", resumed: true)])
    }
}

/// The events a game (or the store) told, as it told them.
@MainActor
final class TrackedEvents {
    private var events: [Event] = []

    func add(_ event: Event) {
        events.append(event)
    }

    /// The names of the events since the last take, which are kept.
    var names: [String] { events.map(\.name) }

    /// The events since the last take.
    func take() -> [Event] {
        defer { events = [] }
        return events
    }
}
