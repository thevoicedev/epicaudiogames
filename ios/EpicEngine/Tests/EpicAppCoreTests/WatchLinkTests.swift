// WatchLink.swift: what the iPhone tells the Apple Watch app, read back as the watch reads it; the watch's commands;
// the watch's inbox (the newest state, the buzzes); and the watch app's copy of the file.

import EpicConformance
import Foundation
import Testing

@testable import EpicAppCore

struct WatchLinkTests {
    private let speaking = WatchState(
        title: "Noodle Rush", state: "Speaking", action: .skip, label: "Skip", enabled: true, listening: false,
        canPause: true)
    private let listening = WatchState(
        title: "Noodle Rush", state: "Listening…", action: .stopListening, label: "Stop listening", enabled: true,
        listening: true, canPause: true)
    private let atAnEnd = WatchState(
        title: "The Werewolf", state: "Chapter complete", action: nil, label: "", enabled: false, listening: false,
        canPause: false)

    @Test func aStateComesBackAsItWent() throws {
        for state in [speaking, listening, atAnEnd, WatchState.none] {
            let back = try #require(WatchState.from(state.context(at: 1_700_000_000.25)))
            #expect(back.state == state)
            #expect(back.at == 1_700_000_000.25)
        }
    }

    /// WatchConnectivity carries a dictionary as a property list: the state comes back the same through one (on Apple's
    /// platforms its numbers and booleans come back as NSNumbers).
    @Test func aStateComesBackThroughAPropertyList() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: listening.context(at: 1234.5), format: .binary, options: 0)
        let read = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let back = try #require(WatchState.from(read))
        #expect(back.state == listening)
        #expect(back.at == 1234.5)
    }

    /// An empty context (the iPhone hasn't said anything yet), a key missing or of the wrong kind, a command: not a
    /// state.
    @Test func anythingElseIsntAState() {
        #expect(WatchState.from([:]) == nil)
        var missing = speaking.context(at: 1)
        missing["canPause"] = nil
        #expect(WatchState.from(missing) == nil)
        var wrong = speaking.context(at: 1)
        wrong["enabled"] = "yes"
        #expect(WatchState.from(wrong) == nil)
        #expect(WatchState.from(WatchCommand.primary.message) == nil)
    }

    /// An action this watch app doesn't know (a newer iPhone app's): the button still shows by its name, with no icon.
    @Test func anActionTheWatchDoesntKnowKeepsItsButton() throws {
        var context = speaking.context(at: 1)
        context["action"] = "somethingNew"
        let back = try #require(WatchState.from(context))
        #expect(back.state.action == nil)
        #expect(back.state.label == "Skip")
        #expect(back.state.enabled)
    }

    @Test func noGameIsNone() {
        #expect(!WatchState.none.gameOpen)
        #expect(WatchState.none.label.isEmpty)
        #expect(!WatchState.none.enabled && !WatchState.none.canPause && !WatchState.none.listening)
        #expect(speaking.gameOpen)
    }

    @Test func aCommandComesBackAsItWent() {
        for command in WatchCommand.allCases {
            #expect(WatchCommand(message: command.message) == command)
        }
        #expect(WatchCommand.primary.message["command"] as? String == "primary")
        #expect(WatchCommand.pause.message["command"] as? String == "pause")
        #expect(WatchCommand(message: [:]) == nil)
        #expect(WatchCommand(message: ["command": "dance"]) == nil)
        #expect(WatchCommand(message: speaking.context(at: 1)) == nil)
    }

    // ----- The watch's inbox -----

    /// The newest state shows; one the iPhone made before it, arriving late, is let go; one made at the same moment
    /// is taken.
    @Test func theNewestShowsAndALateOneIsLetGo() {
        var inbox = WatchInbox()
        #expect(inbox.state == WatchState.none)
        #expect(inbox.at == nil)
        let first = inbox.take(speaking, at: 100)
        #expect(first.shown)
        let newer = inbox.take(listening, at: 101)
        #expect(newer.shown)
        let late = inbox.take(speaking, at: 100.5)
        #expect(!late.shown)
        #expect(late.haptic == nil)
        #expect(inbox.state == listening)
        #expect(inbox.at == 101)
        let same = inbox.take(speaking, at: 101)
        #expect(same.shown)
        #expect(inbox.state == speaking)
    }

    /// The iPhone's clock put back: a state much older than the one showing is taken, not left out for good.
    @Test func theIPhonesClockPutBackIsntALateState() {
        var inbox = WatchInbox()
        _ = inbox.take(speaking, at: 10_000)
        let back = inbox.take(listening, at: 10_000 - WatchInbox.clockJump - 1)
        #expect(back.shown)
        #expect(inbox.state == listening)
    }

    /// The microphone opening and closing buzz; nothing else does: not the first state (the watch app opening on a
    /// game that listens), not a state like the last, not the game closing, not a late state.
    @Test func theMicOpeningAndClosingBuzz() {
        var inbox = WatchInbox()
        let opening = inbox.take(listening, at: 1)
        #expect(opening.haptic == nil, "the first state buzzed")
        let stopped = inbox.take(speaking, at: 2)
        #expect(stopped.haptic == .listeningStopped)
        let again = inbox.take(speaking, at: 3)
        #expect(again.haptic == nil)
        let started = inbox.take(listening, at: 4)
        #expect(started.haptic == .listeningStarted)
        let still = inbox.take(listening, at: 5)
        #expect(still.haptic == nil)
        let closed = inbox.take(.none, at: 6)
        #expect(closed.shown)
        #expect(closed.haptic == nil, "leaving the game buzzed")
        let late = inbox.take(listening, at: 5.5)
        #expect(late.haptic == nil)
    }

    /// The watch app links no package: its copy is this file, word for word.
    @Test func theWatchAppsCopyIsTheSame() throws {
        let root = try Repo.root(from: #filePath)
        func text(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                .replacingOccurrences(of: "\r\n", with: "\n")
        }
        let core = try text("ios/EpicEngine/Sources/EpicAppCore/WatchLink.swift")
        let watch = try text("ios/EpicWatch/WatchLink.swift")
        #expect(core == watch, "ios/EpicWatch/WatchLink.swift isn't EpicAppCore's WatchLink.swift: copy it again")
    }
}
