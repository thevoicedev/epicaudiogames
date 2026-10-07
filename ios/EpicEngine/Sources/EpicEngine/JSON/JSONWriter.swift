// Writes JSON compactly: kotlinx's JsonElement.toString() (GameMap.kt's error messages) and org.json's toString().

/**
 * Compact JSON, keys in order, literals as written. [Escaping.kotlinx] escapes as kotlinx's printQuoted does (`\"`,
 * `\\`, `\t`, `\b`, `\n`, `\r`, `\f`, and `\u00xx` below U+0020); [Escaping.orgJSON] as Android's org.json does
 * (the same, plus `\/`, ` ` and ` `).
 */
public enum JSONWriter {
    public enum Escaping: Sendable {
        case kotlinx
        case orgJSON
    }

    public static func write(_ json: JSON, escaping: Escaping = .kotlinx) -> String {
        var out = ""
        write(json, escaping, into: &out)
        return out
    }

    /// What's left to write: a value, or text between values.
    private enum Work {
        case value(JSON)
        case text(String)
    }

    /// Writes without recursion, so JSON nested as deep as kotlinx reads it can be described.
    private static func write(_ json: JSON, _ escaping: Escaping, into out: inout String) {
        var work: [Work] = [.value(json)]
        while let w = work.popLast() {
            switch w {
            case .text(let t):
                out.append(t)
            case .value(.object(let o)):
                out.append("{")
                work.append(.text("}"))
                for n in stride(from: o.count - 1, through: 0, by: -1) {
                    let (k, v) = o.entry(at: n)
                    work.append(.value(v))
                    work.append(.text((n > 0 ? "," : "") + quote(k, escaping: escaping) + ":"))
                }
            case .value(.array(let a)):
                out.append("[")
                work.append(.text("]"))
                for n in stride(from: a.count - 1, through: 0, by: -1) {
                    work.append(.value(a[n]))
                    if n > 0 { work.append(.text(",")) }
                }
            case .value(.string(let s)):
                quote(s, escaping, into: &out)
            case .value(.literal(let s)):
                out.append(s)
            case .value(.null):
                out.append("null")
            }
        }
    }

    /// A quoted, escaped string.
    public static func quote(_ s: String, escaping: Escaping = .kotlinx) -> String {
        var out = ""
        quote(s, escaping, into: &out)
        return out
    }

    private static func quote(_ s: String, _ escaping: Escaping, into out: inout String) {
        out.append("\"")
        for c in s.unicodeScalars {
            switch c {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\u{0C}": out.append("\\f")
            case "/" where escaping == .orgJSON: out.append("\\/")
            case "\u{2028}" where escaping == .orgJSON, "\u{2029}" where escaping == .orgJSON, "\u{00}"..."\u{1F}":
                out.append(hexEscape(c.value))
            default: out.unicodeScalars.append(c)
            }
        }
        out.append("\"")
    }

    private static func hexEscape(_ v: UInt32) -> String {
        let hex = String(v, radix: 16)
        return "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }
}
