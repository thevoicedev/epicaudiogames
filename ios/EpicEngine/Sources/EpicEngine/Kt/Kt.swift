// Kotlin and Java library behaviour the engine relies on: toDoubleOrNull, Double.toString, toLong, mod, Math.max.

/**
 * The few Kotlin/JVM library functions whose exact behaviour the Kotlin engine depends on, so the Swift engine
 * reads numbers, writes numbers and compares text the same way. Strings are compared and measured in UTF-16 units,
 * as Kotlin's are.
 */
public enum Kt {
    // ----- Numbers from text -----

    /**
     * Kotlin's String.toDoubleOrNull on the JVM: Java's Double.valueOf grammar (leading and trailing characters up to
     * U+0020, a sign, "NaN", "Infinity", decimal or hex digits, an exponent, an f/F/d/D suffix), else null.
     */
    public static func toDoubleOrNull(_ s: String) -> Double? {
        let u = Array(s.utf16)
        var i = 0
        var end = u.count
        while i < end && u[i] <= 0x20 { i += 1 }
        while end > i && u[end - 1] <= 0x20 { end -= 1 }
        guard i < end else { return nil }
        var negative = false
        if u[i] == 0x2B || u[i] == 0x2D {
            negative = u[i] == 0x2D
            i += 1
        }
        func rest(_ word: String) -> Bool { u[i..<end].elementsEqual(word.utf16) }
        if rest("NaN") { return Double.nan }
        if rest("Infinity") { return negative ? -Double.infinity : Double.infinity }
        // An optional type suffix.
        if end > i, [0x66, 0x46, 0x64, 0x44].contains(u[end - 1]) { end -= 1 }
        guard i < end else { return nil }
        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
        var j = i
        if end - j >= 2 && u[j] == 0x30 && (u[j + 1] == 0x78 || u[j + 1] == 0x58) {
            // Hex: 0x digits [.] [digits] p [+-] digits (at least one hex digit).
            j += 2
            var hexDigits = 0
            while j < end && isHex(u[j]) { j += 1; hexDigits += 1 }
            if j < end && u[j] == 0x2E {
                j += 1
                while j < end && isHex(u[j]) { j += 1; hexDigits += 1 }
            }
            guard hexDigits > 0, j < end, u[j] == 0x70 || u[j] == 0x50 else { return nil }
            j += 1
            if j < end && (u[j] == 0x2B || u[j] == 0x2D) { j += 1 }
            let expStart = j
            while j < end && isDigit(u[j]) { j += 1 }
            guard j == end, j > expStart else { return nil }
        } else {
            var digits = 0
            while j < end && isDigit(u[j]) { j += 1; digits += 1 }
            if j < end && u[j] == 0x2E {
                j += 1
                while j < end && isDigit(u[j]) { j += 1; digits += 1 }
            }
            guard digits > 0 else { return nil }
            if j < end && (u[j] == 0x65 || u[j] == 0x45) {
                j += 1
                if j < end && (u[j] == 0x2B || u[j] == 0x2D) { j += 1 }
                let expStart = j
                while j < end && isDigit(u[j]) { j += 1 }
                guard j > expStart else { return nil }
            }
            guard j == end else { return nil }
        }
        let body = String(decoding: u[i..<end], as: UTF16.self)
        guard let v = Double(body) else { return nil }
        return negative ? -v : v
    }

    /// Kotlin's String.toIntOrNull (and toInt, which throws instead): a sign, then decimal digits, in Int range.
    public static func int32OrNull(_ s: String) -> Int32? {
        integerOrNull(s, min: Int64(Int32.min), max: Int64(Int32.max)).map { Int32($0) }
    }

    /// Kotlin's String.toLongOrNull.
    public static func int64OrNull(_ s: String) -> Int64? {
        integerOrNull(s, min: Int64.min, max: Int64.max)
    }

    private static func integerOrNull(_ s: String, min: Int64, max: Int64) -> Int64? {
        let u = Array(s.utf16)
        guard !u.isEmpty else { return nil }
        var i = 0
        var negative = false
        if u[0] < 0x30 {
            guard u.count > 1 else { return nil }
            if u[0] == 0x2D { negative = true } else if u[0] != 0x2B { return nil }
            i = 1
        }
        // Accumulated negatively, as Kotlin does, so Long.MIN_VALUE fits.
        var total: Int64 = 0
        let limit = negative ? min : -max
        while i < u.count {
            guard let d = decimalDigit(u[i]) else { return nil }
            let (m, o1) = total.multipliedReportingOverflow(by: 10)
            let (t, o2) = m.subtractingReportingOverflow(Int64(d))
            if o1 || o2 || t < limit { return nil }
            total = t
            i += 1
        }
        return negative ? total : -total
    }

    /// Java's Character.digit(c, 10): ASCII digits and the other Unicode decimal digits of the BMP.
    static func decimalDigit(_ c: UInt16) -> Int? {
        if c >= 0x30 && c <= 0x39 { return Int(c - 0x30) }
        guard c >= 0x80, let scalar = Unicode.Scalar(c), scalar.properties.numericType == .decimal,
              let v = scalar.properties.numericValue else { return nil }
        return Int(v)
    }

    // ----- Numbers to text -----

    /**
     * Java's Double.toString: "NaN", "Infinity", "0.0", plain digits with at least one decimal between 10^-3 and
     * 10^7 ("100.0", "0.001"), otherwise "d.dddE-n" ("1.0E7", "1.0E-5"). The digits are JDK 17's, which aren't always
     * the shortest ("4.9E-324", "9.999999999999999E22"): see [JavaDoubleString].
     */
    public static func doubleString(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        if d == 0 { return d.sign == .minus ? "-0.0" : "0.0" }
        return JavaDoubleString.string(d)
    }

    /// Kotlin's Double.toLong(): NaN is 0, out-of-range values saturate, the rest truncate.
    public static func saturatingLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9223372036854775807.0 { return Int64.max }
        if d <= -9223372036854775808.0 { return Int64.min }
        return Int64(d)
    }

    /// Kotlin's Double.mod: the remainder of floored division, with the divisor's sign.
    public static func floorMod(_ a: Double, _ b: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: b)
        return r != 0 && signum(r) != signum(b) ? r + b : r
    }

    /// Java's Math.floorMod for Ints.
    public static func floorMod(_ a: Int32, _ b: Int32) -> Int32 {
        let r = a % b
        return r != 0 && (r < 0) != (b < 0) ? r + b : r
    }

    /// Kotlin's Double.sign (Math.signum): -1.0, 1.0, or the value itself for zeros and NaN.
    public static func signum(_ d: Double) -> Double {
        if d.isNaN || d == 0 { return d }
        return d < 0 ? -1 : 1
    }

    /// Java's Math.max: NaN wins, and 0.0 is above -0.0.
    public static func max(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && a.sign == .minus { return b }
        return a >= b ? a : b
    }

    /// Java's Math.min: NaN wins, and -0.0 is below 0.0.
    public static func min(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return a }
        if a == 0 && b == 0 && b.sign == .minus { return b }
        return a <= b ? a : b
    }

    // ----- Text -----

    /// Kotlin's String.compareTo: UTF-16 units in order, then length (only the sign is meaningful).
    public static func compare(_ a: String, _ b: String) -> Int {
        var i = a.utf16.makeIterator()
        var j = b.utf16.makeIterator()
        while true {
            switch (i.next(), j.next()) {
            case let (x?, y?): if x != y { return Int(x) - Int(y) }
            case (nil, nil): return 0
            case (nil, _): return -1
            case (_, nil): return 1
            }
        }
    }

    /**
     * Kotlin's String equality: the same UTF-16 units. Swift's == also treats canonically equal text as equal ("é" and
     * "e" + U+0301, U+212A KELVIN SIGN and "K"), so it only rules text out quickly; text it calls equal is the same
     * when its UTF-8 bytes are (a Swift String holds whole scalars, so the same bytes are the same UTF-16 units).
     */
    public static func utf16Equal(_ a: String, _ b: String) -> Bool { a == b && sameUTF8(a, b) }

    /// For text Swift's == already calls equal: whether it is the same text, byte for byte.
    @inline(__always)
    static func sameUTF8(_ a: String, _ b: String) -> Bool {
        a.utf8.count == b.utf8.count && a.utf8.elementsEqual(b.utf8)
    }

    public static func utf16Less(_ a: String, _ b: String) -> Bool { compare(a, b) < 0 }

    /// Kotlin's String.length.
    public static func length(_ s: String) -> Int { s.utf16.count }

    /// Kotlin's String.take(n): the first n UTF-16 units.
    public static func take(_ s: String, _ n: Int) -> String {
        let u = s.utf16
        guard u.count > n else { return s }
        return String(decoding: u.prefix(n), as: UTF16.self)
    }

    /**
     * Kotlin's String.take(n) as the JVM writes it out: where the cut halves a surrogate pair, Kotlin keeps the lone
     * high surrogate, which a Swift String can't hold and the JVM's UTF-8 encoder writes as "?" (GameMap.kt's
     * "missing" messages, as printed and as the goldens hold them).
     */
    public static func takePrinted(_ s: String, _ n: Int) -> String {
        let u = s.utf16
        guard u.count > n else { return s }
        let cut = u.prefix(n)
        if let last = cut.last, UTF16.isLeadSurrogate(last) {
            return String(decoding: cut.dropLast(), as: UTF16.self) + "?"
        }
        return String(decoding: cut, as: UTF16.self)
    }

    /// Kotlin's Char.isWhitespace: Java's isWhitespace or isSpaceChar.
    public static func isWhitespace(_ c: UInt16) -> Bool {
        switch c {
        case 0x09...0x0D, 0x1C...0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: true
        default: false
        }
    }

    /// Kotlin's String.trim(): whitespace off both ends.
    public static func trim(_ s: String) -> String {
        let u = Array(s.utf16)
        var i = 0
        var end = u.count
        while i < end && isWhitespace(u[i]) { i += 1 }
        while end > i && isWhitespace(u[end - 1]) { end -= 1 }
        if i == 0 && end == u.count { return s }
        return String(decoding: u[i..<end], as: UTF16.self)
    }

    /// Kotlin's String.indexOf(other): the UTF-16 offset of the first occurrence, or -1.
    public static func indexOf(_ s: String, _ other: String) -> Int {
        let h = Array(s.utf16)
        let n = Array(other.utf16)
        if n.isEmpty { return 0 }
        guard h.count >= n.count else { return -1 }
        var i = 0
        while i <= h.count - n.count {
            if h[i] == n[0] {
                var k = 1
                while k < n.count && h[i + k] == n[k] { k += 1 }
                if k == n.count { return i }
            }
            i += 1
        }
        return -1
    }

    /// Kotlin's String.contains(other).
    public static func contains(_ s: String, _ other: String) -> Bool { indexOf(s, other) >= 0 }

    /// Kotlin's String.split(char): every piece, empty ones included ("a,,b" gives "a", "", "b"; "" gives "").
    public static func split(_ s: String, _ separator: Character) -> [String] {
        let sep = Array(String(separator).utf16)
        precondition(sep.count == 1, "a one-unit separator")
        let u = Array(s.utf16)
        var out: [String] = []
        var start = 0
        for (i, c) in u.enumerated() where c == sep[0] {
            out.append(String(decoding: u[start..<i], as: UTF16.self))
            start = i + 1
        }
        out.append(String(decoding: u[start...], as: UTF16.self))
        return out
    }

    /// Java's String.equalsIgnoreCase for the ASCII words the engine compares ("true", "false"), with the one
    /// non-ASCII letter that Java's rule also lets through (U+017F, long s, as "s").
    static func equalsIgnoreCase(_ s: String, _ ascii: String) -> Bool {
        let a = Array(s.utf16)
        let b = Array(ascii.utf16)
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            let lx = x >= 0x41 && x <= 0x5A ? x + 32 : x
            let ly = y >= 0x41 && y <= 0x5A ? y + 32 : y
            if lx == ly || (x == 0x17F && ly == 0x73) { continue }
            return false
        }
        return true
    }

    /// Java's String.hashCode: s[0]*31^(n-1) + ... over UTF-16 units, wrapping.
    public static func javaHash(_ s: String) -> Int32 {
        var h: Int32 = 0
        for c in s.utf16 { h = h &* 31 &+ Int32(c) }
        return h
    }
}
