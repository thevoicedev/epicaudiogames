// Kotlin's kotlin.random.Random (Random.kt) and XorWowRandom (XorWowRandom.kt), the generator behind Random(seed).

/**
 * The calls the engine makes on a Kotlin Random, so a seeded game draws exactly what the Kotlin engine draws, and a
 * test can stand in a generator that replays logged calls. The defaults below are kotlin.random.Random's own,
 * built on [nextBits] and [nextInt()]. Values are Kotlin Ints (32 bits) carried in Swift Ints.
 */
public protocol KotlinRandom: AnyObject {
    /// The next random bits, in the low [bitCount] bits (0 to 32).
    func nextBits(_ bitCount: Int) throws -> Int
    /// A random 32-bit Int.
    func nextInt() throws -> Int
    /// From 0 up to (not including) [until]; an empty range is an error.
    func nextInt(until: Int) throws -> Int
    /// From [from] up to (not including) [until].
    func nextInt(from: Int, until: Int) throws -> Int
    /// From 0.0 up to (not including) 1.0, with 53 random bits.
    func nextDouble() throws -> Double
    func nextBoolean() throws -> Bool
}

extension KotlinRandom {
    public func nextInt() throws -> Int { try nextBits(32) }

    public func nextInt(until: Int) throws -> Int { try nextInt(from: 0, until: until) }

    public func nextInt(from: Int, until: Int) throws -> Int {
        guard until > from, let from32 = Int32(exactly: from), let until32 = Int32(exactly: until) else {
            throw PlayError("Random range is empty: [\(from), \(until)).")
        }
        let n = until32 &- from32
        if n > 0 || n == Int32.min {
            let rnd: Int32
            if n & (0 &- n) == n {
                rnd = Int32(truncatingIfNeeded: try nextBits(31 - n.leadingZeroBitCount))
            } else {
                var v: Int32
                var bits: Int32
                repeat {
                    bits = Int32(bitPattern: UInt32(truncatingIfNeeded: try nextInt()) >> 1)
                    v = bits % n
                } while bits &- v &+ (n &- 1) < 0
                rnd = v
            }
            return Int(from32 &+ rnd)
        }
        while true {
            let rnd = try nextInt()
            if rnd >= from && rnd < until { return rnd }
        }
    }

    public func nextDouble() throws -> Double {
        let hi26 = Int64(try nextBits(26))
        let low27 = Int64(try nextBits(27))
        return Double((hi26 << 27) + low27) / Double(Int64(1) << 53)
    }

    public func nextBoolean() throws -> Bool { try nextBits(1) != 0 }

    /// Kotlin's Random.nextInt(range) for `(a..b).random(r)`.
    public func nextInt(in range: ClosedRange<Int>) throws -> Int {
        if range.upperBound < Int(Int32.max) { return try nextInt(from: range.lowerBound, until: range.upperBound + 1) }
        if range.lowerBound > Int(Int32.min) { return try nextInt(from: range.lowerBound - 1, until: range.upperBound) + 1 }
        return try nextInt()
    }
}

/**
 * Kotlin's XorWowRandom (Marsaglia's xorwow), which `Random(seed)` returns: the same seed gives the same numbers as
 * on the JVM. Seeding sets the state from two Ints and throws away the first 64 values.
 */
public final class XorWowRandom: KotlinRandom {
    private var x: Int32
    private var y: Int32
    private var z: Int32
    private var w: Int32
    private var v: Int32
    private var addend: Int32

    public init(seed1: Int32, seed2: Int32) {
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 &<< 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        // x | v is never 0 (v is ~x), so the state is always valid.
        for _ in 0..<64 { _ = step() }
    }

    /// Kotlin's Random(seed: Int).
    public convenience init(seed: Int32) {
        self.init(seed1: seed, seed2: seed >> 31)
    }

    /// Kotlin's Random(seed: Long).
    public convenience init(longSeed seed: Int64) {
        self.init(seed1: Int32(truncatingIfNeeded: seed), seed2: Int32(truncatingIfNeeded: seed >> 32))
    }

    /// Seeded from the system's random numbers: what the app plays with.
    public convenience init() {
        var g = SystemRandomNumberGenerator()
        self.init(longSeed: Int64(bitPattern: g.next()))
    }

    private func step() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t &<< 1)) ^ v0 ^ (v0 &<< 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    public func nextInt() -> Int { Int(step()) }

    public func nextBits(_ bitCount: Int) -> Int { Int(XorWowRandom.takeUpperBits(step(), bitCount)) }

    /// Kotlin's Int.takeUpperBits: the top [bitCount] bits, shifted down (Java shifts by the distance mod 32).
    static func takeUpperBits(_ value: Int32, _ bitCount: Int) -> Int32 {
        let shifted = Int32(bitPattern: UInt32(bitPattern: value) >> UInt32((32 - bitCount) & 31))
        return shifted & (Int32(truncatingIfNeeded: -bitCount) >> 31)
    }
}
