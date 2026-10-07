// kotlinx.serialization's JsonElement, as GameMap.kt reads it: objects keep their key order, numbers keep their text.

import Foundation

/**
 * A JSON value, read by [JSONParser]. Objects keep their keys in the order written (a key written twice keeps its
 * first place and its last value), and numbers, true and false keep their text, as kotlinx's JsonPrimitive does:
 * `1.0` stays "1.0". Equality is kotlinx's: objects are equal whatever their key order, and text compares UTF-16 unit
 * by unit (Kotlin's String.equals), not by Swift's canonical equivalence.
 */
public enum JSON: Sendable, Equatable {
    case object(JSONObject)
    case array([JSON])
    case string(String)
    /// A number, true or false, as written.
    case literal(String)
    case null

    // ----- kotlinx's accessors -----

    /// A string, number, true, false or null (a JsonPrimitive).
    public var isPrimitive: Bool {
        switch self {
        case .string, .literal, .null: true
        case .object, .array: false
        }
    }

    public var isString: Bool { if case .string = self { true } else { false } }

    /// JsonPrimitive.content: a string's text, a literal as written, "null" for null; nil for objects and arrays.
    public var content: String? {
        switch self {
        case .string(let s), .literal(let s): s
        case .null: "null"
        case .object, .array: nil
        }
    }

    /// JsonPrimitive.doubleOrNull: the content read as Kotlin's toDoubleOrNull reads it (so "1.5" in quotes counts).
    public var doubleOrNull: Double? { content.flatMap(Kt.toDoubleOrNull) }

    /// JsonPrimitive.booleanOrNull: "true" or "false" in any case, quoted or not.
    public var booleanOrNull: Bool? {
        guard let c = content else { return nil }
        if Kt.equalsIgnoreCase(c, "true") { return true }
        if Kt.equalsIgnoreCase(c, "false") { return false }
        return nil
    }

    /**
     * JsonPrimitive.longOrNull: kotlinx's own number reader (consumeNumericLiteral) on the content, which takes
     * "12", "-3", "1e2" and "\"5\"", refuses "1.5" and "1e-1", and stops at a space, comma or bracket ("12 x" is 12).
     */
    public var longOrNull: Int64? { content.flatMap(JSON.kotlinxLong) }

    /// JsonPrimitive.intOrNull: longOrNull, when it fits an Int.
    public var intOrNull: Int32? { longOrNull.flatMap { Int32(exactly: $0) } }

    /// JsonPrimitive.long: kotlinx's NumberFormatException as a PlayError.
    public func long() throws -> Int64 {
        guard let l = longOrNull else { throw PlayError("\(content ?? kotlinxDescription) is not a Long") }
        return l
    }

    /// JsonPrimitive.int.
    public func int() throws -> Int32 {
        guard let i = intOrNull else { throw PlayError("\(content ?? kotlinxDescription) is not an Int") }
        return i
    }

    /// JsonPrimitive.boolean.
    public func boolean() throws -> Bool {
        guard let b = booleanOrNull else { throw PlayError("\(kotlinxDescription) does not represent a Boolean") }
        return b
    }

    /// kotlinx's StringJsonLexer.consumeNumericLiteral: a Long, accumulated negatively; nil where it throws.
    static func kotlinxLong(_ s: String) -> Int64? {
        let u = Array(s.utf16)
        var current = 0
        while current < u.count && [0x20, 0x0A, 0x0D, 0x09].contains(u[current]) { current += 1 }
        guard current < u.count else { return nil }
        var quoted = false
        if u[current] == 0x22 {
            current += 1
            if current == u.count { return nil }
            quoted = true
        }
        // Characters kotlinx's lexer gives a token class of their own end the number.
        func ends(_ c: UInt16) -> Bool {
            c <= 0x20 || [0x2C, 0x3A, 0x7B, 0x7D, 0x5B, 0x5D, 0x22, 0x5C].contains(c)
        }
        var accumulator: Int64 = 0
        var exponentAccumulator: Int64 = 0
        var isNegative = false
        var isExponentPositive = false
        var hasExponent = false
        let start = current
        while current != u.count {
            let ch = u[current]
            if (ch == 0x65 || ch == 0x45) && !hasExponent {
                if current == start { return nil }
                isExponentPositive = true
                hasExponent = true
                current += 1
                continue
            }
            if ch == 0x2D && hasExponent {
                if current == start { return nil }
                isExponentPositive = false
                current += 1
                continue
            }
            if ch == 0x2B && hasExponent {
                if current == start { return nil }
                isExponentPositive = true
                current += 1
                continue
            }
            if ch == 0x2D {
                if current != start { return nil }
                isNegative = true
                current += 1
                continue
            }
            if ends(ch) { break }
            current += 1
            guard ch >= 0x30 && ch <= 0x39 else { return nil }
            let digit = Int64(ch - 0x30)
            if hasExponent {
                exponentAccumulator = exponentAccumulator &* 10 &+ digit
                continue
            }
            accumulator = accumulator &* 10 &- digit
            if accumulator > 0 { return nil }
        }
        if start == current || (isNegative && start == current - 1) { return nil }
        if quoted {
            guard current < u.count, u[current] == 0x22 else { return nil }
        }
        if hasExponent {
            let e = Double(exponentAccumulator)
            let d = Double(accumulator) * Foundation.pow(10.0, isExponentPositive ? e : -e)
            if d > 9223372036854775807.0 || d < -9223372036854775808.0 { return nil }
            if d.rounded(.down) != d { return nil }
            accumulator = Kt.saturatingLong(d)
        }
        if isNegative { return accumulator }
        if accumulator != Int64.min { return -accumulator }
        return nil
    }

    /// `as? JsonObject`.
    public var objectValue: JSONObject? { if case .object(let o) = self { o } else { nil } }

    /// `as? JsonArray`.
    public var arrayValue: [JSON]? { if case .array(let a) = self { a } else { nil } }

    /// `.jsonObject`: the object, or kotlinx's IllegalArgumentException as a MapError of kind other.
    public func jsonObject() throws -> JSONObject {
        guard case .object(let o) = self else { throw notA("JsonObject") }
        return o
    }

    /// `.jsonArray`.
    public func jsonArray() throws -> [JSON] {
        guard case .array(let a) = self else { throw notA("JsonArray") }
        return a
    }

    /// `.jsonPrimitive.content`.
    public func primitiveContent() throws -> String {
        guard let c = content else { throw notA("JsonPrimitive") }
        return c
    }

    /// kotlinx's class name for the element, as its cast errors say it.
    var kotlinxClass: String {
        switch self {
        case .object: "kotlinx.serialization.json.JsonObject"
        case .array: "kotlinx.serialization.json.JsonArray"
        case .string, .literal: "kotlinx.serialization.json.JsonLiteral"
        case .null: "kotlinx.serialization.json.JsonNull"
        }
    }

    private func notA(_ type: String) -> MapError {
        .other("Element class \(kotlinxClass) is not a \(type)")
    }

    /**
     * kotlinx's JsonElement.toString(): compact, keys in order, literals as written, and kotlinx's string escapes.
     * MapError messages embed it, as MapException's do.
     */
    public var kotlinxDescription: String { JSONWriter.write(self) }

    // ----- Building -----

    /// A number as a literal: whole numbers as integer digits ("3", "-0" for -0.0), others as Java writes them.
    public static func number(_ d: Double) -> JSON {
        if d == 0 && d.sign == .minus { return .literal("-0") }
        let l = Kt.saturatingLong(d)
        if d.isFinite && Double(l) == d { return .literal(String(l)) }
        return .literal(Kt.doubleString(d))
    }

    public static func bool(_ b: Bool) -> JSON { .literal(b ? "true" : "false") }

    /// A variable's value.
    public init(_ value: Value) {
        switch value {
        case .bool(let b): self = .bool(b)
        case .number(let d): self = .number(d)
        case .string(let s): self = .string(s)
        }
    }

    public subscript(key: String) -> JSON? { objectValue?[key] }

    /// kotlinx's equality, without recursion (JSON can be nested as deep as kotlinx reads it).
    public static func == (a: JSON, b: JSON) -> Bool {
        var pairs: [(JSON, JSON)] = [(a, b)]
        while let (x, y) = pairs.popLast() {
            switch (x, y) {
            case let (.string(s), .string(t)), let (.literal(s), .literal(t)):
                if !Kt.utf16Equal(s, t) { return false }
            case (.null, .null):
                break
            case let (.array(p), .array(q)):
                guard p.count == q.count else { return false }
                pairs.append(contentsOf: zip(p, q))
            case let (.object(p), .object(q)):
                guard p.count == q.count else { return false }
                for (k, v) in p {
                    guard let w = q[k] else { return false }
                    pairs.append((v, w))
                }
            default:
                return false
            }
        }
        return true
    }

    /**
     * Frees a value a level at a time. Swift frees nested arrays and objects by recursion, so JSON nested thousands
     * deep (which kotlinx reads) would run out of stack; this keeps each container's values alive on a list until the
     * container itself is gone. Leaves [value] as null.
     */
    public static func release(_ value: inout JSON) {
        var stack: [JSON] = [value]
        value = .null
        while var v = stack.popLast() {
            switch v {
            case .array(let a):
                v = .null
                stack.append(contentsOf: a)
            case .object(let o):
                v = .null
                stack.append(contentsOf: o.values)
            default:
                break
            }
        }
    }

    /// [release] for an object.
    public static func release(_ object: inout JSONObject) {
        var value = JSON.object(object)
        object = JSONObject()
        release(&value)
    }
}

/// A JSON object: its keys in the order written.
public typealias JSONObject = LinkedMap<JSON>

extension JSON: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
    ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) { self = .object(JSONObject(elements)) }
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .literal(String(value)) }
}
