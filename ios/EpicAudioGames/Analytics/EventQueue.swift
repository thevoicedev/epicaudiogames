// analytics/EventQueue.kt: the usage data waiting to be sent, kept in a file until the server has it.

import Foundation

/**
 * The usage data waiting to be sent: each event as the JSON the server takes, one a line, in [file]
 * (Application Support/analytics/queue.jsonl, out of backups as the random ID is: [NoBackup]), so nothing is lost when
 * the app is closed or the device is offline. It keeps at most [maxEvents] events, none older than [maxAge]: past
 * either, the oldest go. Each line starts with when its event joined (milliseconds since 1970, then a tab), so the
 * file's own dates are never read. What's sent goes in batches the server takes ([batch]: at most 100 events and
 * 64 KB), each taken off the queue once the server has answered for it ([removeThrough]).
 *
 * Not thread-safe: only the usage data's own queue uses it (UsageData's [Worker]), so the screen never waits for the
 * file. Android: analytics/EventQueue.kt.
 */
nonisolated final class EventQueue: @unchecked Sendable {
    /// An event waiting: [n] counts up as events join (afresh as the file is read); [at] is when it joined (ms).
    nonisolated private struct Entry {
        let n: Int64
        let at: Int64
        let json: String
    }

    private let file: URL
    private let now: @Sendable () -> Date
    private let maxEvents: Int
    private let maxAge: Duration
    private var entries: [Entry] = []
    private var next: Int64 = 0
    private var loaded = false

    init(
        file: URL, now: @escaping @Sendable () -> Date = { Date() }, maxEvents: Int = EventQueue.maxEvents,
        maxAge: Duration = EventQueue.maxAge
    ) {
        self.file = file
        self.now = now
        self.maxEvents = maxEvents
        self.maxAge = maxAge
    }

    /// How many events are waiting.
    var count: Int { load().count }

    var isEmpty: Bool { count == 0 }

    /// An event joins the end of the queue (and the file), the oldest going if that's too many.
    func add(_ json: String) {
        _ = load()
        let entry = Entry(n: next, at: Self.milliseconds(now()), json: json)
        next += 1
        entries.append(entry)
        if trim() { save() } else { append(entry) }
    }

    /**
     * The oldest events, as many as one request can carry: at most [maxEvents], their JSON array at most [maxBytes]
     * long. Nil with none waiting. An event too big to go even alone (none is: they're a few hundred bytes) goes.
     */
    func batch(maxEvents: Int = EventQueue.batchEvents, maxBytes: Int = EventQueue.batchBytes) -> Batch? {
        _ = load()
        var changed = trim()
        while let first = entries.first, first.json.utf8.count + 2 > maxBytes {
            entries.removeFirst()
            changed = true
        }
        if changed { save() }
        guard !entries.isEmpty else { return nil }
        var taken: [Entry] = []
        var size = 2                                    // [ and ]
        for e in entries {
            if taken.count == maxEvents { break }
            let more = e.json.utf8.count + (taken.isEmpty ? 0 : 1)     // and a comma
            if size + more > maxBytes { break }
            taken.append(e)
            size += more
        }
        guard let last = taken.last else { return nil }
        let body = Data(("[" + taken.map(\.json).joined(separator: ",") + "]").utf8)
        return Batch(body: body, count: taken.count, last: last.n)
    }

    /// The events up to the end of a batch (by [Batch.last]) are done with: sent, or turned away.
    func removeThrough(_ last: Int64) {
        _ = load()
        let before = entries.count
        entries.removeAll { $0.n <= last }
        if entries.count != before { save() }
    }

    /// Nothing waits any more, in memory or on the device.
    func clear() {
        entries = []
        loaded = true
        try? FileManager.default.removeItem(at: file)
    }

    /**
     * The events, read from the file the first time they're needed. A line that isn't one (cut short as the app was
     * stopped writing it) is skipped, and the file written again without it, before anything joins it: one bad event
     * would cost the whole batch it went in.
     */
    private func load() -> [Entry] {
        if loaded { return entries }
        loaded = true
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var skipped = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t"), let at = Int64(line[..<tab]) else {
                skipped = true
                continue
            }
            let json = String(line[line.index(after: tab)...])
            guard json.hasPrefix("{"), json.hasSuffix("}"),
                  (try? JSONSerialization.jsonObject(with: Data(json.utf8))) is [String: Any] else {
                skipped = true
                continue
            }
            entries.append(Entry(n: next, at: at, json: json))
            next += 1
        }
        if trim() || skipped { save() }
        return entries
    }

    /// Drops what's too old, then the oldest past the most kept. True if any went.
    private func trim() -> Bool {
        let before = entries.count
        let oldest = Self.milliseconds(now()) - Int64(maxAge.components.seconds) * 1000
        entries.removeAll { $0.at < oldest }
        if entries.count > maxEvents { entries.removeFirst(entries.count - maxEvents) }
        return entries.count != before
    }

    /// One more line at the end of the file.
    private func append(_ entry: Entry) {
        let data = Data(line(entry).utf8)
        do {
            try NoBackup.folder(file.deletingLastPathComponent())
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file)
                NoBackup.exclude(file)
            }
        } catch {
            // Kept in memory: it's sent this run, if not after.
        }
    }

    /// The file written again from what's in memory, whole: a new one, then put in the old one's place.
    private func save() {
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try NoBackup.folder(file.deletingLastPathComponent())
            try Data(entries.map(line).joined().utf8).write(to: file, options: .atomic)
            NoBackup.exclude(file)
        } catch {
            // As it was on the device; in memory, as it is now.
        }
    }

    private func line(_ e: Entry) -> String { "\(e.at)\t\(e.json)\n" }

    /// [date] in milliseconds since 1970 (the nearest: a Date is a Double's seconds).
    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// The most events kept: an offline week of steady play is a few hundred.
    static let maxEvents = 1_000
    /// The oldest an event is kept: a week.
    static let maxAge: Duration = .seconds(7 * 24 * 60 * 60)
    /// The most events the server takes in one request (web/analytics/whitelist.js's MAX_EVENTS).
    static let batchEvents = 100
    /// The biggest request body the server takes (web/server.js's MAX_BODY).
    static let batchBytes = 64 * 1024
}

/// Events to send together: [body] is their JSON array, [count] how many, [last] which was the last of them.
nonisolated struct Batch: Sendable, Equatable {
    let body: Data
    let count: Int
    let last: Int64
}
