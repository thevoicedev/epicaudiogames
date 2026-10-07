// Reads JSON as kotlinx's Json.parseToJsonElement does for GameMap.kt (version 1.6.3), but with RFC 8259 literals only.

import Foundation

/// JSON that the reader can't take: where and why.
public struct JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    /// The byte offset where reading stopped.
    public let offset: Int

    public var description: String { "\(message) at offset \(offset)" }
}

/**
 * A byte-level reader into [JSON] that takes what kotlinx 1.6.3's JsonTreeReader takes from a map file:
 * - object keys keep their order (a repeated key keeps its first place and its last value, as kotlinx's LinkedHashMap
 *   does), and numbers keep their text;
 * - a string may hold raw control characters (kotlinx finds the closing quote and never checks them);
 * - a "]" that ends an array with something in it, followed by a value, carries the array on with that value (kotlinx's
 *   readArray loops while a value follows: `[1] 2]` is [1, 2]);
 * - nesting has no limit (kotlinx reads deep objects without recursion), and nothing here recurses;
 * - the bytes of a string are read as Java's UTF-8 decoder reads a file (File.readText): each malformed sequence is one
 *   U+FFFD, ending where JDK 17's decoder ends it.
 * kotlinx also takes unquoted words and numbers outside RFC 8259 (`01`, `+1`, `NaN`, `yes`) as values; this reader
 * doesn't (docs/IOS_PARITY.md, L12).
 */
public enum JSONParser {
    public static func parse(_ text: String) throws -> JSON {
        var text = text
        return try text.withUTF8 { try parse(bytes: $0) }
    }

    public static func parse(_ data: Data) throws -> JSON {
        try data.withUnsafeBytes { try parse(bytes: $0.bindMemory(to: UInt8.self)) }
    }

    public static func parse(bytes: UnsafeBufferPointer<UInt8>) throws -> JSON {
        var r = Reader(b: bytes)
        r.skipSpace()
        var value = try r.value()
        r.skipSpace()
        if r.i != bytes.count {
            JSON.release(&value)
            throw r.fail("unexpected characters after the JSON value")
        }
        return value
    }

    private struct Reader {
        let b: UnsafeBufferPointer<UInt8>
        var i = 0

        init(b: UnsafeBufferPointer<UInt8>) { self.b = b }

        func fail(_ why: String) -> JSONParseError { JSONParseError(message: why, offset: i) }

        mutating func skipSpace() {
            while i < b.count {
                switch b[i] {
                case 0x20, 0x09, 0x0A, 0x0D: i += 1
                default: return
                }
            }
        }

        /// An object or array being read: where its values (and, for an object, its keys) start on the stacks.
        private struct Open {
            let isObject: Bool
            let valueStart: Int
            let keyStart: Int
        }

        /// One value. What's read so far is freed a level at a time if the JSON turns out bad.
        mutating func value() throws -> JSON {
            var values: [JSON] = []
            do {
                return try value(&values)
            } catch {
                for k in values.indices { JSON.release(&values[k]) }
                throw error
            }
        }

        /// One value, read with stacks of the objects and arrays still open (no recursion, so no depth limit).
        private mutating func value(_ values: inout [JSON]) throws -> JSON {
            var open: [Open] = []
            var keys: [String] = []
            while true {
                var v: JSON
                skipSpace()
                guard i < b.count else { throw fail("the JSON ends too soon") }
                switch b[i] {
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    let isObject = b[i] == UInt8(ascii: "{")
                    i += 1
                    skipSpace()
                    if i < b.count && b[i] == (isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")) {
                        i += 1
                        v = isObject ? .object(JSONObject()) : .array([])
                    } else {
                        open.append(Open(isObject: isObject, valueStart: values.count, keyStart: keys.count))
                        if isObject { keys.append(try key()) }
                        continue
                    }
                case UInt8(ascii: "\""): v = .string(try string())
                case UInt8(ascii: "t"): try word("true"); v = .literal("true")
                case UInt8(ascii: "f"): try word("false"); v = .literal("false")
                case UInt8(ascii: "n"): try word("null"); v = .null
                case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): v = .literal(try number())
                default: throw fail("unexpected character")
                }
                // Put the value in what's open, closing each container that ends here.
                closing: while true {
                    guard let top = open.last else { return v }
                    values.append(v)
                    skipSpace()
                    guard i < b.count else { throw fail("the JSON ends too soon") }
                    if b[i] == UInt8(ascii: ",") {
                        i += 1
                        if top.isObject {
                            skipSpace()
                            keys.append(try key())
                        }
                        break
                    }
                    guard b[i] == (top.isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")) else {
                        throw fail(top.isObject ? "expected \",\" or \"}\"" : "expected \",\" or \"]\"")
                    }
                    i += 1
                    if !top.isObject {
                        // kotlinx's readArray: after "]", a value start carries the same array on.
                        skipSpace()
                        if i < b.count && !Reader.endsValues(b[i]) { break closing }
                    }
                    open.removeLast()
                    if top.isObject {
                        var o = JSONObject()
                        for (k, value) in zip(keys[top.keyStart...], values[top.valueStart...]) {
                            if var replaced = o.updateValue(value, forKey: k) { JSON.release(&replaced) }
                        }
                        keys.removeSubrange(top.keyStart...)
                        v = .object(o)
                    } else {
                        v = .array(Array(values[top.valueStart...]))
                    }
                    values.removeSubrange(top.valueStart...)
                }
            }
        }

        /// kotlinx's isValidValueStart, negated: the characters that can't start a value.
        static func endsValues(_ c: UInt8) -> Bool {
            c == UInt8(ascii: "}") || c == UInt8(ascii: "]") || c == UInt8(ascii: ":") || c == UInt8(ascii: ",")
        }

        /// An object's key and its colon.
        mutating func key() throws -> String {
            guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
            let k = try string()
            skipSpace()
            guard i < b.count, b[i] == UInt8(ascii: ":") else { throw fail("expected \":\"") }
            i += 1
            return k
        }

        mutating func word(_ w: StaticString) throws {
            let n = w.utf8CodeUnitCount
            guard i + n <= b.count else { throw fail("unexpected word") }
            let p = w.utf8Start
            for k in 0..<n where b[i + k] != p[k] { throw fail("unexpected word") }
            i += n
        }

        /// -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?, kept as written.
        mutating func number() throws -> String {
            let start = i
            func digit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }
            if b[i] == UInt8(ascii: "-") { i += 1 }
            guard i < b.count, digit(b[i]) else { throw fail("expected a digit") }
            if b[i] == UInt8(ascii: "0") {
                i += 1
            } else {
                while i < b.count && digit(b[i]) { i += 1 }
            }
            if i < b.count && b[i] == UInt8(ascii: ".") {
                i += 1
                guard i < b.count, digit(b[i]) else { throw fail("expected a digit") }
                while i < b.count && digit(b[i]) { i += 1 }
            }
            if i < b.count && (b[i] == UInt8(ascii: "e") || b[i] == UInt8(ascii: "E")) {
                i += 1
                if i < b.count && (b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-")) { i += 1 }
                guard i < b.count, digit(b[i]) else { throw fail("expected a digit") }
                while i < b.count && digit(b[i]) { i += 1 }
            }
            return String(decoding: UnsafeBufferPointer(rebasing: b[start..<i]), as: UTF8.self)
        }

        mutating func string() throws -> String {
            i += 1
            let start = i
            // Most strings have no escapes: take the bytes as they are.
            while i < b.count {
                let c = b[i]
                if c == UInt8(ascii: "\"") {
                    let s = JavaUTF8.string(UnsafeBufferPointer(rebasing: b[start..<i]))
                    i += 1
                    return s
                }
                if c == UInt8(ascii: "\\") { break }
                i += 1
            }
            var out: [UInt8] = []
            var run = start
            while i < b.count {
                let c = b[i]
                if c == UInt8(ascii: "\"") {
                    JavaUTF8.append(UnsafeBufferPointer(rebasing: b[run..<i]), to: &out)
                    i += 1
                    return String(decoding: out, as: UTF8.self)
                }
                if c != UInt8(ascii: "\\") {
                    i += 1
                    continue
                }
                JavaUTF8.append(UnsafeBufferPointer(rebasing: b[run..<i]), to: &out)
                i += 1
                guard i < b.count else { break }
                let e = b[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var unit = try hex4()
                    if unit >= 0xD800 && unit < 0xDC00, i + 1 < b.count, b[i] == UInt8(ascii: "\\"),
                       b[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let low = try hex4()
                        if low >= 0xDC00 && low < 0xE000 {
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    // A lone surrogate can't be held in a Swift String: it reads as U+FFFD (kotlinx keeps it).
                    let scalar = Unicode.Scalar(unit) ?? "\u{FFFD}"
                    out.append(contentsOf: String(Character(scalar)).utf8)
                default:
                    i -= 1
                    throw fail("an unknown escape")
                }
                run = i
            }
            throw fail("an unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= b.count else { throw fail("a short \\u escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = b[i]
                let d: UInt8
                switch c {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): d = c - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): d = c - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): d = c - UInt8(ascii: "A") + 10
                default: throw fail("a bad \\u escape")
                }
                v = v << 4 | UInt32(d)
                i += 1
            }
            return v
        }
    }
}

/**
 * UTF-8 as JDK 17's decoder reads it (sun.nio.cs.UTF_8, which File.readText uses): each malformed sequence becomes one
 * U+FFFD, and the decoder decides where a malformed sequence ends ("ED A0 80", an encoded surrogate, is one U+FFFD
 * where Swift's own decoding makes three). Bytes that end in the middle of a sequence are one U+FFFD, as at the end of
 * a file. ASCII bytes are never part of a malformed sequence, so a string's bytes read the same on their own as they
 * do inside the whole file.
 */
enum JavaUTF8 {
    static func string(_ b: UnsafeBufferPointer<UInt8>) -> String {
        if firstMalformed(b) == nil { return String(decoding: b, as: UTF8.self) }
        var out: [UInt8] = []
        append(b, to: &out)
        return String(decoding: out, as: UTF8.self)
    }

    /// The bytes, with each malformed sequence replaced by U+FFFD's UTF-8.
    static func append(_ b: UnsafeBufferPointer<UInt8>, to out: inout [UInt8]) {
        guard var bad = firstMalformed(b) else {
            out.append(contentsOf: b)
            return
        }
        var i = 0
        while true {
            out.append(contentsOf: UnsafeBufferPointer(rebasing: b[i..<bad.at]))
            out.append(contentsOf: [0xEF, 0xBF, 0xBD])
            i = bad.at + bad.length
            guard let next = firstMalformed(b, from: i) else {
                out.append(contentsOf: UnsafeBufferPointer(rebasing: b[i...]))
                return
            }
            bad = next
        }
    }

    /// Where the first malformed sequence at or after [from] starts, and how many bytes it covers.
    static func firstMalformed(_ b: UnsafeBufferPointer<UInt8>, from: Int = 0) -> (at: Int, length: Int)? {
        var i = from
        let n = b.count
        while i < n {
            let b1 = b[i]
            if b1 < 0x80 {
                i += 1
                continue
            }
            let step = sequence(b, i, n)
            if step.valid {
                i += step.length
            } else {
                return (i, step.length)
            }
        }
        return nil
    }

    private static func notContinuation(_ c: UInt8) -> Bool { c & 0xC0 != 0x80 }

    /// The sequence starting with the non-ASCII byte at [i]: its length, and whether it's well formed (the decoder's
    /// decodeArrayLoop and malformedN).
    private static func sequence(_ b: UnsafeBufferPointer<UInt8>, _ i: Int, _ n: Int) -> (length: Int, valid: Bool) {
        let b1 = b[i]
        let remaining = n - i
        switch b1 {
        case 0xC2...0xDF:
            if remaining < 2 { return (remaining, false) }
            return notContinuation(b[i + 1]) ? (1, false) : (2, true)
        case 0xE0...0xEF:
            if remaining < 3 {
                if remaining > 1 && ((b1 == 0xE0 && b[i + 1] & 0xE0 == 0x80) || notContinuation(b[i + 1])) {
                    return (1, false)
                }
                return (remaining, false)
            }
            let b2 = b[i + 1]
            let b3 = b[i + 2]
            if (b1 == 0xE0 && b2 & 0xE0 == 0x80) || notContinuation(b2) || notContinuation(b3) {
                return ((b1 == 0xE0 && b2 & 0xE0 == 0x80) || notContinuation(b2) ? 1 : 2, false)
            }
            let c = (UInt32(b1 & 0x0F) << 12) | (UInt32(b2 & 0x3F) << 6) | UInt32(b3 & 0x3F)
            if c >= 0xD800 && c <= 0xDFFF { return (3, false) }
            return (3, true)
        case 0xF0...0xF7:
            func malformed4First(_ b2: UInt8) -> Bool {
                (b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF)) || (b1 == 0xF4 && b2 & 0xF0 != 0x80) || notContinuation(b2)
            }
            if remaining < 4 {
                if b1 > 0xF4 || (remaining > 1 && malformed4First(b[i + 1])) { return (1, false) }
                if remaining > 2 && notContinuation(b[i + 2]) { return (2, false) }
                return (remaining, false)
            }
            let b2 = b[i + 1]
            let b3 = b[i + 2]
            let b4 = b[i + 3]
            let uc = (UInt32(b1 & 0x07) << 18) | (UInt32(b2 & 0x3F) << 12) | (UInt32(b3 & 0x3F) << 6) | UInt32(b4 & 0x3F)
            if notContinuation(b2) || notContinuation(b3) || notContinuation(b4) || uc < 0x10000 || uc >= 0x110000 {
                if b1 > 0xF4 || malformed4First(b2) { return (1, false) }
                if notContinuation(b3) { return (2, false) }
                return (3, false)
            }
            return (4, true)
        default:
            return (1, false)
        }
    }
}
