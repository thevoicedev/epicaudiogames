// Library.kt's Saves (lines 42-75): a game's place as the JSON the Android app keeps, {"node", "vars", "ended"}.

import Foundation

/**
 * A [Saved] to and from the JSON the Android app writes with org.json: `{"node":"q3","vars":{"n":2,"mode":"x"},
 * "ended":false}`. Numbers are written as org.json writes them (whole numbers as integers, -0.0 as -0) and read as
 * Doubles; a missing "ended" is false. A save that can't be read gives nil, so the game starts afresh.
 */
public enum SavedCodec {
    /// A save org.json can't write: a NaN or infinite number. The caller clears the save, as Android ends up doing.
    public struct EncodeError: Error, Equatable, Sendable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    public static func encode(_ saved: Saved) throws -> String {
        var vars = JSONObject()
        for (k, v) in saved.vars {
            switch v {
            case .bool(let b): vars[k] = .bool(b)
            case .string(let s): vars[k] = .string(s)
            case .number(let d): vars[k] = .literal(try number(d))
            }
        }
        let o: JSONObject = ["node": .string(saved.node), "vars": .object(vars), "ended": .bool(saved.ended)]
        return JSONWriter.write(.object(o), escaping: .orgJSON)
    }

    public static func encodeData(_ saved: Saved) throws -> Data { Data(try encode(saved).utf8) }

    /// org.json's numberToString.
    static func number(_ d: Double) throws -> String {
        guard d.isFinite else { throw EncodeError(message: "Forbidden numeric value: \(Kt.doubleString(d))") }
        if d == 0 && d.sign == .minus { return "-0" }
        let l = Kt.saturatingLong(d)
        return d == Double(l) ? String(l) : Kt.doubleString(d)
    }

    public static func decode(_ data: Data) -> Saved? {
        guard var json = try? JSONParser.parse(data) else { return nil }
        let saved = decode(json)
        // A level at a time, so a save nested thousands deep is freed without running out of stack.
        JSON.release(&json)
        return saved
    }

    public static func decode(_ text: String) -> Saved? {
        guard var json = try? JSONParser.parse(text) else { return nil }
        let saved = decode(json)
        JSON.release(&json)
        return saved
    }

    private static func decode(_ json: JSON) -> Saved? {
        guard let o = json.objectValue, let nodeValue = o["node"], let varsObject = o["vars"]?.objectValue else {
            return nil
        }
        // getString: text as it is, anything else as org.json prints it.
        let node: String
        switch nodeValue {
        case .string(let s): node = s
        case .literal(let raw): node = raw == "true" || raw == "false" ? raw : numberText(raw)
        case .null: node = "null"
        case .object, .array: node = JSONWriter.write(nodeValue, escaping: .orgJSON)
        }
        var vars = VarStore()
        for (k, v) in varsObject {
            switch v {
            case .string(let s): vars[k] = .string(s)
            case .literal("true"): vars[k] = .bool(true)
            case .literal("false"): vars[k] = .bool(false)
            case .literal(let raw): vars[k] = .number(readNumber(raw))
            // org.json would keep JSONObject.NULL or a nested object as a variable; no game writes one.
            case .null, .object, .array: return nil
            }
        }
        // optBoolean: true, false, or "true"/"false" in any case; anything else is false.
        var ended = false
        switch o["ended"] {
        case .literal("true")?: ended = true
        case .string(let s)?: ended = Kt.equalsIgnoreCase(s, "true")
        default: break
        }
        return Saved(node: node, vars: vars, ended: ended)
    }

    /// JSONTokener's number: an integer when there's no ".", so "-0" reads as 0.0; else a Double.
    static func readNumber(_ raw: String) -> Double {
        if !raw.contains("."), let l = Int64(raw) { return Double(l) }
        return Kt.toDoubleOrNull(raw) ?? 0
    }

    /// A number as org.json's getString prints the value JSONTokener read: Integer or Long digits, else a Double.
    private static func numberText(_ raw: String) -> String {
        if !raw.contains("."), let l = Int64(raw) { return String(l) }
        return Kt.doubleString(Kt.toDoubleOrNull(raw) ?? 0)
    }
}
