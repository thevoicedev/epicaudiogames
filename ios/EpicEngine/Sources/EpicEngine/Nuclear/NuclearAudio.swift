// nuclear/NuclearAudio.kt (lines 1-99): Nuclear War's audio, games/nuclear-war/clips.json.

import Foundation

/**
 * Nuclear War's audio, games/nuclear-war/clips.json (made by tools/games/nuclearwar.py): Don's lines by their text;
 * the skill's recorded clips by their path on the Mini Games CDN ("nuclear-war/UK/Hello.mp3"); the skill's audio
 * table, which says which clips each of its getters chooses from; and the rules, mixed ahead as one clip.
 *
 * Immutable, so one can be shared by every game. The lines asked for without a clip are noted by each game
 * ([NuclearWar.missing]), not here as in Kotlin (docs/IOS_PARITY.md, L9).
 */
public final class NuclearAudio: Sendable {
    public let who: LinkedMap<String>
    private let voice: LinkedMap<Clip>
    private let clips: LinkedMap<Clip>
    private let table: JSONObject
    private let mixes: LinkedMap<Clip>

    public init(
        who: LinkedMap<String>, voice: LinkedMap<Clip>, clips: LinkedMap<Clip>, table: JSONObject,
        mixes: LinkedMap<Clip>
    ) {
        self.who = who
        self.voice = voice
        self.clips = clips
        self.table = table
        self.mixes = mixes
    }

    /// Don saying a line, or a placeholder when it has no clip (a game notes those: tests fail on them).
    public func don(_ text: String) -> Clip { voice[text] ?? NuclearAudio.placeholder(text) }

    public func has(_ text: String) -> Bool { voice.contains(text) }

    /// A recorded clip; nil when the skill's table has no such file (it would 404 on Alexa: nothing plays).
    public func clip(_ path: String?) -> Clip? {
        guard let path else { return nil }
        if let c = clips[path] { return c }
        return clips.isEmpty ? Clip(path: "audio/\(path)", dur: 1.0, lines: []) : nil
    }

    public func mix(_ name: String) -> Clip? { mixes[name] }

    /// A field of the table for a country ("Representative") or of its sounds ("sfx").
    public func path(_ section: String, _ field: String) -> String? { table[section]?.objectValue?[field]?.content }

    /// A field that is a list of paths ("GeneralChat"). An entry that isn't text fails, as `jsonPrimitive` does.
    public func paths(_ section: String, _ field: String) throws -> [String] {
        guard let list = table[section]?.objectValue?[field]?.arrayValue else { return [] }
        return try list.map { try $0.primitiveContent() }
    }

    /// A field that maps names to paths ("Attack": city to clip).
    public func keyed(_ section: String, _ field: String, _ key: String) -> String? {
        table[section]?.objectValue?[field]?.objectValue?[key]?.content
    }

    /// A motivator comment: one path, or a list to choose from.
    public func options(_ section: String, _ field: String, _ key: String) throws -> [String] {
        guard let e = table[section]?.objectValue?[field]?.objectValue?[key] else { return [] }
        switch e {
        case .string, .literal, .null: return [e.content ?? ""]
        case .array(let list): return try list.map { try $0.primitiveContent() }
        case .object: return []
        }
    }

    public static func load(_ file: URL) throws -> NuclearAudio { try parse(data: Data(contentsOf: file)) }

    public static func parse(_ text: String) throws -> NuclearAudio { try parse(json: JSONParser.parse(text)) }

    public static func parse(data: Data) throws -> NuclearAudio { try parse(json: JSONParser.parse(data)) }

    private static func parse(json: JSON) throws -> NuclearAudio {
        let root = try json.jsonObject()
        if try root["format"].map({ try $0.primitiveContent() }) != "1" {
            throw MapError("clips.json: only format 1 is supported")
        }
        func plays(_ key: String) throws -> LinkedMap<Clip> {
            guard let o = root[key]?.objectValue else { return LinkedMap() }
            return try o.mapValues { try play($0.jsonObject()) }
        }
        return NuclearAudio(
            who: try root["who"]?.objectValue?.mapValues { try $0.primitiveContent() } ?? LinkedMap(),
            voice: try plays("voice"),
            clips: try plays("clips"),
            table: root["table"]?.objectValue ?? JSONObject(),
            mixes: try plays("mixes")
        )
    }

    /// Before the audio is made (tests, the typing player): every line and clip a placeholder.
    public static func placeholder() -> NuclearAudio {
        NuclearAudio(who: who, voice: LinkedMap(), clips: LinkedMap(), table: JSONObject(), mixes: LinkedMap())
    }

    private static func placeholder(_ text: String) -> Clip {
        Clip(path: "don/missing", dur: 1.0, lines: [Line(at: 0.0, len: 1.0, who: "HOST", text: text)])
    }

    public static let who: LinkedMap<String> = {
        var m: LinkedMap<String> = ["HOST": ""]
        for land in World.lands { m[land.who] = land.leader }
        return m
    }()

    /// kotlinx's getValue(key): a missing key fails (NoSuchElementException).
    private static func value(_ o: JSONObject, _ key: String) throws -> JSON {
        guard let v = o[key] else { throw PlayError("Key \(key) is missing in the map.") }
        return v
    }

    private static func play(_ o: JSONObject) throws -> Clip {
        let path = try value(o, "play").primitiveContent()
        let dur = try primitive(value(o, "dur")).doubleOrNull ?? 0.0
        let lines = try o["lines"]?.arrayValue?.map { l -> Line in
            let lo = try l.jsonObject()
            // A JSON null's content is "null", which isn't a number: 0.0, as `doubleOrNull ?: 0.0` gives.
            let at = try primitive(value(lo, "at")).doubleOrNull ?? 0.0
            let len = lo["len"].flatMap { $0.isPrimitive ? $0.doubleOrNull : nil } ?? 0.0
            let who = try value(lo, "who").primitiveContent()
            let text = try value(lo, "text").primitiveContent()
            let words = try lo["w"]?.arrayValue?.map { w -> Double in
                let s = try w.primitiveContent()
                guard let d = Kt.toDoubleOrNull(s) else { throw PlayError("For input string: \"\(s)\"") }
                return d
            }
            return Line(at: at, len: len, who: who, text: text, words: words)
        }
        return Clip(
            path: path,
            dur: dur,
            lines: lines ?? [],
            sfx: o["sfx"].flatMap { $0.isPrimitive ? $0.booleanOrNull : nil } == true
        )
    }

    /// `.jsonPrimitive`: an object or array fails.
    private static func primitive(_ e: JSON) throws -> JSON {
        _ = try e.primitiveContent()
        return e
    }
}
