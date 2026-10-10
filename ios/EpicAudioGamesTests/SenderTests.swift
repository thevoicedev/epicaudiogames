// analytics/SenderTest.kt: the usage data sent a batch at a time, waiting after failures, and the request itself.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * Sending the usage data (Analytics/Sender.swift): what's queued goes a batch at a time until it's all gone; what the
 * server took or turned away for good comes off the queue, and what it couldn't take now stays, sending waiting longer
 * after each failure (and as long as the server's Retry-After asks); the server is asked to forget an install. And
 * the system's URLSession, against a stand-in server: the request is the one web/server.js takes. Android:
 * SenderTest.kt.
 */
@MainActor
@Suite(.serialized)
final class SenderTests {
    private let folder: URL
    private let queue: EventQueue
    private let server = FakeServer()
    private let clock = TestClock()

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SenderTests-\(UUID().uuidString)")
        queue = EventQueue(file: folder.appendingPathComponent("queue.jsonl"))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sender() throws -> Sender {
        let clock = clock
        let sender = Sender(queue: queue, post: server, server: "https://epicaudiogames.com", clock: { clock.now })
        return try #require(sender)
    }

    private func queueEvents(_ n: Int) {
        for i in 0..<n { queue.add("{\"name\":\"tab_view\",\"n\":\(i)}") }
    }

    @Test func whatAnAnswerMeans() {
        #expect(Delivery.of(202) == .sent)
        #expect(Delivery.of(200) == .sent)
        for status in [400, 404, 405, 413, 415] { #expect(Delivery.of(status) == .refused, "\(status)") }
        let later: [Int?] = [nil, 429, 500, 502, 503, 301]
        for status in later { #expect(Delivery.of(status) == .later, "\(String(describing: status))") }
    }

    @Test func theWaitDoublesUpToHalfAnHourAndHeedsRetryAfter() {
        let waits = (1...10).map { Int(Sender.backoff(failures: $0, retryAfterSeconds: nil).components.seconds) }
        #expect(waits == [30, 60, 120, 240, 480, 960, 1800, 1800, 1800, 1800])
        #expect(Sender.backoff(failures: 1_000, retryAfterSeconds: nil) == .seconds(1800))
        // The server asks for longer (a 503 without its database: an hour): it gets it, up to a day.
        #expect(Sender.backoff(failures: 1, retryAfterSeconds: 3600) == .seconds(3600))
        #expect(Sender.backoff(failures: 2, retryAfterSeconds: 1) == .seconds(60))
        #expect(Sender.backoff(failures: 1, retryAfterSeconds: 1_000_000_000) == .seconds(24 * 3600))
    }

    @Test func itSendsABatchAtATimeUntilAllHaveGone() throws {
        queueEvents(250)
        let s = try sender()
        #expect(s.send() == 250)
        #expect(server.requests.count == 3)
        #expect(server.requests.allSatisfy { $0.url.absoluteString == "https://epicaudiogames.com/api/events" })
        #expect(server.requests.map { $0.body.components(separatedBy: "\"n\"").count - 1 } == [100, 100, 50])
        #expect(queue.isEmpty)
        #expect(s.retryAt == nil)
        #expect(s.ready())
        // Nothing left: nothing sent.
        #expect(s.send() == 0)
        #expect(server.requests.count == 3)
    }

    @Test func whatTheServerCantTakeNowStaysAndSendingWaits() throws {
        queueEvents(150)
        clock.now = .seconds(1_000)
        server.answers = [Response(202), Response(503, retryAfterSeconds: 60), Response(202)]
        let s = try sender()
        #expect(s.send() == 100)
        #expect(queue.count == 50)
        #expect(s.retryAt == .seconds(1_060))
        #expect(!s.ready())
        #expect(!s.offline)
        clock.now = .seconds(1_060) - .milliseconds(1)
        #expect(!s.ready())
        clock.now = .seconds(1_060)
        #expect(s.ready())
        #expect(s.send() == 50)
        #expect(queue.isEmpty)
        #expect(s.retryAt == nil)
        // The same events went again: the server keeps each once (by its install, session and number).
        #expect(server.requests[1].body == server.requests[2].body)
    }

    @Test func withNoNetworkItWaitsLongerEachTime() throws {
        queueEvents(5)
        server.answers = [Response(nil)]
        let s = try sender()
        #expect(s.send() == 0)
        #expect(s.offline)
        #expect(s.retryAt == .seconds(30))
        clock.now = .seconds(30)
        s.send()
        #expect(s.retryAt == .seconds(30 + 60))
        // A busy server's 429 counts as a failure too.
        server.answers = [Response(429, retryAfterSeconds: 5)]
        clock.now = .seconds(90)
        s.send()
        #expect(!s.offline)
        #expect(s.retryAt == .seconds(90 + 120))
        #expect(queue.count == 5)
        server.answers = [Response(202)]
        clock.now = .seconds(210)
        #expect(s.send() == 5)
        #expect(s.retryAt == nil)
    }

    @Test func whatsTurnedAwayGoesAndTheRestIsSent() throws {
        queueEvents(150)
        server.answers = [Response(400), Response(202)]
        #expect(try sender().send() == 50)
        #expect(server.requests.count == 2)
        #expect(queue.isEmpty)
    }

    @Test func turnedOffMeanwhileItStops() throws {
        queueEvents(250)
        var on = true
        let got = try sender().send(stillOn: {
            defer { on = false }
            return on
        })
        #expect(got == 100)
        #expect(server.requests.count == 1)
        #expect(queue.count == 150)
    }

    @Test func theServerIsAskedToForgetAnInstall() throws {
        let id = "4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10"
        let s = try sender()
        #expect(s.forget(id))
        #expect(server.requests.count == 1)
        #expect(server.requests[0].url.absoluteString == "https://epicaudiogames.com/api/forget")
        #expect(server.requests[0].body == "{\"install_id\":\"\(id)\"}")
        for answer in [Response(nil), Response(503), Response(429), Response(400)] {
            server.answers = [answer]
            #expect(!s.forget(id), "\(answer)")
        }
    }

    /// The system's URLSession, against a stand-in server (URLProtocol): a POST of the body as JSON, with the app's
    /// User-Agent, uncompressed; the server's status and Retry-After come back.
    @Test func theRequestIsTheOneTheServerTakes() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInServer.self]
        let http = HTTPPost(userAgent: "EpicAudioGames/1.0 (ios)", timeout: 5, configuration: configuration)
        let url = try #require(URL(string: "https://epicaudiogames.com/api/events"))
        let body = #"[{"name":"tab_view","props":{"tab":"shop"}}]"#
        StandInServer.reset(status: 202)
        #expect(http.post(url, Data(body.utf8)) == Response(202))
        let request = try #require(StandInServer.requests.first)
        #expect(request.method == "POST")
        #expect(request.url == url.absoluteString)
        #expect(request.headers["content-type"] == "application/json; charset=utf-8")
        #expect(request.headers["content-encoding"] == nil, "not compressed")
        #expect(request.headers["user-agent"] == "EpicAudioGames/1.0 (ios)")
        #expect(request.body == body)

        StandInServer.reset(status: 429)
        #expect(http.post(url, Data(body.utf8)) == Response(429, retryAfterSeconds: 7))
    }
}

/// A time on the usage data's clock (ContinuousClock's, in the app) that a test moves on by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Duration.zero

    var now: Duration {
        get {
            lock.lock()
            defer { lock.unlock() }
            return time
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            time = newValue
        }
    }
}

/**
 * Our server, faked: each request kept (its URL, and its body as text), answered with [answers] in turn, the last
 * again once they're used up (by default, 202). Used on the test's own thread (the tests' workers run their tasks at
 * once).
 */
final class FakeServer: Post, @unchecked Sendable {
    private(set) var requests: [(url: URL, body: String)] = []
    var answers = [Response(202)]
    /// Answers by the request's URL, when set (before [answers]).
    var answer: ((URL) -> Response)?

    func post(_ url: URL, _ body: Data) -> Response {
        requests.append((url, String(decoding: body, as: UTF8.self)))
        if let answer { return answer(url) }
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }

    /// The events sent so far, in the order they went (each batch as the server's whitelist reads it).
    func events(_ whitelist: Whitelist) throws -> [[String: JSONValue]] {
        try requests.filter { $0.url.path == "/api/events" }.flatMap { try whitelist.batch(Data($0.body.utf8)) }
    }
}

/**
 * Just enough of our server, as URLSession's own stand-in (a URLProtocol): it keeps each request (its method, URL,
 * headers by lower-case name and body) and answers with [status], with Retry-After: 7 for a 429.
 */
final class StandInServer: URLProtocol {
    struct Request {
        let method: String?
        let url: String?
        let headers: [String: String]
        let body: String
    }

    nonisolated(unsafe) static var requests: [Request] = []
    nonisolated(unsafe) static var status = 202

    static func reset(status: Int) {
        requests = []
        self.status = status
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        var headers: [String: String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] { headers[name.lowercased()] = value }
        Self.requests.append(Request(
            method: request.httpMethod, url: request.url?.absoluteString, headers: headers,
            body: String(decoding: body, as: UTF8.self)))
        var fields = ["Content-Type": "application/json; charset=utf-8"]
        if Self.status == 429 { fields["Retry-After"] = "7" }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: fields)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ok":true,"accepted":1}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A request body URLSession turned into a stream.
    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
