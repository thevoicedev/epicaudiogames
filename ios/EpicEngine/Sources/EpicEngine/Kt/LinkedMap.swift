// Kotlin's LinkedHashMap<String, V> (mutableMapOf, mapValues, Map.plus): string keys in insertion order.

/**
 * A map that keeps its keys in the order they were first put, as Kotlin's maps do: setting a key that is already
 * there keeps its place, a new key goes at the end. Two maps are equal when they hold the same keys and values, in
 * any order (Kotlin's Map.equals). Keys are the same key when their UTF-16 units are (Kotlin's String.equals), so
 * "é" and "e" + U+0301, or U+212A KELVIN SIGN and "K", are two keys, as they are in Kotlin.
 */
public struct LinkedMap<V> {
    public private(set) var keys: [String]
    public private(set) var values: [V]
    /**
     * Each key's position by Swift's == (canonical equivalence), kept once the map is big enough for it to pay (most
     * JSON objects have a few keys). Text that is the same is canonically equal, so the index finds the one key that
     * can be it, and the bytes say whether it is. A map with two canonically equal keys ([hasTwins]) has no index.
     */
    private var index: [String: Int]?
    private var hasTwins = false

    private static var indexFrom: Int { 12 }

    public init() {
        keys = []
        values = []
        index = nil
    }

    private func position(_ key: String) -> Int? {
        if let index {
            guard let i = index[key] else { return nil }
            return Kt.sameUTF8(keys[i], key) ? i : nil
        }
        var from = 0
        while from < keys.count, let i = keys[from...].firstIndex(of: key) {
            if Kt.sameUTF8(keys[i], key) { return i }
            from = i + 1
        }
        return nil
    }

    /// The pairs in order; a key given twice keeps its first place and its last value.
    public init<S: Sequence>(_ pairs: S) where S.Element == (String, V) {
        self.init()
        for (k, v) in pairs { self[k] = v }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public func contains(_ key: String) -> Bool { position(key) != nil }

    /// Setting nil removes the key (the keys after it move up).
    public subscript(key: String) -> V? {
        get { position(key).map { values[$0] } }
        set {
            if let v = newValue {
                updateValue(v, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    /// Puts the value (in the key's place, or at the end); returns the value it replaced.
    @discardableResult
    public mutating func updateValue(_ value: V, forKey key: String) -> V? {
        // One look for the key, noting any canonically equal key that isn't it (Kotlin keeps both).
        var twin = false
        if let index {
            if let i = index[key] {
                if Kt.sameUTF8(keys[i], key) { return replace(i, value) }
                twin = true
            }
        } else {
            var from = 0
            while from < keys.count, let i = keys[from...].firstIndex(of: key) {
                if Kt.sameUTF8(keys[i], key) { return replace(i, value) }
                twin = true
                from = i + 1
            }
        }
        if twin {
            // Only the slow search can tell the two apart.
            hasTwins = true
            index = nil
        }
        keys.append(key)
        values.append(value)
        if index != nil {
            index![key] = keys.count - 1
        } else if !hasTwins && keys.count > LinkedMap.indexFrom {
            index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        }
        return nil
    }

    private mutating func replace(_ i: Int, _ value: V) -> V {
        let old = values[i]
        values[i] = value
        return old
    }

    @discardableResult
    public mutating func removeValue(forKey key: String) -> V? {
        guard let i = position(key) else { return nil }
        keys.remove(at: i)
        let old = values.remove(at: i)
        if index != nil {
            index![key] = nil
            for j in i..<keys.count { index![keys[j]] = j }
        }
        return old
    }

    public mutating func removeAll() {
        keys.removeAll()
        values.removeAll()
        index = nil
        hasTwins = false
    }

    /// Kotlin's putAll: each key replaces in place or goes at the end, in the other map's order.
    public mutating func putAll(_ other: LinkedMap<V>) {
        // Into an empty map that is the other map itself.
        if isEmpty {
            self = other
            return
        }
        for (k, v) in other { self[k] = v }
    }

    /// Kotlin's `a + b`: this map's keys first (with b's value where b has them), then b's new keys.
    public func merging(_ other: LinkedMap<V>) -> LinkedMap<V> {
        var out = self
        out.putAll(other)
        return out
    }

    /// Kotlin's `map - key`.
    public func removing(_ key: String) -> LinkedMap<V> {
        var out = self
        out.removeValue(forKey: key)
        return out
    }

    public func mapValues<T>(_ transform: (String, V) throws -> T) rethrows -> LinkedMap<T> {
        var out = LinkedMap<T>()
        for (k, v) in self { out[k] = try transform(k, v) }
        return out
    }

    public func mapValues<T>(_ transform: (V) throws -> T) rethrows -> LinkedMap<T> {
        try mapValues { _, v in try transform(v) }
    }

    /// The entry at a position, in order.
    public func entry(at i: Int) -> (key: String, value: V) { (keys[i], values[i]) }
}

extension LinkedMap: Sequence {
    public struct Iterator: IteratorProtocol {
        let map: LinkedMap
        var i = 0
        public mutating func next() -> (key: String, value: V)? {
            guard i < map.keys.count else { return nil }
            defer { i += 1 }
            return (map.keys[i], map.values[i])
        }
    }

    public func makeIterator() -> Iterator { Iterator(map: self) }
}

extension LinkedMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, V)...) {
        self.init(elements)
    }
}

extension LinkedMap: Equatable where V: Equatable {
    public static func == (a: LinkedMap, b: LinkedMap) -> Bool {
        guard a.count == b.count else { return false }
        for (k, v) in a {
            guard let w = b[k], w == v else { return false }
        }
        return true
    }
}

extension LinkedMap: Hashable where V: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Order-free, as equality is.
        var sum = 0
        for (k, v) in self {
            var h = Hasher()
            h.combine(k)
            h.combine(v)
            sum = sum &+ h.finalize()
        }
        hasher.combine(count)
        hasher.combine(sum)
    }
}

extension LinkedMap: Sendable where V: Sendable {}

/**
 * A String that is equal to another only when their UTF-16 units are (Kotlin's String.equals and hashCode), for
 * dictionaries and sets that stand in for Kotlin's. A plain Swift String key would merge canonically equal text.
 */
struct ExactKey: Hashable, Sendable {
    let text: String

    init(_ text: String) { self.text = text }

    static func == (a: ExactKey, b: ExactKey) -> Bool { Kt.utf16Equal(a.text, b.text) }

    /// Swift's own hash: text with the same UTF-16 units is canonically equal too, so it hashes the same.
    func hash(into hasher: inout Hasher) { hasher.combine(text) }
}
