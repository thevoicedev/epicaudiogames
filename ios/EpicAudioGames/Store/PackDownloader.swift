// Store.kt's download (lines 147-195): a pack's zip fetched from the pack server, with its progress.

import EpicAppCore
import Foundation

/// What a download comes to, as the store hears it.
enum PackFetchEvent: Sendable {
    /// The bytes received so far.
    case progress(Int64)
    /// The zip, in a file of its own (the store deletes it).
    case finished(URL)
    case failed(FetchFailure)
}

/// A download that failed: what went wrong, and whether it was the disk being full.
struct FetchFailure: Error, Sendable, CustomStringConvertible {
    let description: String
    let diskFull: Bool

    init(_ error: any Error) {
        description = String(describing: error)
        diskFull = DiskSpace.isFull(error)
    }
}

/// A download the app's last run left going, as the system carried on with it.
struct RunningDownload: Equatable, Sendable {
    let bytes: Int64
    /// It may use cellular and Low Data Mode.
    let cellular: Bool
}

/**
 * Where the packs' zips come from: the pack server (PackDownloader), or a fake in tests. The store names each download
 * ("<pack>@<version>#<n>"), and hears its events by that name, on the main actor.
 */
protocol PackFetching: AnyObject {
    var events: (String, PackFetchEvent) -> Void { get set }
    /// Starts fetching [url]. [cellular]: it may use cellular and Low Data Mode; if not, it waits for Wi-Fi there.
    func start(_ url: URL, key: String, cellular: Bool)
    func cancel(_ key: String)
    /// The downloads still going from the app's last run (the system carried on with them), by name.
    func running() async -> [String: RunningDownload]
}

/**
 * The pack server, through a background URLSession: a download carries on while the app is away, and after the system
 * ends the app. iOS then launches it again to hand the zip over (AppDelegate), and the store, started again, takes it
 * up: [running] for one still going, and the events of one that finished meanwhile. HTTP 200 is required.
 */
final class PackDownloader: PackFetching {
    static let shared = PackDownloader()
    static let identifier = "com.epicaudiogames.app.packs"

    var events: (String, PackFetchEvent) -> Void = { _, _ in }

    /// iOS's handler, from a launch to hand over this session's events: called once they've all come.
    private var eventsHandled: (() -> Void)?
    /// The events came before iOS's handler did.
    private var eventsCame = false

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        c.sessionSendsLaunchEvents = true
        c.isDiscretionary = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c, delegate: SessionEvents(owner: self), delegateQueue: nil)
    }()

    private init() {}

    /// AppDelegate's handleEventsForBackgroundURLSession: the session is made (if the store hasn't yet), and iOS is
    /// told when its events have been handled.
    func handOver(_ handled: @escaping () -> Void) {
        _ = session
        if eventsCame {
            eventsCame = false
            handled()
        } else {
            eventsHandled = handled
        }
    }

    func start(_ url: URL, key: String, cellular: Bool) {
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = cellular
        request.allowsConstrainedNetworkAccess = cellular
        let task = session.downloadTask(with: request)
        task.taskDescription = key
        task.resume()
    }

    func cancel(_ key: String) {
        let session = session
        Task {
            for task in await session.allTasks where task.taskDescription == key { task.cancel() }
        }
    }

    func running() async -> [String: RunningDownload] {
        var out: [String: RunningDownload] = [:]
        for task in await session.allTasks where task.state == .running || task.state == .suspended {
            guard let key = task.taskDescription else { continue }
            let cellular = task.originalRequest?.allowsExpensiveNetworkAccess ?? true
            out[key] = RunningDownload(bytes: task.countOfBytesReceived, cellular: cellular)
        }
        return out
    }

    fileprivate func deliver(_ key: String, _ event: PackFetchEvent) {
        events(key, event)
    }

    fileprivate func allDelivered() {
        if let handled = eventsHandled {
            eventsHandled = nil
            handled()
        } else {
            eventsCame = true
        }
    }
}

/**
 * The session's delegate, on its own serial queue (the only one that touches [files] and [shown]). Each event goes on
 * to the main actor, in order.
 */
nonisolated private final class SessionEvents: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let owner: PackDownloader
    /// Each task's zip, moved out of URLSession's file (deleted when the callback returns), or why it couldn't be.
    private var files: [Int: Result<URL, any Error>] = [:]
    /// When each task's progress was last passed on (ten times a second at most).
    private var shown: [Int: Date] = [:]

    init(owner: PackDownloader) {
        self.owner = owner
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription else { return }
        let now = Date()
        if let last = shown[downloadTask.taskIdentifier], now.timeIntervalSince(last) < 0.1 { return }
        shown[downloadTask.taskIdentifier] = now
        post(key, .progress(totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Anything but a 200 is said when the task completes.
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            files[downloadTask.taskIdentifier] = .success(kept)
        } catch {
            files[downloadTask.taskIdentifier] = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let file = files.removeValue(forKey: task.taskIdentifier)
        shown.removeValue(forKey: task.taskIdentifier)
        guard let key = task.taskDescription else {
            if case .success(let zip)? = file { try? FileManager.default.removeItem(at: zip) }
            return
        }
        switch (error, file) {
        case (let error?, _):
            if case .success(let zip)? = file { try? FileManager.default.removeItem(at: zip) }
            post(key, .failed(FetchFailure(error)))
        case (nil, .success(let zip)?):
            post(key, .finished(zip))
        case (nil, .failure(let error)?):
            post(key, .failed(FetchFailure(error)))
        case (nil, nil):
            let status = (task.response as? HTTPURLResponse)?.statusCode
            post(key, .failed(FetchFailure(status.map { PackError("HTTP \($0)") } ?? URLError(.badServerResponse))))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let owner = owner
        DispatchQueue.main.async { MainActor.assumeIsolated { owner.allDelivered() } }
    }

    private func post(_ key: String, _ event: PackFetchEvent) {
        let owner = owner
        DispatchQueue.main.async { MainActor.assumeIsolated { owner.deliver(key, event) } }
    }
}
