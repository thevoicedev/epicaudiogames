// LoggingRandom.kt, played back: a Kotlin Random that returns logged draws and fails at the first call that differs.

import EpicEngine

/// One logged call on a Kotlin Random, as README section 7.2 writes it.
public enum Draw: Equatable, Sendable, CustomStringConvertible {
    case nextInt(Int)
    case nextIntUntil(until: Int, Int)
    case nextIntFrom(from: Int, until: Int, Int)
    case nextBits(bitCount: Int, Int)
    case nextDouble(Double)
    case nextBoolean(Bool)

    /// A fixture draw: ["nextInt", r], ["nextInt", until, r], ["nextInt", from, until, r], ["nextBits", n, r],
    /// ["nextDouble", d], ["nextBoolean", b].
    public init(_ j: JSON) throws {
        let a = try j.fxArray()
        guard let method = a.first?.content else { throw ConformanceError("not a draw: \(j.kotlinxDescription)") }
        switch (method, a.count) {
        case ("nextInt", 2): self = .nextInt(try a[1].fxInt())
        case ("nextInt", 3): self = .nextIntUntil(until: try a[1].fxInt(), try a[2].fxInt())
        case ("nextInt", 4): self = .nextIntFrom(from: try a[1].fxInt(), until: try a[2].fxInt(), try a[3].fxInt())
        case ("nextBits", 3): self = .nextBits(bitCount: try a[1].fxInt(), try a[2].fxInt())
        case ("nextDouble", 2): self = .nextDouble(try a[1].fxDouble())
        case ("nextBoolean", 2): self = .nextBoolean(try a[1].fxBool())
        default: throw ConformanceError("not a draw: \(j.kotlinxDescription)")
        }
    }

    /// A turn line's "rng": its draws, in order.
    public static func list(_ rng: JSON) throws -> [Draw] { try rng.fxArray().map(Draw.init) }

    /// The draw as the fixtures write it.
    public var canon: CanonValue {
        switch self {
        case .nextInt(let r): ["nextInt", .int(r)]
        case .nextIntUntil(let until, let r): ["nextInt", .int(until), .int(r)]
        case .nextIntFrom(let from, let until, let r): ["nextInt", .int(from), .int(until), .int(r)]
        case .nextBits(let n, let r): ["nextBits", .int(n), .int(r)]
        case .nextDouble(let d): ["nextDouble", .double(d)]
        case .nextBoolean(let b): ["nextBoolean", .bool(b)]
        }
    }

    public var description: String { Canon.json(canon) }
}

/**
 * Plays logged draws back to a game: each call must be the next draw's method with its bounds, and returns its
 * result. The first call that differs fails, naming the draw's index; [finish] fails unless every draw was used.
 */
public final class ReplayRandom: KotlinRandom {
    private var draws: [Draw]
    private var next = 0

    public init(_ draws: [Draw] = []) { self.draws = draws }

    /// Another turn's draws.
    public func load(_ draws: [Draw]) {
        self.draws = draws
        next = 0
    }

    /// The next draw's result, when [result] finds it is the call made; else the failure, naming the draw.
    private func take<T>(_ call: String, _ result: (Draw) -> T?) throws -> T {
        guard next < draws.count else {
            throw ConformanceError("draw \(next): the game called \(call), but the log has only \(draws.count) draws")
        }
        guard let r = result(draws[next]) else {
            throw ConformanceError("draw \(next): the game called \(call), but the log has \(draws[next])")
        }
        next += 1
        return r
    }

    public func nextBits(_ bitCount: Int) throws -> Int {
        try take("nextBits(\(bitCount))") {
            if case .nextBits(bitCount, let r) = $0 { return r }
            return nil
        }
    }

    public func nextInt() throws -> Int {
        try take("nextInt()") {
            if case .nextInt(let r) = $0 { return r }
            return nil
        }
    }

    public func nextInt(until: Int) throws -> Int {
        try take("nextInt(\(until))") {
            if case .nextIntUntil(until, let r) = $0 { return r }
            return nil
        }
    }

    public func nextInt(from: Int, until: Int) throws -> Int {
        try take("nextInt(\(from), \(until))") {
            if case .nextIntFrom(from, until, let r) = $0 { return r }
            return nil
        }
    }

    public func nextDouble() throws -> Double {
        try take("nextDouble()") {
            if case .nextDouble(let d) = $0 { return d }
            return nil
        }
    }

    public func nextBoolean() throws -> Bool {
        try take("nextBoolean()") {
            if case .nextBoolean(let b) = $0 { return b }
            return nil
        }
    }

    /// Fails unless every draw was used.
    public func finish() throws {
        guard next == draws.count else {
            throw ConformanceError(
                "draw \(next): the game made no more calls, but the log has \(draws[next]) (\(draws.count) draws)")
        }
    }
}

/**
 * A Random that hands every call on to [inner] and logs it at the outermost call, as LoggingRandom.kt does (so a
 * `nextInt(n)` is one draw, whatever XorWow does inside).
 */
public final class LoggingRandom: KotlinRandom {
    private let inner: any KotlinRandom
    private var log: [Draw] = []

    public init(_ inner: any KotlinRandom) { self.inner = inner }

    /// The draws since the last call, and a fresh log.
    public func take() -> [Draw] {
        defer { log.removeAll() }
        return log
    }

    public func nextBits(_ bitCount: Int) throws -> Int {
        let r = try inner.nextBits(bitCount)
        log.append(.nextBits(bitCount: bitCount, r))
        return r
    }

    public func nextInt() throws -> Int {
        let r = try inner.nextInt()
        log.append(.nextInt(r))
        return r
    }

    public func nextInt(until: Int) throws -> Int {
        let r = try inner.nextInt(until: until)
        log.append(.nextIntUntil(until: until, r))
        return r
    }

    public func nextInt(from: Int, until: Int) throws -> Int {
        let r = try inner.nextInt(from: from, until: until)
        log.append(.nextIntFrom(from: from, until: until, r))
        return r
    }

    public func nextDouble() throws -> Double {
        let d = try inner.nextDouble()
        log.append(.nextDouble(d))
        return d
    }

    public func nextBoolean() throws -> Bool {
        let b = try inner.nextBoolean()
        log.append(.nextBoolean(b))
        return b
    }
}
