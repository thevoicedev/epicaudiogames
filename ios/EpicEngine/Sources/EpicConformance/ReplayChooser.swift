// LoggingRandom.kt's LoggingChooser, both ways: a Session's choose logged as [n, r], and logged draws played back.

import EpicEngine

/// Why a replay or a fixture failed: what was expected and where.
public struct ConformanceError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/// A Session's chooser, `rng.nextInt(n)`, logging each call as [n, r] (README section 7.2).
public final class LoggingChooser {
    private let rng: any KotlinRandom
    private var log: [CanonValue] = []

    public init(_ rng: any KotlinRandom) { self.rng = rng }

    public func callAsFunction(_ n: Int) throws -> Int {
        let r = try rng.nextInt(until: n)
        log.append([.int(n), .int(r)])
        return r
    }

    /// The draws since the last call, and a fresh log.
    public func take() -> CanonValue {
        defer { log.removeAll() }
        return .list(log)
    }
}

/**
 * Plays a turn's logged choose draws back to a Session: its k-th call must ask for the k-th draw's n, and gets its r.
 * The first call that differs fails, naming the draw; [finish] fails unless every draw was used.
 */
public final class ReplayChooser {
    private var draws: [(n: Int, r: Int)] = []
    private var next = 0

    public init() {}

    /// The next turn's draws: the fixture line's "rng", [[n, r], …].
    public func load(_ rng: JSON) throws {
        draws = try rng.fxArray().map { d in
            let pair = try d.fxArray()
            guard pair.count == 2 else { throw ConformanceError("a map draw isn't [n, r]: \(d.kotlinxDescription)") }
            return (try pair[0].fxInt(), try pair[1].fxInt())
        }
        next = 0
    }

    public func callAsFunction(_ n: Int) throws -> Int {
        guard next < draws.count else {
            throw ConformanceError("draw \(next): choose(\(n)), but the log has only \(draws.count) draws")
        }
        let d = draws[next]
        guard d.n == n else {
            throw ConformanceError("draw \(next): choose(\(n)), but the log has [\(d.n),\(d.r)]")
        }
        next += 1
        return d.r
    }

    /// Fails unless the turn used every draw.
    public func finish() throws {
        guard next == draws.count else {
            throw ConformanceError("the turn made \(next) draws, but the log has \(draws.count)")
        }
    }
}
