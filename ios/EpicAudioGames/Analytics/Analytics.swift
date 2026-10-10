// analytics/Analytics.kt: usage data, what the player does in the app, sent to our own server under a random ID.

import Foundation
import Network
import UIKit
import os

/**
 * Usage data (docs/DESIGN.md › Usage data): what the player does in the app, as events of web/analytics/events.json
 * with their details ([Events] makes every one). The app tells its [Analytics]; [UsageData] sends them to our server,
 * [NoAnalytics] (tests) nowhere. Android: analytics/Analytics.kt.
 */
nonisolated protocol Analytics: Sendable {
    /// Something happened: an event of the whitelist, with some of its details (see [Events]).
    func track(_ name: String, _ props: [String: any Sendable])
}

nonisolated extension Analytics {
    /// Something happened ([Events] has what).
    func track(_ event: Event) {
        track(event.name, event.props)
    }
}

/// Usage data that goes nowhere: the tests', and a screen shown on its own.
nonisolated struct NoAnalytics: Analytics {
    func track(_ name: String, _ props: [String: any Sendable]) {}
}

/// How Settings › Privacy › Delete my usage data went. Android: Analytics.kt's UsageDeletion.
nonisolated enum UsageDeletion: Sendable {
    /// The server deleted what this device sent under its random ID; the app has forgotten that ID.
    case deleted
    /// The server couldn't be reached, or said no: nothing changed, so it can be tried again.
    case failed
    /**
     * There's no random ID on this device to delete under: usage data is off (turning it off forgets the ID), or
     * nothing has been recorded since it was last forgotten.
     */
    case nothingSent
}

/// Where the usage data's work is done: one task at a time, in the order they're asked for. Analytics.kt's Worker.
nonisolated protocol Worker: Sendable {
    /// Does [task] as soon as what's before it is done.
    func run(_ task: @escaping @Sendable () -> Void)

    /// Does [task] in [delay] (and every [delay] after that, with [repeats]); what's returned stops it.
    func later(_ delay: Duration, repeats: Bool, _ task: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}

/**
 * The device's [Worker]: a serial queue of its own, so files and requests never hold up the screen (a request waits
 * for its answer there). Analytics.kt's ThreadWorker.
 */
nonisolated final class QueueWorker: Worker {
    private let queue = DispatchQueue(label: "com.epicaudiogames.app.usage-data", qos: .utility)

    func run(_ task: @escaping @Sendable () -> Void) {
        queue.async { task() }
    }

    func later(_ delay: Duration, repeats: Bool, _ task: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let stopped = OSAllocatedUnfairLock(initialState: false)
        let queue = queue
        let (seconds, attoseconds) = delay.components
        let milliseconds = Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
        let wait = DispatchTimeInterval.milliseconds(max(0, milliseconds))
        @Sendable func due() {
            if stopped.withLock({ $0 }) { return }
            task()
            if repeats && !stopped.withLock({ $0 }) { queue.asyncAfter(deadline: .now() + wait) { due() } }
        }
        queue.asyncAfter(deadline: .now() + wait) { due() }
        return { stopped.withLock { $0 = true } }
    }
}

/**
 * The app's usage data, sent to our server under a random ID while Settings › Privacy › Share usage data is on
 * ([sharing]): each event stamped with that ID ([InstallId]), the session, its number in the session, the time and the
 * coarse [About] details, then queued ([EventQueue]: kept on the device until it's sent, at most 1,000 events and a
 * week) and sent ([Sender]) as the app goes off screen, every minute while it's on screen, when a game is left
 * ([flush]) and when the network comes back after a send found none. All of it on a queue of its own ([Worker]).
 *
 * - A session is new each time the app's process starts, and when the app comes back after 30 minutes away.
 * - Turned off, nothing more is recorded or sent, what's waiting is deleted, and the random ID is forgotten; turned on
 *   again, the next event makes a new one, in a new session, so nothing links the two.
 * - [delete] asks the server to delete everything under the ID, then forgets it as turning off does.
 * - On the first run, nothing is sent until onboarding has been finished or skipped ([waitForWelcome]): its welcome
 *   page says plainly that usage data is collected, with Turn off, and a player who turns it off there has sent
 *   nothing at all.
 * - [server] nil (a Debug build not given one at launch, the unit tests' host, or -EpicAnalytics off): nothing is
 *   recorded or sent. Tests use [NoAnalytics], or their own.
 * - [strict] (Debug builds): an event the whitelist hasn't got, or a detail of the wrong type, stops the app
 *   (assertionFailure), so the bug is found at once; a release build leaves it out (the server would turn away the
 *   batch it came in).
 *
 * The process has one ([app]): the session and the queue outlive the screens, as the app comes and goes. Nonisolated:
 * its state is the worker's alone, but for [sharing] and [waitForWelcome], which are behind a lock. Android:
 * Analytics.kt's UsageData.
 */
nonisolated final class UsageData: Analytics, @unchecked Sendable {
    /// Share usage data, and waiting for the welcome: read on any thread, set on the main actor.
    nonisolated private struct Flags: Sendable {
        var on: Bool
        var held: Bool
    }

    private let server: String?
    private let worker: any Worker
    /// What the app runs on, read as each event is recorded.
    private let about: @Sendable () -> About
    /// Time that goes on counting while the device sleeps (ContinuousClock's): how long things took.
    private let clock: @Sendable () -> Duration
    /// When things happened.
    private let wallClock: @Sendable () -> Date
    private let strict: (@Sendable (String) -> Void)?
    private let log: @Sendable (String) -> Void
    private let newId: @Sendable () -> UUID
    private let installId: InstallId
    private let queue: EventQueue
    private let sender: Sender?
    private let flags: OSAllocatedUnfairLock<Flags>
    /// Watches for the network coming back ([networkBack]); the app's own only.
    private var network: NWPathMonitor?

    // The worker's alone, as the queue and the ID are.
    private var session: String
    private var seq = 0
    /// No app_open yet in this process.
    private var cold = true
    private var onScreen = false
    private var onScreenAt = Duration.zero
    private var offScreenAt: Duration?
    private var ticking: (@Sendable () -> Void)?
    private var retrying: (@Sendable () -> Void)?

    /**
     * Usage data kept in [directory] ([installIdFile] and [queueFile]), sent to [server] (nil: nowhere) with [post].
     * [sharing]: Settings › Privacy › Share usage data; [waitForWelcome]: onboarding not over yet, on the first run.
     */
    init(
        directory: URL, server: String?, post: any Post, worker: any Worker,
        about: @escaping @Sendable () -> About, clock: @escaping @Sendable () -> Duration,
        wallClock: @escaping @Sendable () -> Date, strict: (@Sendable (String) -> Void)?,
        log: @escaping @Sendable (String) -> Void, sharing: Bool, waitForWelcome: Bool,
        newId: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        let queue = EventQueue(
            file: directory.appendingPathComponent(Self.queueFile, isDirectory: false), now: wallClock)
        self.server = server
        self.worker = worker
        self.about = about
        self.clock = clock
        self.wallClock = wallClock
        self.strict = strict
        self.log = log
        self.newId = newId
        installId = InstallId(
            file: directory.appendingPathComponent(Self.installIdFile, isDirectory: false), make: newId)
        self.queue = queue
        sender = server.flatMap { Sender(queue: queue, post: post, server: $0, clock: clock, log: log) }
        flags = OSAllocatedUnfairLock(initialState: Flags(on: sharing, held: waitForWelcome))
        session = newId().uuidString.lowercased()
        // Turned off before (perhaps in a run that ended before it had forgotten everything): nothing of it is left.
        if !sharing { worker.run { [self] in forgetAll() } }
    }

    private var on: Bool { flags.withLock { $0.on } }

    /**
     * Settings › Privacy › Share usage data. Turned off: nothing more is recorded or sent, what's waiting is deleted
     * and the random ID forgotten (a request already on its way finishes first). Turned on: the next event makes a new
     * random ID.
     */
    var sharing: Bool {
        get { on }
        set {
            let was = flags.withLock { flags in
                let was = flags.on
                flags.on = newValue
                return was
            }
            if was && !newValue { worker.run { [self] in forgetAll() } }
        }
    }

    /**
     * Onboarding hasn't been finished or skipped yet, on the first run: what happens is kept, but nothing is sent
     * until the player has had the welcome's word about usage data, and its Turn off.
     */
    var waitForWelcome: Bool {
        get { flags.withLock { $0.held } }
        set {
            let was = flags.withLock { flags in
                let was = flags.held
                flags.held = newValue
                return was
            }
            if was && !newValue { worker.run { [self] in send() } }
        }
    }

    func track(_ name: String, _ props: [String: any Sendable]) {
        if let problem = Events.problem(name, props) {
            // A mistake in the app's own code: found at once in a Debug build; never sent from a release one.
            if let strict {
                strict("usage data: \(problem)")
            } else {
                log("usage data: left out \(problem)")
            }
            return
        }
        guard server != nil, on else { return }
        let event = Event(name: name, props: props)
        let at = wallClock()
        worker.run { [self] in
            if on { record(event, at: at) }
        }
    }

    /// The app came on screen (active): app_open, a new session after 30 minutes away, and what's waiting sent every
    /// minute.
    func foreground() {
        guard server != nil else { return }
        let at = clock()
        let now = wallClock()
        worker.run { [self] in
            if onScreen { return }              // already on screen (back from a moment's alert)
            onScreen = true
            onScreenAt = at
            if let off = offScreenAt, at - off >= Self.newSessionAfter { newSession() }
            offScreenAt = nil
            if on { record(Events.appOpen(cold: cold, first: installId.peek() == nil), at: now) }
            cold = false
            ticking?()
            ticking = worker.later(Self.tick, repeats: true) { [self] in send() }
        }
    }

    /**
     * The app went off screen (to the background, or the device locked): app_background, and sending now; [then] once
     * that's over, on the worker (at once, with no server). iOS gives the app a moment for it before it's suspended:
     * AppModel.onScreen's background time.
     */
    func background(then: @escaping @Sendable () -> Void = {}) {
        guard server != nil else {
            then()
            return
        }
        let at = clock()
        let now = wallClock()
        worker.run { [self] in
            defer { then() }
            guard onScreen else { return }
            onScreen = false
            offScreenAt = at
            ticking?()
            ticking = nil
            if on { record(Events.appBackground(seconds: Int((at - onScreenAt).components.seconds)), at: now) }
            send()
        }
    }

    /// Sends what's waiting now (a game was just left), unless sending is waiting after a failure.
    func flush() {
        guard server != nil else { return }
        worker.run { [self] in send() }
    }

    /// The device has a network again: what a send without one left waiting goes now.
    func networkBack() {
        worker.run { [self] in
            if sender?.offline == true { send(anyway: true) }
        }
    }

    /**
     * Settings › Privacy › Delete my usage data: the server is asked to delete everything under the random ID (after
     * any request on its way), then the ID is forgotten and what's waiting deleted, as turning usage data off does;
     * on, the next event makes a new ID. If the server can't be reached nothing changes, so it can be asked again.
     */
    func delete() async -> UsageDeletion {
        guard sender != nil else { return .nothingSent }
        return await withCheckedContinuation { (answer: CheckedContinuation<UsageDeletion, Never>) in
            worker.run { [self] in
                guard let sender, let id = installId.peek() else {
                    answer.resume(returning: .nothingSent)
                    return
                }
                if sender.forget(id) {
                    forgetAll()
                    answer.resume(returning: .deleted)
                } else {
                    answer.resume(returning: .failed)
                }
            }
        }
    }

    /// An event stamped and queued: the ID (made now if there isn't one), the session, its number, its time.
    private func record(_ event: Event, at: Date) {
        let stamp = Stamp(installId: installId.get(), sessionId: session, seq: seq, at: at, about: about())
        seq += 1
        queue.add(Events.json(event, stamp))
    }

    /**
     * Sends what's waiting, unless it mustn't now: usage data off, the welcome not seen yet, or waiting after a
     * failure ([anyway]: the network's back, worth a try). What can't go is tried again when the wait is over.
     */
    private func send(anyway: Bool = false) {
        guard let sender, on, !waitForWelcome, !queue.isEmpty else { return }
        if !anyway && !sender.ready() { return }
        retrying?()
        retrying = nil
        sender.send(stillOn: { [self] in on })
        if let retryAt = sender.retryAt, !queue.isEmpty {
            retrying = worker.later(max(.zero, retryAt - clock()), repeats: false) { [self] in send() }
        }
    }

    /// A new session: a new ID for it, its events counted from 0 again.
    private func newSession() {
        session = newId().uuidString.lowercased()
        seq = 0
    }

    /**
     * Nothing of the usage data left on the device: what's waiting and the random ID go, and a new session starts, so
     * nothing sent later can be linked to what went before.
     */
    private func forgetAll() {
        queue.clear()
        installId.forget()
        newSession()
        retrying?()
        retrying = nil
        sender?.reset()
    }

    /// Where the release app sends usage data (/api/events and /api/forget, web/server.js).
    static let ourServer = "https://epicaudiogames.com"
    /**
     * The launch argument for another server, in a Debug build only: `-EpicAnalytics http://localhost:3000` (the web
     * server on the Mac, for the simulator; Info.plist's NSAllowsLocalNetworking lets plain HTTP go there). "off" turns
     * usage data off in any build, for that launch (every UI test, every screenshot).
     */
    static let argument = "EpicAnalytics"
    /// Its folder, in Application Support (never in a backup), and its two files.
    static let folder = "analytics"
    static let installIdFile = "install_id"
    static let queueFile = "queue.jsonl"
    /// On screen, what's waiting is sent this often.
    static let tick: Duration = .seconds(60)
    /// Back on screen after this long away: a new session.
    static let newSessionAfter: Duration = .seconds(30 * 60)
    static let logger = Logger(subsystem: "com.epicaudiogames.app", category: "usage-data")

    /**
     * Where this process's usage data goes: our server in a release build, the [argument]'s address in a Debug one
     * (none without one), and nowhere for the unit tests' host ([testing]) or with "off".
     */
    static func server(debug: Bool, argument: String?, testing: Bool) -> String? {
        if testing { return nil }
        if argument?.trimmingCharacters(in: .whitespaces).lowercased() == "off" { return nil }
        if !debug { return ourServer }
        guard var address = argument?.trimmingCharacters(in: .whitespaces) else { return nil }
        while address.hasSuffix("/") { address.removeLast() }
        if address.hasSuffix("/api/events") { address.removeLast("/api/events".count) }
        while address.hasSuffix("/") { address.removeLast() }
        return address.hasPrefix("http://") || address.hasPrefix("https://") ? address : nil
    }

    /// The process's usage data, once made ([app]).
    @MainActor private static var made: UsageData?

    /**
     * The process's usage data: made the first time it's asked for, as Settings ([sharing]) and onboarding
     * ([waitForWelcome]) are then; on the main actor, which reads what the app runs on ([About.app]) and watches the
     * network. MainActivity.kt's UsageData.of.
     */
    @MainActor static func app(sharing: Bool, waitForWelcome: Bool) -> UsageData {
        if let made { return made }
        // A Debug build stops at a mistake in the app's own events; a release one leaves the event out.
        #if DEBUG
        let debug = true
        let strict: (@Sendable (String) -> Void)? = { problem in assertionFailure(problem) }
        #else
        let debug = false
        let strict: (@Sendable (String) -> Void)? = nil
        #endif
        // XCTest's configuration in the environment: the app is the unit tests' host, in any build.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let address = server(debug: debug, argument: UserDefaults.standard.string(forKey: argument), testing: testing)
        let logger = Self.logger
        let log: @Sendable (String) -> Void = { logger.debug("\($0, privacy: .public)") }
        log(address.map { "usage data: to \($0)" } ?? "usage data: off in this run")
        let about = About.app()
        let start = ContinuousClock.now
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let usage = UsageData(
            directory: support.appendingPathComponent(folder, isDirectory: true), server: address,
            post: HTTPPost(userAgent: "EpicAudioGames/\(about.appVersion) (ios)"), worker: QueueWorker(),
            about: { about }, clock: { ContinuousClock.now - start }, wallClock: { Date() }, strict: strict,
            log: log, sharing: sharing, waitForWelcome: waitForWelcome)
        if address != nil { usage.watchNetwork() }
        made = usage
        return usage
    }

    /// The network coming back sends what a send without one left waiting ([networkBack]).
    private func watchNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { self?.networkBack() }
        }
        monitor.start(queue: DispatchQueue(label: "com.epicaudiogames.app.usage-data.network", qos: .utility))
        network = monitor
    }
}

extension About {
    /**
     * This app on this device: its version and build (Info.plist), iOS's version, the player's language (the first
     * of their preferred ones), and the kind of device. None of it changes while the app runs (an iPad stays one),
     * so it's read once, on the main actor, which UIDevice wants.
     */
    @MainActor static func app(_ bundle: Bundle = .main) -> About {
        let info = bundle.infoDictionary ?? [:]
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(system.majorVersion).\(system.minorVersion)"
            + (system.patchVersion > 0 ? ".\(system.patchVersion)" : "")
        return About(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            osVersion: version,
            lang: Locale.preferredLanguages.first ?? "",
            formFactor: formFactor(
                pad: UIDevice.current.userInterfaceIdiom == .pad, mac: ProcessInfo.processInfo.isiOSAppOnMac))
    }
}
