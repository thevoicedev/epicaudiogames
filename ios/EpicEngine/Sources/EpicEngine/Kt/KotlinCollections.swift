// Kotlin's collection functions the engine uses with a Random (shuffled, random, randomOrNull) and a few others.

extension Collection {
    /// Kotlin's shuffled(random): from the last index down to 1, swap with nextInt(i + 1).
    public func kShuffled(_ random: any KotlinRandom) throws -> [Element] {
        var out = Array(self)
        var i = out.count - 1
        while i >= 1 {
            let j = try random.nextInt(until: i + 1)
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }

    /// Kotlin's random(random): one draw of nextInt(count); an empty collection is an error.
    public func kRandom(_ random: any KotlinRandom) throws -> Element {
        guard !isEmpty else { throw PlayError("Collection is empty.") }
        return self[index(startIndex, offsetBy: try random.nextInt(until: count))]
    }

    /// Kotlin's randomOrNull(random): null, with no draw, when empty.
    public func kRandomOrNull(_ random: any KotlinRandom) throws -> Element? {
        guard !isEmpty else { return nil }
        return self[index(startIndex, offsetBy: try random.nextInt(until: count))]
    }
}

extension Sequence {
    /// Kotlin's sortedBy / sortedByDescending: stable, so equal keys keep their order.
    public func stableSorted<K: Comparable>(descending: Bool = false, by key: (Element) throws -> K) rethrows -> [Element] {
        let keyed = try enumerated().map { (offset: $0.offset, key: try key($0.element), element: $0.element) }
        return keyed.sorted { a, b in
            if a.key != b.key { return descending ? a.key > b.key : a.key < b.key }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Kotlin's maxBy: the first of the largest (nil when empty).
    public func kMaxBy<K: Comparable>(_ key: (Element) throws -> K) rethrows -> Element? {
        var best: (Element, K)?
        for e in self {
            let k = try key(e)
            if best == nil || k > best!.1 { best = (e, k) }
        }
        return best?.0
    }
}

extension Sequence where Element: Hashable {
    /// Kotlin's distinct(): each element once, in first-seen order.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Sequence where Element == String {
    /// Kotlin's distinct() (and toSet()) on text: the same UTF-16 units are the same element, so canonically equal
    /// spellings ("é" and "e" + U+0301) are both kept, as in Kotlin.
    public func uniqued() -> [String] {
        var seen = Set<ExactKey>()
        return filter { seen.insert(ExactKey($0)).inserted }
    }
}

extension Comparable {
    /// Kotlin's coerceIn: an empty range is an error.
    public func clamped(_ low: Self, _ high: Self) throws -> Self {
        guard high >= low else {
            throw PlayError("Cannot coerce value to an empty range: maximum \(high) is less than minimum \(low).")
        }
        if self < low { return low }
        if self > high { return high }
        return self
    }
}
