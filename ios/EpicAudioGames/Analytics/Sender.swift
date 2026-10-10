// analytics/Sender.kt: the usage data sent to our server a batch at a time, waiting longer after each failure.

import Foundation

/// Our server's answer: its HTTP status (nil: none came, as with no network or a timeout), and its Retry-After.
nonisolated struct Response: Sendable, Equatable {
    let status: Int?
    let retryAfterSeconds: Int64?

    init(_ status: Int?, retryAfterSeconds: Int64? = nil) {
        self.status = status
        self.retryAfterSeconds = retryAfterSeconds
    }
}

/// Sends a JSON body to a URL and waits for the answer: [HTTPPost] on the device, a stand-in in the tests.
nonisolated protocol Post: Sendable {
    func post(_ url: URL, _ body: Data) -> Response
}

/**
 * A POST with the system's URLSession, nothing more (no SDK; an ephemeral session, so no cookies, cache or stored
 * credentials): the body as JSON, the app's name and version as its User-Agent, and the server's answer. It waits for
 * the answer on the usage data's own queue, never the screen's. Redirects aren't followed (the API sends none): the
 * redirect is the answer, which means later ([Delivery]), so what the request carried stays rather than going
 * wherever it was sent. Android: Sender.kt's HttpPost.
 */
nonisolated final class HTTPPost: Post {
    private let session: URLSession
    private let userAgent: String
    private let timeout: TimeInterval

    /// [configuration]: an ephemeral session's (a test's has a stand-in server in it), set up as above.
    init(userAgent: String, timeout: TimeInterval = 15, configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // (A session keeps its delegate until it's let go: this one lasts as long as the app.)
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        self.userAgent = userAgent
        self.timeout = timeout
    }

    func post(_ url: URL, _ body: Data) -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let answer = Answer()
        let done = DispatchSemaphore(value: 0)
        // The answer's body ({"ok":true} or why not) isn't needed: only its status and Retry-After. A redirect refused
        // is the answer from this address; one from another (a redirect followed after all) counts as none.
        let task = session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.url?.host == url.host, http.url?.path == url.path {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
                answer.set(Response(http.statusCode, retryAfterSeconds: retryAfter))
            }
            done.signal()
        }
        task.resume()
        if done.wait(timeout: .now() + timeout * 2 + 5) == .timedOut {
            task.cancel()
            return Response(nil)
        }
        return answer.get()
    }

    /// The answer, from URLSession's queue to the one waiting for it (the semaphore orders them; the lock says so).
    nonisolated private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var response = Response(nil)

        func set(_ value: Response) {
            lock.lock()
            response = value
            lock.unlock()
        }

        func get() -> Response {
            lock.lock()
            defer { lock.unlock() }
            return response
        }
    }

    /// Every redirect refused, so the redirect itself is the answer (HttpURLConnection's instanceFollowRedirects off).
    nonisolated private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }
}

/// What a request's answer means for what it carried.
nonisolated enum Delivery: Sendable {
    /// Stored (202): off the queue.
    case sent
    /// Turned away for good (400, 413, 415, any 4xx but 429): sending it again would get the same, so it goes.
    case refused
    /// Not now (no answer, 429, 503 or another 5xx): it stays, and is tried again later.
    case later

    /// What an answer's status means (web/server.js: 202, 400, 413, 415, 429, 503).
    static func of(_ status: Int?) -> Delivery {
        guard let status else { return .later }
        switch status {
        case 200...299: return .sent
        case 429: return .later
        case 400...499: return .refused
        default: return .later
        }
    }
}

/**
 * Sends the usage data waiting in [queue] to our server ([server]/api/events, docs/DESIGN.md › Usage data): a batch at
 * a time (at most 100 events and 64 KB), oldest first, until none is left or one can't go now. What the server stored,
 * or turned away for good (a 4xx but 429: it would turn it away again), comes off the queue; otherwise it all stays,
 * and sending waits: 30 s after a first failure, then twice as long each time up to 30 minutes, and at least as long
 * as the server's Retry-After asks (a busy server's 429, a 503 while its database is down). A batch sent again after
 * its answer was lost is stored once: the server knows each event by its ID, session and number in it.
 *
 * Also asks the server to forget an install ([forget]). Runs on the usage data's own queue, never the screen's: a
 * request blocks it. [clock] keeps counting while the device sleeps (ContinuousClock's). Not thread-safe: only that
 * queue uses it. Android: analytics/Sender.kt.
 */
nonisolated final class Sender: @unchecked Sendable {
    let eventsURL: URL
    let forgetURL: URL
    private let queue: EventQueue
    private let post: any Post
    private let clock: @Sendable () -> Duration
    private let log: @Sendable (String) -> Void

    /// Failures in a row (sending waits longer after each).
    private var failures = 0

    /// When sending may be tried again after a failure ([clock]'s time); nil: whenever.
    private(set) var retryAt: Duration?

    /// The last request got no answer at all: the network coming back is worth trying again for at once.
    private(set) var offline = false

    /// Nil for a [server] that isn't an address.
    init?(
        queue: EventQueue, post: any Post, server: String, clock: @escaping @Sendable () -> Duration,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        guard let events = URL(string: server + "/api/events"), let forget = URL(string: server + "/api/forget") else {
            return nil
        }
        eventsURL = events
        forgetURL = forget
        self.queue = queue
        self.post = post
        self.clock = clock
        self.log = log
    }

    /// Whether sending may be tried now (not waiting after a failure).
    func ready() -> Bool { retryAt.map { clock() >= $0 } ?? true }

    /**
     * Sends what's waiting, a batch at a time, while [stillOn] (usage data turned off meanwhile stops it). Stops at
     * the first batch that can't go now, which stays for later ([retryAt]). How many events the server took.
     */
    @discardableResult
    func send(stillOn: () -> Bool = { true }) -> Int {
        var sent = 0
        while stillOn(), let batch = queue.batch() {
            let answer = post.post(eventsURL, batch.body)
            offline = answer.status == nil
            switch Delivery.of(answer.status) {
            case .sent:
                queue.removeThrough(batch.last)
                sent += batch.count
                reset()
            case .refused:
                // Never happens with events the app checked against the whitelist; if it does, it can't be fixed by
                // sending them again.
                queue.removeThrough(batch.last)
                log("usage data: \(batch.count) events turned away (HTTP \(answer.status ?? 0))")
                reset()
            case .later:
                failed(answer.retryAfterSeconds)
                let why = answer.status.map { "HTTP \($0)" } ?? "no answer"
                log("usage data: \(batch.count) events kept for later (\(why))")
                if sent > 0 { log("usage data: \(sent) events sent") }
                return sent
            }
        }
        if sent > 0 { log("usage data: \(sent) events sent") }
        return sent
    }

    /**
     * Asks the server to delete everything it has under [installId] ("Delete my usage data"): true once it says it
     * has (202, also when it had nothing), false if it couldn't be asked or said no.
     */
    func forget(_ installId: String) -> Bool {
        let body = Data("{\"install_id\":\(Events.quoted(installId))}".utf8)
        let answer = post.post(forgetURL, body)
        offline = answer.status == nil
        return Delivery.of(answer.status) == .sent
    }

    /// Sending can be tried whenever again (it went through, or there's nothing left to send).
    func reset() {
        failures = 0
        retryAt = nil
    }

    /// A batch that couldn't go: sending waits ([backoff]).
    private func failed(_ retryAfterSeconds: Int64?) {
        failures += 1
        retryAt = clock() + Self.backoff(failures: failures, retryAfterSeconds: retryAfterSeconds)
    }

    /// The wait after a first failure.
    static let firstWait: Duration = .seconds(30)
    /// The longest the wait grows to by itself.
    static let longestWait: Duration = .seconds(30 * 60)
    /// The longest a server's Retry-After is followed for.
    static let longestRetryAfter: Duration = .seconds(24 * 60 * 60)

    /**
     * How long to wait after [failures] failures in a row: 30 s, then twice as long each time up to 30 minutes, or the
     * server's Retry-After if that's longer (up to a day).
     */
    static func backoff(failures: Int, retryAfterSeconds: Int64?) -> Duration {
        let doublings = min(max(failures - 1, 0), 16)
        let wait = min(firstWait * (1 << doublings), longestWait)
        guard let asked = retryAfterSeconds, asked > 0 else { return wait }
        return max(wait, min(.seconds(asked), longestRetryAfter))
    }
}
