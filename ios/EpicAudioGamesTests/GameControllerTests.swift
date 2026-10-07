// GameController.kt's behaviour, with fake audio, listening and saves (Android has no tests of its own for it).

import EpicAppCore
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import EpicAudioGames

/// A small game: a question whose lines join (a comma), a chapter end, a second chapter, a game over and the leaves.
private let mapJSON = """
{
 "format": 1, "id": "test", "title": "Test", "start": "q1",
 "vars": { "score": 0 },
 "who": { "NARRATOR": "Narrator", "PIP": "Pip" },
 "words": { "yes": ["=yes"], "no": ["=no"], "repeat": ["say that again"] },
 "nodes": {
  "q1": {
   "say": [ { "play": "scenes/q1", "dur": 4, "lines": [
     { "at": 0, "len": 2, "who": "PIP", "text": "Hello there," },
     { "at": 2, "len": 2, "who": "PIP", "text": "do you want cake?" } ] } ],
   "ask": {
    "reprompt": [ { "play": "prompts/q1", "dur": 1, "lines": [
      { "at": 0, "len": 1, "who": "NARRATOR", "text": "Cake? Say yes or no." } ] } ],
    "answers": [
     { "yes": true, "go": "c1end" },
     { "no": true, "go": "over" },
     { "words": ["later"], "go": { "end": "leave" } },
     { "words": ["goodbye"], "go": { "end": "quit" } }
    ],
    "else": "c1end",
    "buttons": [ { "label": "Yes please, cake", "value": "  yes  " }, { "label": "No", "value": "no" } ]
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

/// Two questions: the first's else goes on to the second, which has no else (it asks again).
private let twoQuestionsJSON = """
{
 "format": 1, "id": "test", "title": "Test", "start": "a1",
 "vars": {},
 "who": { "PIP": "Pip" },
 "words": { "yes": ["=yes"], "no": ["=no"] },
 "nodes": {
  "a1": {
   "say": [ { "play": "scenes/a1", "dur": 1, "lines": [ { "at": 0, "len": 1, "who": "PIP", "text": "First?" } ] } ],
   "ask": {
    "reprompt": [ { "play": "prompts/a1", "dur": 1, "lines": [ { "at": 0, "len": 1, "who": "PIP", "text": "1?" } ] } ],
    "answers": [ { "yes": true, "go": "a2" } ],
    "else": "a2",
    "buttons": [ { "label": "Yes", "value": "yes" } ]
   }
  },
  "a2": {
   "say": [ { "play": "scenes/a2", "dur": 1, "lines": [ { "at": 0, "len": 1, "who": "PIP", "text": "Second?" } ] } ],
   "ask": {
    "reprompt": [ { "play": "prompts/a2", "dur": 1, "lines": [ { "at": 0, "len": 1, "who": "PIP", "text": "2?" } ] } ],
    "answers": [ { "yes": true, "go": "a1" } ],
    "buttons": [ { "label": "Yes", "value": "yes" } ]
   }
  }
 }
}
"""

/// Nuclear War's clips.json, as the app bundles it.
private let nuclearClips = Bundle.main.url(forResource: "clips", withExtension: "json", subdirectory: "Games/nuclear-war")

/// The audio: it plays nothing, and finishes a turn when the test says.
@MainActor
final class FakeAudio: TurnPlaying {
    var onFinished: (@MainActor @Sendable () -> Void)?
    var onStalled: (@MainActor @Sendable () -> Void)?
    var played: [[Step]] = []
    var stops = 0
    var now: ClipPosition?
    var done = 0

    func play(_ steps: [Step]) { played.append(steps) }
    func stop() { stops += 1 }
    func position() -> ClipPosition? { now }
    func clipsDone() -> Int { done }
    func release() {}

    /// The turn's audio has played to its end.
    func finish() { onFinished?() }

    /// The turn's audio couldn't start (a call has the audio).
    func stall() { onStalled?() }
}

/// The listener: it hears what the test says.
@MainActor
final class FakeListener: Listening {
    var events = ListenerEvents()
    var isAvailable = true
    var starts = 0
    var stops = 0

    func start(hints: [String]) { starts += 1 }
    func stop() { stops += 1 }
    func release() {}
}

/// Saves in memory, counting what's written and cleared.
final class FakeSaves: SaveStore, @unchecked Sendable {
    let memory: MemorySaveStore
    private(set) var stored: [Saved] = []
    private(set) var clears = 0

    init(_ json: [String: String] = [:]) {
        memory = MemorySaveStore(json)
    }

    func load(_ game: String) -> Saved? { memory.load(game) }

    func store(_ game: String, _ saved: Saved) {
        stored.append(saved)
        memory.store(game, saved)
    }

    func clear(_ game: String) {
        clears += 1
        memory.clear(game)
    }
}

/// A game that fails where it's told to, as Nuclear War does on a save it can't read, or an engine error would.
final class FailingPlay: Play {
    let inner: Session
    var failOpeningSaves = false
    var failAnswers = false

    init(_ inner: Session) { self.inner = inner }

    var who: LinkedMap<String> { inner.who }
    var ask: Ask? { inner.ask }
    func start() throws -> Turn { try inner.start() }
    func canResume(_ saved: Saved) -> Bool { inner.canResume(saved) }
    func resume(_ saved: Saved) throws -> Turn {
        if failOpeningSaves { throw PlayError("bad state") }
        return try inner.resume(saved)
    }
    func open(_ saved: Saved?) throws -> Turn {
        if saved != nil && failOpeningSaves { throw PlayError("bad state") }
        return try inner.open(saved)
    }
    func answer(_ said: String) throws -> Turn {
        if failAnswers { throw PlayError("the game broke") }
        return try inner.answer(said)
    }
    func silence() throws -> Turn { try inner.silence() }
    func restart(at: String?) throws -> Turn { try inner.restart(at: at) }
    func nextChapter() throws -> Turn { try inner.nextChapter() }
    func hasChapter(_ next: String) -> Bool { inner.hasChapter(next) }
    func save() -> Saved { inner.save() }
    func understands(_ said: String) throws -> Bool { try inner.understands(said) }
}

@MainActor
struct GameControllerTests {
    let info = GameInfo(id: "test", title: "Test", blurb: "", free: "", packs: [])
    let map: GameMap
    let audio = FakeAudio()
    let listener = FakeListener()
    let saves: FakeSaves
    /// How many times the game went back to the list.
    let left = Counter()

    final class Counter {
        var count = 0
    }

    init() throws {
        map = try GameMap.parse(data: Data(mapJSON.utf8))
        saves = FakeSaves()
    }

    init(saves: FakeSaves) throws {
        map = try GameMap.parse(data: Data(mapJSON.utf8))
        self.saves = saves
    }

    private func controller(_ game: (any Play)? = nil, mic: Bool = false) -> GameController {
        let map = map
        let left = left
        let c = GameController(
            info: info, game: game ?? Session(map), fresh: { Session(map) },
            dependencies: GameDependencies(saves: saves, audio: audio, listener: listener),
            onLeave: { _ in left.count += 1 })
        c.micAllowed = mic
        c.doubleTap = .zero         // the tests tap at once
        return c
    }

    private func twoQuestions() throws -> Session {
        Session(try GameMap.parse(data: Data(twoQuestionsJSON.utf8)))
    }

    private func spoken(_ c: GameController) -> [String] {
        c.feed.compactMap { if case .spoken(_, _, let text) = $0.kind { text } else { nil } }
    }

    private func replies(_ c: GameController) -> [String] {
        c.feed.compactMap { if case .reply(let text) = $0.kind { text } else { nil } }
    }

    private func notes(_ c: GameController) -> [String] {
        c.feed.compactMap { if case .note(let text) = $0.kind { text } else { nil } }
    }

    /// Waits (up to a second) for something the controller does later: its ticker, or going back to the list.
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // ----- Turns -----

    @Test func theFirstTurnPlaysAndShowsItsButtonsAtOnce() {
        let c = controller()
        c.open()
        #expect(audio.played.count == 1)
        #expect(c.speaking)
        #expect(c.ask?.buttons.count == 2)
        #expect(c.feed.isEmpty)
        #expect(saves.stored.isEmpty)
    }

    @Test func linesShowAsTheVoiceReachesThem() async throws {
        let c = controller()
        c.open()
        audio.now = ClipPosition(clip: 0, seconds: 1)
        try await eventually { !c.feed.isEmpty }
        #expect(spoken(c) == ["Hello there,"])
        #expect(c.activeEntry == 0)
        #expect(c.activeChars == 6)     // half of "Hello there," (12 units)
        // The next line carries on the sentence (the comma): it joins the entry, and the highlight follows it.
        audio.now = ClipPosition(clip: 0, seconds: 3)
        try await eventually { c.activeChars > 12 }
        #expect(spoken(c) == ["Hello there, do you want cake?"])
        #expect(c.activeChars == 13 + 8)    // its offset, and half of "do you want cake?" (17 units)
        c.close()
    }

    @Test func aSkipNeverFinishesTwice() {
        let c = controller(mic: true)
        c.open()
        c.skip()
        #expect(!c.speaking)
        #expect(spoken(c) == ["Hello there, do you want cake?"])
        #expect(saves.stored.count == 1)
        #expect(listener.starts == 1)
        c.skip()
        audio.finish()      // a late finish for the turn that was skipped
        #expect(saves.stored.count == 1)
        #expect(listener.starts == 1)
        #expect(audio.played.count == 1)
    }

    @Test func aTurnFinishesOnce() {
        let c = controller()
        c.open()
        audio.finish()
        audio.finish()
        #expect(saves.stored.count == 1)
        #expect(spoken(c) == ["Hello there, do you want cake?"])
    }

    @Test func answeringWhileSpeakingStopsTheVoiceAndShowsTheRest() {
        let c = controller()
        c.open()
        #expect(c.feed.isEmpty)
        let stops = audio.stops
        c.answer("no")
        #expect(audio.stops > stops)
        #expect(spoken(c).first == "Hello there, do you want cake?")
        #expect(replies(c) == ["no"])
        #expect(audio.played.count == 2)
        #expect(c.speaking)        // the answer's turn
        #expect(saves.stored.isEmpty)
    }

    @Test func aTappedButtonSendsItsValueAndShowsItsLabel() throws {
        let c = controller()
        c.open()
        audio.finish()
        let button = try #require(c.ask?.buttons.first)
        #expect(button.label == "Yes please, cake")
        c.tap(button)
        // fixed: the reply showed the value ("yes"); it shows what the player tapped.
        #expect(replies(c) == ["Yes please, cake"])
        #expect(c.speaking)
        audio.finish()
        #expect(c.end?.kind == "chapter")       // the value was sent
    }

    /// Nuclear War's buttons say one thing and send another ("the USA" sends "USA"): the reply shows the label.
    @Test(.enabled(if: nuclearClips != nil, "no Games/nuclear-war/clips.json in the app"))
    func aNuclearWarButtonShowsItsLabel() throws {
        let audioFile = try #require(nuclearClips)
        let nuclear = try NuclearAudio.load(audioFile)
        let c = controller(NuclearWar(audio: nuclear, random: XorWowRandom(seed: 7)))
        c.open()
        audio.finish()
        let buttons = try #require(c.ask?.buttons)
        let button = try #require(buttons.first { $0.label != $0.value })
        c.tap(button)
        // fixed: it showed the value ("USA" for "the USA").
        #expect(replies(c) == [Kt.trim(button.label)])
        #expect(replies(c) != [button.value])
    }

    /// A double tap: the second tap lands on the next question's buttons, drawn at once in the same places. It's let
    /// go; a tap after a moment answers.
    @Test func aDoubleTapDoesntAnswerTheNextQuestion() async throws {
        let c = controller(try twoQuestions())
        c.doubleTap = .milliseconds(300)
        c.open()
        audio.finish()
        try await Task.sleep(for: .milliseconds(350))
        let yes = try #require(c.ask?.buttons.first)
        c.tap(yes)
        #expect(replies(c) == ["Yes"])
        #expect(audio.played.count == 2)
        c.tap(yes)                              // fixed: it answered the second question, never heard
        #expect(replies(c) == ["Yes"])
        #expect(audio.played.count == 2)
        try await Task.sleep(for: .milliseconds(350))
        c.tap(yes)
        #expect(replies(c) == ["Yes", "Yes"])
        #expect(audio.played.count == 3)
    }

    @Test func blankAnswersAreIgnored() {
        let c = controller()
        c.open()
        audio.finish()
        c.answer("   ")
        #expect(replies(c).isEmpty)
        #expect(audio.played.count == 1)
    }

    /// Typed while paused (the keyboard still up): the answer carries on, and the next question listens.
    @Test func answeringWhilePausedCarriesOn() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        c.answer("stop")
        #expect(c.paused)
        c.answer("say that again")
        // fixed: the turn played under the pause, which stayed, and the mic never opened after it.
        #expect(!c.paused)
        #expect(replies(c) == ["say that again"])
        audio.finish()
        #expect(c.listening)
    }

    @Test func stopPausesTheGame() {
        let c = controller()
        c.open()
        c.answer("Stop")
        #expect(c.paused)
        #expect(!c.speaking)
        #expect(replies(c).isEmpty)
        #expect(saves.stored.count == 1)        // the turn finished, waiting
        c.carryOn()
        #expect(!c.paused)
        #expect(audio.played.count == 2)        // the question again
    }

    // ----- Silence -----

    @Test func aSilenceRepromptsAndASecondPauses() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        #expect(listener.starts == 1)
        listener.events.silence()
        #expect(!c.paused)
        #expect(audio.played.count == 2)        // the reprompt
        audio.finish()
        #expect(listener.starts == 2)
        listener.events.silence()
        #expect(c.paused)
        #expect(audio.played.count == 2)
    }

    @Test func speechNotMadeOutCountsAsASilence() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        listener.events.heard([])
        #expect(replies(c) == ["…"])
        #expect(c.speaking)                      // the else: the chapter's end
        #expect(audio.played.count == 2)
    }

    @Test func theFirstGuessTheQuestionTakesIsAnswered() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        listener.events.heard(["jess", "yes"])
        #expect(replies(c) == ["yes"])
    }

    /// fixed: NEXT CHAPTER kept a silence from the chapter before, so the next one's first silence paused.
    @Test func silencesAreResetByNextChapter() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        listener.events.heard([])               // a silence, and the else: the chapter's end
        audio.finish()
        #expect(c.end?.kind == "chapter")
        #expect(c.canGoOn)
        c.nextChapter()
        audio.finish()
        #expect(c.ask != nil)
        listener.events.silence()               // the first silence of the new chapter: the question again
        #expect(!c.paused)
        audio.finish()
        listener.events.silence()
        #expect(c.paused)
    }

    /// fixed: PLAY AGAIN kept a silence from the game before, so the new game's first silence paused.
    @Test func silencesAreResetByPlayAgain() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        c.answer("yes")
        audio.finish()
        c.nextChapter()
        audio.finish()
        listener.events.heard([])               // a silence, and the else: game over
        audio.finish()
        #expect(c.end?.kind == "gameover")
        c.playAgain()
        #expect(notes(c) == ["Starting again!"])
        audio.finish()
        #expect(c.ask != nil)
        listener.events.silence()
        #expect(!c.paused)
        audio.finish()
        listener.events.silence()
        #expect(c.paused)
    }

    /// Speech not made out that moves the game on to a new question: that question gets its own "say it again".
    @Test func silencesStartAgainAtANewQuestion() throws {
        let c = controller(try twoQuestions(), mic: true)
        c.open()
        audio.finish()
        listener.events.heard([])               // the else: on to the second question
        audio.finish()
        #expect(c.ask != nil)
        listener.events.silence()               // fixed: its first silence paused at once
        #expect(!c.paused)
        audio.finish()
        listener.events.heard([])               // at the same question, the second running
        #expect(c.paused)
    }

    @Test func anAnswerResetsTheSilences() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        listener.events.silence()
        audio.finish()
        c.answer("say that again")
        audio.finish()
        listener.events.silence()
        #expect(!c.paused)
    }

    // ----- Saves -----

    @Test func theSaveIsWrittenAtTheTurnsEnd() {
        let c = controller()
        c.open()
        #expect(saves.stored.isEmpty)
        audio.finish()
        #expect(saves.stored.map(\.node) == ["q1"])
        c.answer("yes")
        #expect(saves.stored.count == 1)        // not while the answer's turn plays
        audio.finish()
        #expect(saves.stored.last?.node == "c1end")
        #expect(saves.stored.last?.ended == true)
    }

    @Test func leavingKeepsThePlace() async throws {
        let c = controller()
        c.open()
        audio.finish()
        c.answer("later")
        audio.finish()
        #expect(saves.stored.last?.node == "q1")
        #expect(saves.clears == 0)
        try await eventually { left.count > 0 }
        #expect(left.count == 1)
    }

    /// fixed: a plain quit cleared the save, and the map's "keep" variables with it. Its save is kept, as ended, so it
    /// isn't picked up again.
    @Test func quittingKeepsAnEndedSave() async throws {
        let c = controller()
        c.open()
        audio.finish()
        c.answer("goodbye")
        audio.finish()
        #expect(saves.clears == 0)
        #expect(saves.stored.last?.ended == true)
        #expect(!saves.inProgress("test"))
        try await eventually { left.count > 0 }
        #expect(left.count == 1)
    }

    /// A save at a place the map doesn't have (its pack missing) is kept aside, not overwritten by the fresh game; once
    /// the map has the place again, it's picked up.
    @Test func aSaveAtAPlaceTheMapHasntIsKeptAside() throws {
        let saves = FakeSaves(["test": #"{"node":"fr9","vars":{"score":3},"ended":false}"#])
        let t = try GameControllerTests(saves: saves)
        let c = t.controller()
        c.open()
        #expect(saves.load("test.parked")?.node == "fr9")
        t.audio.finish()
        #expect(saves.load("test")?.node == "q1")
        #expect(saves.load("test.parked")?.node == "fr9")
        // Its place back (here a place the map has, as a pack's would be once installed).
        saves.store("test.parked", Saved(node: "c2", vars: saves.load("test")!.vars, ended: false))
        let back = try GameControllerTests(saves: saves)
        let d = back.controller()
        d.open()
        #expect(back.notes(d) == ["Welcome back!"])
        #expect(saves.load("test.parked") == nil)
        #expect(saves.load("test")?.node == "c2")
    }

    @Test func aSaveAtAQuestionIsPickedUp() throws {
        let saves = FakeSaves(["test": #"{"node":"c2","vars":{"score":3},"ended":false}"#])
        let t = try GameControllerTests(saves: saves)
        let c = t.controller()
        c.open()
        #expect(t.notes(c) == ["Welcome back!"])
        let clips = t.audio.played.first?.compactMap { if case .play(let clip) = $0 { clip.path } else { nil } }
        #expect(clips == ["scenes/c2"])
    }

    @Test func aSaveAtAnEndStartsAfresh() throws {
        let saves = FakeSaves(["test": #"{"node":"over","vars":{"score":3},"ended":true}"#])
        let t = try GameControllerTests(saves: saves)
        let c = t.controller()
        c.open()
        #expect(t.notes(c).isEmpty)
        let clips = t.audio.played.first?.compactMap { if case .play(let clip) = $0 { clip.path } else { nil } }
        #expect(clips == ["scenes/q1"])
    }

    /// L11: a save the game can't open is cleared, and the game starts afresh.
    @Test func aSaveThatCantBeOpenedStartsAFreshGame() throws {
        let saves = FakeSaves(["test": #"{"node":"q1","vars":{"state":"{broken"},"ended":false}"#])
        let t = try GameControllerTests(saves: saves)
        let broken = FailingPlay(Session(t.map))
        broken.failOpeningSaves = true
        let c = t.controller(broken)
        c.open()
        #expect(saves.clears == 1)
        #expect(t.notes(c).isEmpty)
        #expect(c.speaking)
        #expect(t.audio.played.count == 1)
        t.audio.finish()
        #expect(saves.stored.last?.node == "q1")
    }

    @Test func aSaveThatCantBeReadStartsAfresh() throws {
        let saves = FakeSaves(["test": "{not json"])
        let t = try GameControllerTests(saves: saves)
        let c = t.controller()
        c.open()
        #expect(t.notes(c).isEmpty)
        t.audio.finish()
        #expect(saves.load("test")?.node == "q1")
    }

    // ----- Errors -----

    /// L1: an engine error is a note, and back to the list.
    @Test func anEngineErrorGoesBackToTheList() async throws {
        let broken = FailingPlay(Session(map))
        broken.failAnswers = true
        let c = controller(broken)
        c.open()
        audio.finish()
        c.answer("yes")
        #expect(notes(c) == ["Sorry, the game went wrong."])
        #expect(!c.speaking)
        // fixed (B037): the list showed the error's own text; it says so plainly (the error goes to the log).
        #expect(c.failure == "Test went wrong and had to stop.")
        #expect(saves.stored.count == 1)        // the last turn's save is kept
        try await eventually { left.count > 0 }
        #expect(left.count == 1)
    }

    // ----- Listening -----

    @Test func theMicIsOffWhenListeningIsUnavailable() async throws {
        listener.isAvailable = false
        let c = controller(mic: true)
        #expect(!c.micWorks)
        c.open()
        audio.finish()
        #expect(listener.starts == 0)
        // The real stand-in says so when asked to listen.
        let unavailable = UnavailableListener()
        let d = GameController(
            info: info, game: Session(map), fresh: { [map] in Session(map) },
            dependencies: GameDependencies(saves: FakeSaves(), audio: FakeAudio(), listener: unavailable),
            onLeave: { _ in })
        d.micAllowed = true
        d.mic()
        #expect(d.micWorks)
        d.open()
        d.skip()
        #expect(d.listening)
        try await eventually { !d.micWorks }
        #expect(!d.listening)
        #expect(!d.micWorks)
    }

    /// Typing is the answer coming: the mic stops, and doesn't open by itself; the mic button still listens.
    @Test func typingStopsListeningAndTheMicWaits() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        listener.events.silence()               // one silence: the question again
        audio.finish()
        #expect(c.listening)
        c.typing = true
        // fixed: the mic listened on while the player typed; its silences asked again, then paused.
        #expect(!c.listening)
        c.answer("say that again")
        audio.finish()
        #expect(!c.listening)
        #expect(listener.starts == 2)
        c.mic()
        #expect(c.listening)
        c.typed()
        #expect(!c.listening)
        c.typing = false
        c.mic()
        listener.events.silence()               // the silences counted from nothing again
        #expect(!c.paused)
    }

    /// The mic couldn't start (Android's busy recogniser, the mic in use): the listen ends, with no silence counted.
    @Test func troubleWithTheMicIsntASilence() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        #expect(c.listening)
        listener.events.trouble()
        // fixed: it asked the question again at once and counted a silence (the next paused).
        #expect(!c.listening)
        #expect(audio.played.count == 1)
        c.mic()
        #expect(c.listening)
        listener.events.silence()
        #expect(!c.paused)
    }

    /// What the listener reports once listening has stopped (a result already on its way) is let go.
    @Test func whatIsHeardAfterListeningStoppedIsLetGo() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        c.mic()                                 // stops listening
        #expect(!c.listening)
        listener.events.heard(["yes"])
        listener.events.heard([])
        listener.events.silence()
        #expect(replies(c).isEmpty)
        #expect(audio.played.count == 1)
    }

    /// The mic allowed later (in Settings): the game listens if it waits for an answer, not while paused.
    @Test func allowingTheMicListensUnlessPaused() {
        let c = controller(mic: false)
        c.open()
        audio.finish()
        c.allowMic()
        #expect(c.listening)
        let d = controller(mic: false)
        d.open()
        audio.finish()
        d.pause()
        d.allowMic()
        #expect(d.micAllowed)
        #expect(!d.listening)
    }

    /// D8: with VoiceOver on, the game doesn't open the mic by itself (it would hear VoiceOver), nor once the mic is
    /// allowed; the player opens it (Magic Tap, Talk), and a sound says so.
    @Test func withVoiceOverTheGameWaitsForThePlayerToTalk() {
        let c = controller(mic: true)
        c.listensByItself = { false }
        var sounds = 0
        c.onListen = { sounds += 1 }
        c.open()
        audio.finish()
        #expect(!c.listening)
        #expect(listener.starts == 0)
        c.mic()
        #expect(c.listening)
        #expect(sounds == 1)
        c.mic()
        #expect(!c.listening)
        let d = controller(mic: false)
        d.listensByItself = { false }
        d.open()
        audio.finish()
        d.allowMic()
        #expect(d.micAllowed)
        #expect(!d.listening)
    }

    @Test func listeningTwiceStartsOnce() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        #expect(c.listening)
        c.listen()
        #expect(listener.starts == 1)
        c.mic()                                  // the mic while listening stops it
        #expect(!c.listening)
    }

    /// GameScreen.kt: with the mic allowed and working, the status says so; listening, it shows the words.
    @Test func listeningReportsAsTheGameShowsIt() {
        let c = controller(mic: true)
        c.open()
        audio.finish()
        #expect(c.listening)
        listener.events.partial("yes pl")
        listener.events.level(0.5)
        #expect(c.partial == "yes pl")
        #expect(c.level == 0.5)
        listener.events.heard(["yes please"])
        #expect(!c.listening)
        #expect(c.partial == "")
        #expect(replies(c) == ["yes please"])
        // Not allowed (the player said no): the game never listens, and the mic stays off.
        let d = controller(mic: false)
        d.open()
        audio.finish()
        #expect(!d.listening)
        d.mic()
        #expect(!d.listening)
    }

    /// Allowed once the turn has finished (the player answered the permission dialog late): listen() starts then.
    @Test func allowingTheMicLateListensAtOnce() {
        let c = controller(mic: false)
        c.open()
        audio.finish()
        let starts = listener.starts
        c.micAllowed = true
        c.listen()
        #expect(c.listening)
        #expect(listener.starts == starts + 1)
    }

    /// L2: a turn whose audio can't start at all (a call has it) shows its lines and waits for a tap, without
    /// listening; carrying on asks again.
    @Test func aTurnWhoseAudioCantPlayWaitsForATap() {
        let c = controller(mic: true)
        c.open()
        audio.stall()
        #expect(c.paused)
        #expect(!c.speaking)
        #expect(spoken(c) == ["Hello there, do you want cake?"])
        #expect(c.ask != nil)
        #expect(saves.stored.count == 1)
        #expect(listener.starts == 0)
        audio.finish()          // nothing more comes of it
        #expect(saves.stored.count == 1)
        c.carryOn()
        #expect(!c.paused)
        #expect(audio.played.count == 2)
        audio.finish()
        #expect(listener.starts == 1)
        // A stall for a turn that's over means nothing.
        audio.stall()
        #expect(!c.paused)
    }

    @Test func startAgainClearsTheFeed() {
        let c = controller()
        c.open()
        audio.finish()
        c.answer("no")
        c.startAgain()
        #expect(notes(c) == ["Starting again!"])
        #expect(replies(c).isEmpty)
        #expect(c.speaking)
    }
}

/// The bottom panels, laid out as Compose's verticalScroll lays them out: as tall as what's in them, and no taller
/// than the room they have (then they scroll).
@MainActor
struct PanelScrollTests {
    private func height(_ view: some View, room: CGFloat) -> CGFloat {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 320, height: room)).height
    }

    @Test func aPanelIsAsTallAsItsContentUpToItsRoom() {
        let panel = PanelScroll { Color.red.frame(height: 200) }
        #expect(height(panel, room: 1000) == 200)
        // fixed: short of room (a small phone, the keyboard up), the panel ran off the screen, its last buttons lost.
        #expect(height(panel, room: 120) == 120)
    }
}
