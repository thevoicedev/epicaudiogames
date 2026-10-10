// WearBridge.kt's on Android: the Apple Watch app's link (Watch/WatchBridge.swift), what the watch is told as a game
// goes, and its two buttons doing what Magic Tap and the pause do. The fakes are GameControllerTests'.

import EpicAppCore
import Foundation
import Observation
import Testing
@testable import EpicAudioGames

/// A question, a chapter end, a second chapter, a game over (GameEventsTests' game).
private let watchJSON = """
{
 "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
 "who": { "NARRATOR": "Narrator", "PIP": "Pip" },
 "words": { "yes": ["=yes"], "no": ["=no"] },
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

/// The app's games are in the bundle (the Mac's test host): the app's model can open one.
private let appGames = Bundle.main.url(forResource: "Games", withExtension: nil) != nil

/// The watch's end of the link: what it was told, in order, and its buttons, pressed as a test says.
@MainActor
final class FakeWatchLink: WatchLinking {
    var onCommand: (WatchCommand) -> Void = { _ in }
    var onReady: () -> Void = {}
    private(set) var starts = 0
    private(set) var told: [WatchState] = []

    func start() { starts += 1 }

    func tell(_ state: WatchState) { told.append(state) }

    /// A button pressed on the watch.
    func press(_ command: WatchCommand) { onCommand(command) }
}

/// The open game, as the app's model has it (observed, as AppModel.game is).
@MainActor
@Observable
final class OpenGame {
    var game: GameController?
}

@MainActor
struct WatchBridgeTests {
    let audio = FakeAudio()
    let listener = FakeListener()
    let cues = FakeCues()
    let saves = FakeSaves()
    let info = GameInfo(id: "test-cake", title: "Cake", blurb: "", free: "", packs: [])

    /// The game, opened, its first turn speaking; the mic as [mic] says, not opening by itself.
    private func open(mic: Bool = true) throws -> GameController {
        let map = try GameMap.parse(data: Data(watchJSON.utf8))
        let game = GameController(
            info: info, game: Session(map), fresh: { Session(map) },
            dependencies: GameDependencies(saves: saves, audio: audio, listener: listener, cues: cues),
            onLeave: { _ in }, listensByItself: { false })
        game.micAllowed = mic
        game.doubleTap = .zero          // the tests tap at once
        game.open()
        return game
    }

    private func state(
        _ words: String, _ action: WatchAction?, _ label: String, enabled: Bool = true, listening: Bool = false,
        canPause: Bool = true
    ) -> WatchState {
        WatchState(
            title: "Cake", state: words, action: action, label: label, enabled: enabled, listening: listening,
            canPause: canPause)
    }

    /// Waits (up to [timeout]) for what the bridge does a moment later: an observed change, told.
    private func until(_ timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// What the watch shows as a game goes: speaking, the player's turn, listening, paused, at an end; with none open,
    /// that there's none.
    @Test func theWatchSeesWhatTheGameIsDoing() throws {
        #expect(WatchBridge.state(of: nil) == WatchState.none)
        let game = try open()
        #expect(WatchBridge.state(of: game) == state("Speaking", .skip, "Skip"))
        audio.finish()
        #expect(WatchBridge.state(of: game) == state("Your turn", .talk, "Talk"))
        game.listen()
        #expect(WatchBridge.state(of: game) == state("Listening…", .stopListening, "Stop listening", listening: true))
        game.pause()
        #expect(WatchBridge.state(of: game) == state("Paused", .carryOn, "Carry on", canPause: false))
        game.carryOn()                  // the question again
        audio.finish()
        game.answer("yes")
        audio.finish()
        #expect(game.end?.kind == "chapter")
        let atTheEnd = state("Chapter complete", nil, "", enabled: false, canPause: false)
        #expect(WatchBridge.state(of: game) == atTheEnd)
        // Paused there (a call came, L2): the circle says Carry on, but the watch still has the end and no button,
        // as its big button does nothing at an end (WearBridge.kt's).
        game.pause()
        #expect(game.circleAction == .carryOn)
        #expect(WatchBridge.state(of: game) == atTheEnd)
        game.playAgain()
        audio.finish()
        game.answer("no")
        audio.finish()
        #expect(WatchBridge.state(of: game).state == "Game over")
    }

    /**
     * With the mic not allowed, the big button says so and is dimmed: only the iPhone can ask for the mic. With no
     * speech recognition just now, it can be pressed, to try again.
     */
    @Test func theMicOffDimsTheBigButton() throws {
        let game = try open(mic: false)
        audio.finish()
        let off = WatchBridge.state(of: game)
        #expect(off == state("Your turn", .micRefused, "Talk (the microphone is off)", enabled: false))
        game.micAllowed = true
        game.micWorks = false
        let noRecognition = WatchBridge.state(of: game)
        #expect(noRecognition == state(
            "Your turn", .noRecognition, "Talk (speech recognition isn't available)", enabled: true))
    }

    /// Every one of the circle's actions has the watch's name for it, the same as its own, and its words: the circle's
    /// state, but listening as the status line says it.
    @Test func everyActionHasItsNameAndWords() {
        for action in CircleAction.allCases {
            #expect(WatchBridge.watchAction(action).rawValue == "\(action)")
            let words = WatchBridge.words(action)
            #expect(words == (action == .stopListening ? "Listening…" : action.state))
        }
        #expect(WatchBridge.words(.wait) == "Wait for the question")
        #expect(Set(CircleAction.allCases.map { WatchBridge.watchAction($0) }).count == WatchAction.allCases.count)
    }

    /**
     * The big button does what Magic Tap does, as the headphones' button has it: speaking, it skips; waiting, it
     * listens, and again stops listening (with the stop sound: the player turned it off); paused, it carries on (the
     * question again); at an end, nothing, not even over a pause there (WearBridge.kt's). Pause pauses, but not over a
     * pause, nor at an end.
     */
    @Test func theWatchsButtonsAreMagicTapAndThePause() throws {
        let game = try open()
        let link = FakeWatchLink()
        let bridge = WatchBridge(link: link) { game }
        bridge.start()
        link.press(.primary)
        #expect(!game.speaking, "it didn't skip")
        #expect(listener.starts == 0)
        link.press(.primary)
        #expect(game.listening, "it didn't listen")
        #expect(cues.played == [.listenStart])
        link.press(.primary)
        #expect(!game.listening, "it didn't stop listening")
        #expect(cues.played == [.listenStart, .listenStop])
        link.press(.pause)
        #expect(game.paused)
        let played = audio.played.count
        link.press(.pause)
        #expect(game.paused)
        #expect(audio.played.count == played)
        link.press(.primary)
        #expect(!game.paused, "it didn't carry on")
        #expect(game.speaking)
        audio.finish()
        game.answer("yes")
        audio.finish()
        #expect(game.end != nil)
        let atTheEnd = audio.played.count
        link.press(.primary)
        link.press(.pause)
        #expect(!game.paused, "the watch paused an end")
        #expect(audio.played.count == atTheEnd)
        #expect(!game.listening)
        // A press that crosses with the end, over a pause the end has (a call came, L2): still nothing.
        game.pause()
        link.press(.primary)
        #expect(game.paused, "the watch carried on at an end")
        withExtendedLifetime(bridge) {}
    }

    /// With the mic not allowed, the big button does nothing (the watch shows it dimmed); nor does anything without a
    /// game.
    @Test func withTheMicOffOrNoGameTheBigButtonDoesNothing() throws {
        let game = try open(mic: false)
        audio.finish()
        let link = FakeWatchLink()
        let bridge = WatchBridge(link: link) { game }
        bridge.start()
        link.press(.primary)
        #expect(!game.listening)
        #expect(listener.starts == 0)
        #expect(cues.played.isEmpty)
        let none = FakeWatchLink()
        let nothing = WatchBridge(link: none) { nil }
        nothing.start()
        none.press(.primary)
        none.press(.pause)
        #expect(none.told == [WatchState.none])
        withExtendedLifetime((bridge, nothing)) {}
    }

    /**
     * The watch is told as the bridge starts (nothing open: that there's none), then whenever what it shows changes,
     * once for each change (a line shown or the highlight moving changes nothing for it), and again whenever its link
     * says it can hear, changed or not.
     */
    @Test func theWatchIsToldAsTheGameChanges() async throws {
        let link = FakeWatchLink()
        let holder = OpenGame()
        let bridge = WatchBridge(link: link) { holder.game }
        bridge.start()
        #expect(link.starts == 1)
        #expect(link.told == [WatchState.none])
        let game = try open()
        holder.game = game
        #expect(await until { link.told.count == 2 })
        #expect(link.told.last == state("Speaking", .skip, "Skip"))
        audio.now = ClipPosition(clip: 0, seconds: 1)          // the voice moves on: the feed changes, not the state
        try await Task.sleep(for: .milliseconds(200))
        #expect(link.told.count == 2, "told what the watch already had")
        audio.finish()
        #expect(await until { link.told.count == 3 })
        #expect(link.told.last == state("Your turn", .talk, "Talk"))
        link.onReady()
        #expect(link.told.count == 4)
        #expect(link.told[3] == link.told[2])
        link.press(.primary)
        #expect(await until { link.told.last?.listening == true })
        #expect(link.told.last == state("Listening…", .stopListening, "Stop listening", listening: true))
        holder.game = nil
        #expect(await until { link.told.last == WatchState.none })
        game.close()
        withExtendedLifetime(bridge) {}
    }

    /// The app's model tells the watch about the game it opens and closes, and the watch's buttons reach that game.
    @Test(.enabled(if: appGames, "the app's games aren't in this bundle"))
    func theAppsModelTellsTheWatch() async throws {
        let link = FakeWatchLink()
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchBridgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = AppModel(
            saves: MemorySaveStore(), packs: PackStore(root: scratch.appendingPathComponent("packs")),
            hearing: AppModel.Hearing.none, silent: true, startStore: false, watchLink: link)
        #expect(model.watch != nil)
        #expect(link.starts == 1)
        #expect(link.told == [WatchState.none])
        model.open(try #require(model.games.first { $0.id == "noodle-rush" }))
        #expect(await until(.seconds(10)) { model.game != nil })
        let game = try #require(model.game)
        #expect(await until { link.told.last?.title == "Noodle Rush" })
        link.press(.pause)
        #expect(game.paused)
        #expect(await until { link.told.last?.state == "Paused" })
        model.home()
        #expect(await until { link.told.last == WatchState.none })
    }
}
