// analytics/EventQueueTest.kt: the usage data waiting to be sent, kept between runs, its caps, and its batches.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The usage data waiting to be sent (Analytics/EventQueue.swift): kept on the device between runs, out of backups, at
 * most 1,000 events and none older than a week (the oldest go first), and sent in batches the server takes: at most
 * 100 events and 64 KB. Android: EventQueueTest.kt.
 */
@MainActor
@Suite(.serialized)
final class EventQueueTests {
    private let folder: URL
    private let file: URL
    private let clock = WallClock(Date(timeIntervalSince1970: 1_791_538_860))

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("EventQueueTests-\(UUID().uuidString)")
        file = folder.appendingPathComponent("analytics/queue.jsonl")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func queue() -> EventQueue {
        let clock = clock
        return EventQueue(file: file, now: { clock.now })
    }

    /// A small event, numbered.
    private func event(_ n: Int, padding: Int = 0) -> String {
        "{\"name\":\"tab_view\",\"n\":\(n),\"pad\":\"\(String(repeating: "x", count: padding))\"}"
    }

    /// The numbers of the events in a batch.
    private func numbers(_ batch: Batch?) throws -> [Int] {
        let body = try #require(batch?.body)
        guard case .array(let events) = try JSONValue.parse(body) else { throw Trouble("not an array") }
        return events.compactMap { if case .int(let n)? = $0["n"] { Int(n) } else { nil } }
    }

    @Test func itKeepsAtMostAThousandEventsTheOldestGoingFirst() throws {
        let q = queue()
        for n in 0..<1_005 { q.add(event(n)) }
        #expect(q.count == 1_000)
        #expect(try numbers(q.batch()) == Array(5..<105))
        // So does the file: read again, it's the same thousand.
        let again = queue()
        #expect(again.count == 1_000)
        #expect(try numbers(again.batch()).first == 5)
    }

    @Test func itKeepsNothingOlderThanAWeek() throws {
        let q = queue()
        q.add(event(0))
        clock.advance(.seconds(24 * 60 * 60))
        q.add(event(1))
        clock.advance(EventQueue.maxAge - .seconds(24 * 60 * 60))      // the first is a week old, to the millisecond
        #expect(try numbers(q.batch()) == [0, 1])
        clock.advance(.milliseconds(1))
        #expect(try numbers(q.batch()) == [1])
        #expect(queue().count == 1)
        clock.advance(.seconds(24 * 60 * 60))
        #expect(q.batch() == nil)
        #expect(q.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func itKeepsItsEventsBetweenRunsAndSkipsALineCutShort() throws {
        let q = queue()
        for n in 0..<3 { q.add(event(n)) }
        // The app stopped as it wrote a fourth.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(EventQueue.milliseconds(clock.now))\t{\"name\":\"tab_vi".utf8))
        try handle.close()
        let again = queue()
        #expect(again.count == 3)
        #expect(try numbers(again.batch()) == [0, 1, 2])
        // Its file is tidied as it's read.
        #expect(try lines().count == 3)
        again.add(event(3))
        #expect(try numbers(queue().batch()) == [0, 1, 2, 3])
        // One cut short just after a bracket (it looks whole, but isn't JSON) is skipped too.
        try Data("\(EventQueue.milliseconds(clock.now))\t{\"name\":\"x\",\"props\":{\"a\":1}\n".utf8)
            .write(to: file)
        #expect(queue().isEmpty)
    }

    @Test func aBatchIsAtMostAHundredEvents() throws {
        let q = queue()
        for n in 0..<250 { q.add(event(n)) }
        var sizes: [Int] = []
        while let batch = q.batch() {
            sizes.append(batch.count)
            #expect(try numbers(batch).count == batch.count)
            q.removeThrough(batch.last)
        }
        #expect(sizes == [100, 100, 50])
        #expect(q.isEmpty)
    }

    @Test func aBatchIsAtMost64KB() throws {
        let q = queue()
        // Events of 1,000 bytes: 65 fit in 64 KB with the brackets and commas (65 × 1,001 + 1 = 65,066), 66 don't.
        let bytes = event(0).utf8.count
        for n in 0..<150 { q.add(event(n, padding: 1_000 - bytes - (n >= 10 ? 1 : 0) - (n >= 100 ? 1 : 0))) }
        #expect(event(5, padding: 1_000 - bytes).utf8.count == 1_000)
        let batch = try #require(q.batch())
        #expect(batch.count == 65)
        #expect(batch.body.count <= EventQueue.batchBytes)
        #expect(batch.body.count == 65 * 1_000 + 64 + 2)
        #expect(try numbers(batch) == Array(0..<65))
    }

    @Test func anEventTooBigToSendEvenAloneGoes() throws {
        let q = queue()
        q.add(event(0, padding: 70_000))
        q.add(event(1))
        #expect(try numbers(q.batch()) == [1])
        #expect(q.count == 1)
    }

    @Test func whatJoinedWhileABatchWasOnItsWayStays() throws {
        let q = queue()
        for n in 0..<10 { q.add(event(n)) }
        let batch = try #require(q.batch())
        for n in 10..<15 { q.add(event(n)) }
        q.removeThrough(batch.last)
        #expect(try numbers(q.batch()) == Array(10..<15))
        // And past the thousand meanwhile, the batch's own events having gone: nothing else goes with them.
        for n in 100..<1_100 { q.add(event(n)) }
        let next = try #require(q.batch())
        q.removeThrough(batch.last)
        #expect(q.count == 1_000)
        q.removeThrough(next.last)
        #expect(q.count == 900)
    }

    @Test func clearedNothingIsLeftOnTheDevice() {
        let q = queue()
        for n in 0..<3 { q.add(event(n)) }
        #expect(FileManager.default.fileExists(atPath: file.path))
        q.clear()
        #expect(q.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(queue().isEmpty)
    }

    @Test func itsFolderAndFileAreOutOfBackups() throws {
        let q = queue()
        q.add(event(0))
        for url in [file, file.deletingLastPathComponent()] {
            #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true, "\(url)")
        }
    }

    /// The file's lines.
    private func lines() throws -> [Substring] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    }
}

/// A wall clock a test moves on by hand.
final class WallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ by: Duration) {
        lock.lock()
        defer { lock.unlock() }
        let (seconds, attoseconds) = by.components
        date += Double(seconds) + Double(attoseconds) / 1e18
    }
}
