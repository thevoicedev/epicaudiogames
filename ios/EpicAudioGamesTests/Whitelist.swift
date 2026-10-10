// analytics/Whitelist.kt (the tests'): the server's own whitelist, read from web/ as the server reads it.

import Foundation
@testable import EpicAudioGames

/**
 * The server's own whitelist, read from web/ as the server reads it: web/analytics/events.json, and the id pattern in
 * web/analytics/whitelist.js. The tests check what the app sends against this, not against the app's own copy
 * ([Events.allowed]), so the two can't agree on a mistake. The repository is EPIC_REPO_ROOT (the scheme sets it for
 * the tests), else found from this file's place in it (ios/EpicAudioGamesTests/), as AppFlowTests finds it.
 * Android: Whitelist.kt.
 */
struct Whitelist {
    /// "common": each common field's type.
    let common: [String: String]
    /// "events": each event's properties and their types.
    let events: [String: [String: String]]
    /// whitelist.js's `const ID = /…/;`.
    let idPattern: String

    static func load() throws -> Whitelist {
        let file = try JSONValue.parse(Data(contentsOf: repo.appendingPathComponent("web/analytics/events.json")))
        guard case .object(let root) = file, case .object(let common)? = root["common"],
              case .object(let events)? = root["events"] else { throw Trouble("events.json isn't the whitelist") }
        let js = try String(contentsOf: repo.appendingPathComponent("web/analytics/whitelist.js"), encoding: .utf8)
        let lines = js.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.first(where: { $0.hasPrefix("const ID = /") && $0.hasSuffix("/;") }) else {
            throw Trouble("no ID pattern in whitelist.js")
        }
        return Whitelist(
            common: try types(common),
            events: try events.mapValues { props in
                guard case .object(let props) = props else { throw Trouble("an event that isn't an object") }
                return try types(props)
            },
            idPattern: String(line.dropFirst("const ID = /".count).dropLast("/;".count)))
    }

    /// The repository this test runs from.
    static var repo: URL {
        if let root = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func types(_ object: [String: JSONValue]) throws -> [String: String] {
        try object.mapValues { type in
            guard case .string(let type) = type else { throw Trouble("a type that isn't a string") }
            return type
        }
    }

    /**
     * Why the server would turn away this event (one element of a batch, as sent), or nil if it would take it:
     * whitelist.js's checkEvent, by the file's types.
     */
    func problem(_ event: JSONValue) -> String? {
        guard case .object(let fields) = event else { return "not an object" }
        guard case .string(let name)? = fields["name"] else { return "no name" }
        guard let allowed = events[name] else { return "unknown event \(name)" }
        for (key, value) in fields where key != "name" && key != "props" {
            guard let type = common[key] else { return "unknown field \(key)" }
            if !fits(type, value) { return "\(key) has the wrong type: \(value)" }
        }
        for key in ["install_id", "session_id", "seq"] where fields[key] == nil { return "no \(key)" }
        guard let props = fields["props"] else { return nil }
        guard case .object(let details) = props else { return "props is not an object" }
        for (key, value) in details {
            guard let type = allowed[key] else { return "\(name) has no property \(key)" }
            if !fits(type, value) { return "\(name).\(key) has the wrong type: \(value)" }
        }
        return nil
    }

    /// Whether a JSON value is of a whitelist type, as whitelist.js's compile() checks it (a null is never one).
    func fits(_ type: String, _ value: JSONValue) -> Bool {
        switch (type, value) {
        case ("bool", .bool): return true
        case ("int", .int(let n)): return n >= 0 && n <= 1_000_000_000
        case ("id", .string(let s)): return Self.matches(idPattern, s)
        case ("uuid", .string(let s)):
            return Self.matches("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", s)
        case ("iso8601", .string(let s)):
            return Self.matches(#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$"#, s)
        case ("string", .string(let s)):
            return s.utf16.count <= 64 && !s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        case (_, .string(let s)) where type.hasPrefix("enum:"):
            return type.dropFirst("enum:".count).split(separator: ",").contains { $0 == s }
        default:
            return false
        }
    }

    /// A batch as sent (a JSON array of events), each checked; the events, if the server would take all of them.
    func batch(_ body: Data) throws -> [[String: JSONValue]] {
        guard body.count <= 64 * 1024 else { throw Trouble("a batch of \(body.count) bytes") }
        guard case .array(let events) = try JSONValue.parse(body), (1...100).contains(events.count) else {
            throw Trouble("not a batch of 1 to 100 events")
        }
        return try events.map { event in
            if let problem = problem(event) { throw Trouble("the server would refuse \(event): \(problem)") }
            guard case .object(let fields) = event else { throw Trouble("not an object") }
            return fields
        }
    }

    /// Whether [text] matches [pattern] whole (JavaScript's and Foundation's regular expressions agree on these).
    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range).map { $0.range == range } ?? false
    }
}

/// A JSON value as the server's JSON.parse has it: a whole number apart from a fraction, true and false apart from
/// either (JSONDecoder keeps them apart on every platform; JSONSerialization's NSNumber doesn't).
enum JSONValue: Decodable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let flag = try? value.decode(Bool.self) {
            self = .bool(flag)
        } else if let n = try? value.decode(Int64.self) {
            self = .int(n)
        } else if let n = try? value.decode(Double.self) {
            self = .number(n)
        } else if let s = try? value.decode(String.self) {
            self = .string(s)
        } else if let a = try? value.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// A field of an object; nil for none, or for anything else.
    subscript(_ key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    /// A string's, number's or flag's text, as the server would store it.
    var text: String? {
        switch self {
        case .string(let s): s
        case .int(let n): String(n)
        case .bool(let b): b ? "true" : "false"
        default: nil
        }
    }

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let b): b ? "true" : "false"
        case .int(let n): String(n)
        case .number(let n): String(n)
        case .string(let s): Events.quoted(s)
        case .array(let a): "[" + a.map(\.description).joined(separator: ",") + "]"
        case .object(let o): "{" + o.keys.sorted().map { Events.quoted($0) + ":" + o[$0]!.description }
            .joined(separator: ",") + "}"
        }
    }
}

/// What a test found wrong with a file or a request.
struct Trouble: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}
