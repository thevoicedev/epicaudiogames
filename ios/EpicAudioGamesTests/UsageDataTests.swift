// analytics/UsageDataTest.kt: the app's usage data as a whole, on a test's clock with a stand-in server.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The app's usage data as a whole (Analytics/Analytics.swift's UsageData), on a test's clock with a stand-in server:
 * app_open and app_background, sessions and their numbered events under one random ID, sending every minute on screen
 * and as the app goes, waiting after a failure (the same events, the same numbers, again), the network coming back,
 * nothing sent before the welcome, turning off (nothing left on the device, a new ID after), Delete my usage data, a
 * mistake in the app's own events, and a build with no server. Every event sent is checked against the server's own
 * whitelist (web/analytics/events.json). And the device's own worker. Android: UsageDataTest.kt.
 */
@MainActor
@Suite(.serialized)
final class UsageDataTests {
    private let folder: URL
    private let dir: URL
    private let clock = TestClock()
    private let wall = WallClock(Date(timeIntervalSince1970: 1_791_538_860))
    private let worker: TestWorker
    private let post = FakeServer()
    private let device = Device()
    private let mistakes = Mistakes()
    private let whitelist: Whitelist

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("UsageDataTests-\(UUID().uuidString)")
        dir = folder.appendingPathComponent("analytics", isDirectory: true)
        worker = TestWorker(clock: clock, wall: wall)
        clock.now = .seconds(50_000)
        whitelist = try Whitelist.load()
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private var idFile: URL { dir.appendingPathComponent(UsageData.installIdFile) }
    private var queueFile: URL { dir.appendingPathComponent(UsageData.queueFile) }

    private func usage(
        sharing: Bool = true, waitForWelcome: Bool = false, strict: Bool = true,
        server: String? = "https://epicaudiogames.com"
    ) -> UsageData {
        let clock = clock
        let wall = wall
        let device = device
        let mistakes = mistakes
        // A Debug build's: each mistake noted (the app's stops at it).
        var caught: (@Sendable (String) -> Void)?
        if strict { caught = { mistakes.add($0) } }
        return UsageData(
            directory: dir, server: server, post: post, worker: worker,
            about: { About(appVersion: "1.0", build: "3", osVersion: "18.1", lang: "en-GB", formFactor: device.kind) },
            clock: { clock.now }, wallClock: { wall.now }, strict: caught, log: { _ in }, sharing: sharing,
            waitForWelcome: waitForWelcome)
    }

    /// The events sent so far, each checked against the server's whitelist, in the order they went.
    private func sent() throws -> [[String: JSONValue]] { try post.events(whitelist) }

    private func names(_ events: [[String: JSONValue]]) -> [String] { events.map { $0["name"]?.text ?? "?" } }

    private func field(_ event: [String: JSONValue], _ key: String) -> String { event[key]?.text ?? "?" }

    private func prop(_ event: [String: JSONValue], _ key: String) -> String { event["props"]?[key]?.text ?? "?" }

    private func idText() throws -> String { try String(contentsOf: idFile, encoding: .utf8) }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func aSessionsEventsAreNumberedUnderOneRandomID() throws {
        let u = usage()
        u.foreground()
        u.track(Events.tabView(.shop))
        worker.advance(.seconds(30))
        u.background()
        let first = try sent()
        #expect(names(first) == ["app_open", "tab_view", "app_background"])
        #expect(first.map { field($0, "seq") } == ["0", "1", "2"])
        #expect(Set(first.map { field($0, "session_id") }).count == 1)
        let ids = Set(first.map { field($0, "install_id") })
        #expect(ids.count == 1)
        let id = try #require(ids.first)
        #expect(try idText() == id)
        #expect(prop(first[0], "cold") == "true")
        #expect(prop(first[0], "first") == "true")
        #expect(prop(first[2], "seconds") == "30")
        #expect(field(first[0], "form_factor") == "phone")
        #expect(field(first[0], "platform") == "ios")
        #expect(!exists(queueFile), "nothing left waiting")

        // Back ten minutes later: the same session, numbered on.
        worker.advance(.seconds(10 * 60))
        u.foreground()
        worker.advance(.seconds(5))
        u.background()
        let again = Array(try sent().dropFirst(3))
        #expect(names(again) == ["app_open", "app_background"])
        #expect(again.map { field($0, "seq") } == ["3", "4"])
        #expect(prop(again[0], "cold") == "false")
        #expect(prop(again[0], "first") == "false")
        #expect(field(again[0], "session_id") == field(first[0], "session_id"))

        // Back after half an hour away: a new session, the same ID.
        worker.advance(.seconds(30 * 60))
        device.kind = "tablet"              // (the iPad app, on a Mac now: as the app reads it at each event)
        u.foreground()
        u.background()
        let later = Array(try sent().dropFirst(5))
        #expect(later.map { field($0, "seq") } == ["0", "1"])
        #expect(field(later[0], "session_id") != field(first[0], "session_id"))
        #expect(field(later[0], "install_id") == id)
        #expect(field(later[0], "form_factor") == "tablet")

        // The app started again (a new process): cold, a new session, not the first time.
        let next = usage()
        next.foreground()
        next.background()
        let restarted = Array(try sent().dropFirst(7))
        #expect(prop(restarted[0], "cold") == "true")
        #expect(prop(restarted[0], "first") == "false")
        #expect(field(restarted[0], "seq") == "0")
        #expect(field(restarted[0], "install_id") == id)
    }

    @Test func onScreenWhatsWaitingGoesEveryMinute() throws {
        let u = usage()
        u.foreground()
        u.track(Events.introFinished(skipped: true))
        worker.advance(.seconds(60) - .milliseconds(1))
        #expect(post.requests.isEmpty)
        worker.advance(.milliseconds(1))
        #expect(names(try sent()) == ["app_open", "intro_finished"])
        u.track(Events.tabView(.help))
        worker.advance(.seconds(60))
        #expect(post.requests.count == 2)
        // Nothing waiting: nothing sent.
        worker.advance(.seconds(60))
        #expect(post.requests.count == 2)
        // Off screen, the minutes stop.
        u.background()
        #expect(post.requests.count == 3)
        u.track(Events.gameOpen("noodle-rush", resumed: false))
        worker.advance(.seconds(10 * 60))
        #expect(post.requests.count == 3)
        // A game left: what's waiting goes then.
        u.flush()
        #expect(names(try sent()).last == "game_open")
    }

    /// Going off screen, the app hears when the send is over (it gives back the background time iOS lent it): after
    /// the send, and at once with nothing to do (already off screen) or no server.
    @Test func goingOffScreenSaysWhenTheSendIsOver() throws {
        let u = usage()
        let server = post
        let done = Done()
        u.foreground()
        u.track(Events.tabView(.shop))
        u.background { done.add(server.requests.count) }
        #expect(done.all == [1], "said once, after the send")
        #expect(names(try sent()) == ["app_open", "tab_view", "app_background"])
        u.background { done.add(-1) }
        #expect(done.all == [1, -1])
        usage(server: nil).background { done.add(-2) }
        #expect(done.all == [1, -1, -2])
        #expect(server.requests.count == 1)
    }

    @Test func nothingIsSentUntilThePlayerHasHadTheWelcome() throws {
        let u = usage(waitForWelcome: true)
        u.foreground()
        u.track(Events.introFinished(skipped: false))
        u.track(Events.onboardingFinished(completed: true))
        worker.advance(.seconds(5 * 60))
        u.background()
        #expect(post.requests.isEmpty)
        #expect(try String(contentsOf: queueFile, encoding: .utf8).split(separator: "\n").count == 4)
        u.waitForWelcome = false
        #expect(names(try sent()) == ["app_open", "intro_finished", "onboarding_finished", "app_background"])
    }

    @Test func turnedOffNothingIsLeftOnTheDeviceAndNothingIsSent() throws {
        post.answers = [Response(503, retryAfterSeconds: 60)]
        let u = usage()
        u.foreground()
        u.track(Events.tabView(.settings))
        u.background()                      // the server's down: kept for later
        let oldId = try idText()
        let failed = try #require(post.requests.last)
        let oldSession = try #require(try whitelist.batch(Data(failed.body.utf8)).first)
        #expect(exists(queueFile))
        u.sharing = false
        #expect(!exists(idFile))
        #expect(!exists(queueFile))
        // No more events, and the retry that was waiting doesn't happen.
        post.answers = [Response(202)]
        u.track(Events.tabView(.games))
        u.foreground()
        worker.advance(.seconds(10 * 60))
        u.background()
        #expect(post.requests.count == 1)
        let left = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        #expect(left.allSatisfy { ((try? Data(contentsOf: $0)) ?? Data()).isEmpty }, "\(left)")

        // Turned on again: a new ID, a new session, nothing to link them.
        u.sharing = true
        u.foreground()
        u.background()
        let now = Array(try sent().dropFirst(3))           // (after the three the server couldn't take)
        #expect(names(now) == ["app_open", "app_background"])
        #expect(field(now[0], "install_id") != oldId)
        #expect(field(now[0], "session_id") != field(oldSession, "session_id"))
        #expect(field(now[0], "seq") == "0")
    }

    @Test func startedTurnedOffNothingFromBeforeIsLeft() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10".utf8).write(to: idFile)
        try Data("\(EventQueue.milliseconds(wall.now))\t{\"name\":\"tab_view\"}\n".utf8).write(to: queueFile)
        let u = usage(sharing: false)
        #expect(!exists(idFile))
        #expect(!exists(queueFile))
        u.foreground()
        u.track(Events.tabView(.shop))
        u.background()
        #expect(post.requests.isEmpty)
        #expect(!exists(idFile))
    }

    @Test func deleteMyUsageDataAsksTheServerThenForgets() async throws {
        let u = usage()
        u.foreground()
        u.background()
        let id = try idText()
        let opened = try #require(try sent().first)
        let session = field(opened, "session_id")

        // The server can't be reached: nothing changes, so it can be asked again.
        post.answers = [Response(nil)]
        u.track(Events.tabView(.settings))
        #expect(await u.delete() == .failed)
        #expect(try idText() == id)
        #expect(exists(queueFile))

        post.answers = [Response(202)]
        #expect(await u.delete() == .deleted)
        let forget = try #require(post.requests.last)
        #expect(forget.url.absoluteString == "https://epicaudiogames.com/api/forget")
        #expect(forget.body == "{\"install_id\":\"\(id)\"}")
        #expect(!exists(idFile))
        #expect(!exists(queueFile), "what was waiting went too")

        // Still sharing: the next events are under a new ID, in a new session.
        u.foreground()
        u.background()
        let after = Array(try sent().dropFirst(2))
        #expect(names(after) == ["app_open", "app_background"])
        #expect(field(after[0], "install_id") != id)
        #expect(field(after[0], "session_id") != session)

        // Turned off, the ID is forgotten already: nothing can be found to delete, and nothing is asked.
        u.sharing = false
        let asked = post.requests.count
        #expect(await u.delete() == .nothingSent)
        #expect(post.requests.count == asked)
    }

    @Test func whatCouldntGoGoesLaterWithTheSameNumbers() throws {
        post.answers = [Response(503, retryAfterSeconds: 60)]
        let u = usage()
        u.foreground()
        u.track(Events.helpViewed(.tab))
        u.background()
        #expect(post.requests.count == 1)
        let failed = try #require(post.requests.first).body
        post.answers = [Response(202)]
        worker.advance(.seconds(59))
        #expect(post.requests.count == 1)
        worker.advance(.seconds(1))
        #expect(post.requests.count == 2)
        #expect(post.requests.last?.body == failed)
        #expect(!exists(queueFile))
        // And the next event is numbered on, never again from a number already used.
        u.foreground()
        u.background()
        #expect(Array(try sent().dropFirst(6)).map { field($0, "seq") } == ["3", "4"])
    }

    @Test func theNetworkComingBackSendsAtOnce() throws {
        post.answers = [Response(nil)]
        let u = usage()
        u.foreground()
        u.background()
        #expect(post.requests.count == 1)
        post.answers = [Response(202)]
        u.networkBack()
        #expect(post.requests.count == 2)
        #expect(!exists(queueFile))
        // With nothing waiting for the network, its coming and going sends nothing.
        u.networkBack()
        #expect(post.requests.count == 2)
        // Nor does it hurry a server that asked to wait (it answered: the network wasn't the trouble).
        post.answers = [Response(503, retryAfterSeconds: 3600)]
        u.foreground()
        u.background()
        #expect(post.requests.count == 3)
        u.networkBack()
        #expect(post.requests.count == 3)
    }

    @Test func aNumberIsNeverUsedForTwoEventsInASession() throws {
        // Answers of every kind, as a device could get in a day.
        let kinds = [Response(202), Response(503), Response(nil), Response(400), Response(429), Response(202)]
        var n = 0
        post.answer = { _ in
            defer { n += 1 }
            return kinds[n % kinds.count]
        }
        let u = usage()
        var seen: [String: String] = [:]
        for round in 0..<30 {
            u.foreground()
            for i in 0..<7 { u.track(Events.tabView(AppTab.allCases[(round + i) % 4])) }
            u.track(Events.gameLeave(
                "noodle-rush", node: "Page1", turns: round, seconds: round * 10, spoken: 1, typed: 2, tapped: 3,
                silences: 0))
            worker.advance(.seconds(61))
            u.background()
            u.networkBack()
            worker.advance(round % 3 == 0 ? .seconds(31 * 60) : .seconds(90))
        }
        for event in try sent() {
            let key = field(event, "session_id") + "#" + field(event, "seq")
            let text = JSONValue.object(event).description
            // Sent again (its answer lost or refused), it's the same event; never another under its number.
            #expect(seen[key, default: text] == text, "\(key)")
            seen[key] = text
        }
        #expect(seen.count > 100)
    }

    @Test func aMistakeInTheAppsOwnEventsIsCaught() throws {
        // A Debug build: at once (the app's assertionFailure; here, noted).
        let strict = usage()
        strict.track("screen_reader_on", [:])
        strict.track("tab_view", ["tab": "games", "theme": "contrast"])
        strict.track("game_end", ["game": "noodle-rush", "kind": "end", "node": "yes please"])
        #expect(mistakes.found.count == 3)
        #expect(mistakes.found.allSatisfy { $0.hasPrefix("usage data: ") })
        #expect(!exists(queueFile))
        // A release build: left out, and the rest goes as ever (the server would turn away a batch with it in).
        let release = usage(strict: false)
        release.foreground()
        release.track("screen_reader_on", ["on": true])
        release.track("tab_view", ["tab": "games", "voice_speed": 2])
        release.track("app_open", ["cold": "yes"])
        release.background()
        #expect(names(try sent()) == ["app_open", "app_background"])
        #expect(mistakes.found.count == 3)
    }

    @Test func withNoServerNothingIsKeptOrSent() async throws {
        let u = usage(server: nil)
        u.foreground()
        u.track(Events.tabView(.shop))
        worker.advance(.seconds(5 * 60))
        u.background()
        u.flush()
        u.networkBack()
        #expect(post.requests.isEmpty)
        #expect(!exists(dir))
        #expect(await u.delete() == .nothingSent)
        // Its mistakes are still caught.
        u.track("transcript", ["text": "Gribbo: who's there?"])
        #expect(mistakes.found.count == 1)
    }

    /// The device's own worker: its tasks one at a time, in the order they were asked for, and a timer that goes on
    /// until it's stopped.
    @Test func theDevicesWorkerKeepsOrderAndStopsItsTimers() async throws {
        let worker = QueueWorker()
        let done = Done()
        for i in 0..<200 { worker.run { done.add(i) } }
        #expect(await until { done.count == 200 })
        #expect(done.all == Array(0..<200))
        let ticks = Done()
        let stop = worker.later(.milliseconds(20), repeats: true) { ticks.add(0) }
        #expect(await until { ticks.count >= 3 })
        stop()
        // (a tick already on its way may still come: the one after it doesn't)
        try await Task.sleep(for: .milliseconds(60))
        let stopped = ticks.count
        try await Task.sleep(for: .milliseconds(100))
        #expect(ticks.count == stopped)
        let once = Done()
        _ = worker.later(.milliseconds(10), repeats: false) { once.add(1) }
        let never = worker.later(.milliseconds(30), repeats: false) { once.add(2) }
        never()
        // (Waited for, as a busy machine runs a timer late; the one stopped was due soon after, and never comes.)
        #expect(await until { once.count >= 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(once.all == [1])
    }

    private func until(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/**
 * The usage data's worker, in the test's hands: tasks done at once, timers run as [advance] passes their time on both
 * clocks. Used on the test's own thread.
 */
final class TestWorker: Worker, @unchecked Sendable {
    private final class Timer: @unchecked Sendable {
        var due: Duration
        let every: Duration?
        let task: @Sendable () -> Void

        init(due: Duration, every: Duration?, task: @escaping @Sendable () -> Void) {
            self.due = due
            self.every = every
            self.task = task
        }
    }

    private let clock: TestClock
    private let wall: WallClock
    private var timers: [Timer] = []

    init(clock: TestClock, wall: WallClock) {
        self.clock = clock
        self.wall = wall
    }

    func run(_ task: @escaping @Sendable () -> Void) {
        task()
    }

    func later(_ delay: Duration, repeats: Bool, _ task: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let timer = Timer(due: clock.now + delay, every: repeats ? delay : nil, task: task)
        timers.append(timer)
        return { [weak self] in self?.timers.removeAll { $0 === timer } }
    }

    /// [time] passes on both clocks, each timer due in it running in turn.
    func advance(_ time: Duration) {
        let end = clock.now + time
        while let next = timers.filter({ $0.due <= end }).min(by: { $0.due < $1.due }) {
            wall.advance(next.due - clock.now)
            clock.now = next.due
            if let every = next.every {
                next.due += every
            } else {
                timers.removeAll { $0 === next }
            }
            next.task()
        }
        wall.advance(end - clock.now)
        clock.now = end
    }
}

/// The kind of device the test's app is on, as each event reads it.
final class Device: @unchecked Sendable {
    var kind = "phone"
}

/// The mistakes a Debug build would have stopped at.
final class Mistakes: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    var found: [String] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }

    func add(_ mistake: String) {
        lock.lock()
        defer { lock.unlock() }
        list.append(mistake)
    }
}

/// What a worker's tasks did, from its own queue.
final class Done: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Int] = []

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }

    var count: Int { all.count }

    func add(_ n: Int) {
        lock.lock()
        defer { lock.unlock() }
        list.append(n)
    }
}
