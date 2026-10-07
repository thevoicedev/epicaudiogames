// GoldenTest.kt's Goldens, read back: the variants, the fixture files and their header (README sections 1, 2.2, 4).

import CryptoKit
import EpicEngine
import Foundation

/// A map as the app loads it: a free map, or a game with all its packs merged in (README section 1).
public struct Variant: Sendable {
    public let name: String
    public let dir: URL
    /// The map file, then its packs in file-name order.
    public let files: [URL]

    public var packs: [URL] { Array(files.dropFirst()) }
}

/// The header's hashes of the game data and the Kotlin engine (README section 4).
public struct Stamp: Sendable, Equatable {
    public let gamesSha256: String
    public let engineSha256: String
}

/**
 * The repo's games, the variants made from them and the fixtures in fixtures/engine, for tests and `eag --dump`.
 * Maps are loaded once, when first asked for; it's safe to share between threads.
 */
public final class Goldens: Sendable {
    public let root: URL
    public let games: URL
    public let fixtures: URL
    public let engineSource: URL
    /// Every variant, in the fixtures' order: folders by name, each free variant followed by its +packs variant.
    public let variants: [Variant]
    private let maps: [String: Once<GameMap>]
    private let stampOnce = Once<Stamp>()
    private let audioOnce = Once<NuclearAudio>()

    /// The repo found as [Repo.root] finds it.
    public static let shared: Result<Goldens, any Error> = Result { try Goldens(root: Repo.root()) }

    public init(root: URL) throws {
        let games = root.appendingPathComponent("games")
        self.root = root
        self.games = games
        fixtures = root.appendingPathComponent("fixtures/engine")
        engineSource = root.appendingPathComponent("android/engine/src/main/kotlin")
        var variants: [Variant] = []
        let dirs = Repo.list(games).filter { Repo.isFile(games.appendingPathComponent("\($0)/map.json")) }
            .sorted { Kt.utf16Less($0, $1) }
        guard !dirs.isEmpty else { throw ConformanceError("no maps in \(games.path)") }
        for name in dirs {
            let dir = games.appendingPathComponent(name)
            let map = dir.appendingPathComponent("map.json")
            let packDir = dir.appendingPathComponent("packs")
            let packs = Repo.list(packDir)
                .filter { Goldens.extension($0) == "json" && Repo.isFile(packDir.appendingPathComponent($0)) }
                .sorted { Kt.utf16Less($0, $1) }.map { packDir.appendingPathComponent($0) }
            variants.append(Variant(name: name, dir: dir, files: [map]))
            if !packs.isEmpty { variants.append(Variant(name: "\(name)+packs", dir: dir, files: [map] + packs)) }
        }
        self.variants = variants
        maps = Dictionary(uniqueKeysWithValues: variants.map { ($0.name, Once<GameMap>()) })
    }

    /// Kotlin's File.extension: the text after the last dot.
    private static func `extension`(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return String(name[name.index(after: dot)...])
    }

    public func variant(_ name: String) throws -> Variant {
        guard let v = variants.first(where: { Kt.utf16Equal($0.name, name) }) else {
            throw ConformanceError("no variant \(name) in \(games.path)")
        }
        return v
    }

    /// The variant's map, as GameMap.load(map, packs) loads it.
    public func map(_ name: String) throws -> GameMap {
        let v = try variant(name)
        return try maps[v.name]!.get { try GameMap.load(v.files[0], packs: v.packs) }
    }

    /// A file's path relative to games/, with "/" separators.
    public func relative(_ url: URL) -> String {
        let base = games.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    /**
     * The chapter ends (in map order) whose next chapter a pack defines: where odd walks of a +packs variant start
     * (README section 8.1). Empty for a free variant.
     */
    public func entries(_ name: String) throws -> [String] {
        let v = try variant(name)
        if v.packs.isEmpty { return [] }
        let map = try map(name)
        var fromPacks = Set<String>()
        for p in v.packs { fromPacks.formUnion(try Goldens.packNodes(p)) }
        return map.nodes.compactMap { id, n in
            guard let e = n.end, e.kind == "chapter", let next = e.next, fromPacks.contains(next),
                  map.nodes.contains(next) else { return nil }
            return id
        }
    }

    /// The ids of the nodes a pack file defines.
    public static func packNodes(_ file: URL) throws -> [String] {
        try JSONParser.parse(Data(contentsOf: file))["nodes"]?.objectValue?.keys ?? []
    }

    /// Nuclear War's real audio table, games/nuclear-war/clips.json (never the placeholder, which changes the draws).
    public func nuclearAudio() throws -> NuclearAudio {
        try audioOnce.get {
            let clips = games.appendingPathComponent("\(NuclearWar.id)/clips.json")
            guard Repo.isFile(clips) else {
                throw ConformanceError("no \(clips.path): the Nuclear War fixtures need the real audio table")
            }
            return try NuclearAudio.load(clips)
        }
    }

    // ----- The header -----

    /// The hashes of the games and the engine, as the header must have them.
    public func stamp() throws -> Stamp {
        try stampOnce.get {
            Stamp(gamesSha256: try Goldens.treeSha256(games, ".json"),
                  engineSha256: try Goldens.treeSha256(engineSource, ".kt"))
        }
    }

    /**
     * SHA-256 of the files under [dir] ending in [ext] (names starting with "." skipped): for each, by path, its
     * path, 0, its size in decimal, 0, its bytes.
     */
    static func treeSha256(_ dir: URL, _ ext: String) throws -> String {
        var files: [(path: String, url: URL)] = []
        func walk(_ d: URL, _ prefix: String) {
            for name in Repo.list(d) where !name.hasPrefix(".") {
                let f = d.appendingPathComponent(name)
                if Repo.isDirectory(f) {
                    walk(f, "\(prefix)\(name)/")
                } else if Repo.isFile(f) && name.hasSuffix(ext) {
                    files.append(("\(prefix)\(name)", f))
                }
            }
        }
        walk(dir, "")
        guard !files.isEmpty else { throw ConformanceError("no \(ext) files in \(dir.path)") }
        var sha = SHA256()
        for (path, url) in files.sorted(by: { Kt.utf16Less($0.path, $1.path) }) {
            let bytes = try Data(contentsOf: url)
            sha.update(data: Data(path.utf8))
            sha.update(data: Data([0]))
            sha.update(data: Data(String(bytes.count).utf8))
            sha.update(data: Data([0]))
            sha.update(data: bytes)
        }
        return sha.finalize().map { b in
            let h = String(b, radix: 16)
            return h.count == 1 ? "0" + h : h
        }.joined()
    }

    /// Fails unless the header is format 1 and made from these games and this engine.
    public func checkHeader(_ header: JSONObject, _ path: String) throws {
        guard Array(header.keys.prefix(3)) == ["format", "games_sha256", "engine_sha256"] else {
            throw ConformanceError("\(path): the header isn't format, games_sha256, engine_sha256")
        }
        guard header["format"] == .literal("1") else {
            let format = header["format"]?.kotlinxDescription ?? "missing"
            throw ConformanceError("\(path): format \(format), not 1 (fixtures/engine/README.md)")
        }
        let s = try stamp()
        guard header["games_sha256"]?.content == s.gamesSha256,
              header["engine_sha256"]?.content == s.engineSha256 else {
            throw ConformanceError("""
                fixtures stale: cd android && ./gradlew :engine:goldens
                  (\(path) was made from other games/*.json or another Kotlin engine: \
                games_sha256 \(header["games_sha256"]?.content ?? "-") here \(s.gamesSha256), \
                engine_sha256 \(header["engine_sha256"]?.content ?? "-") here \(s.engineSha256))
                """)
        }
    }

    // ----- The files -----

    private func text(_ path: String) throws -> String {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(path))
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { throw ConformanceError("\(path) has a byte-order mark") }
        guard data.last == 0x0A else { throw ConformanceError("\(path) doesn't end with a newline") }
        guard let s = String(data: data, encoding: .utf8) else { throw ConformanceError("\(path) isn't UTF-8") }
        return s
    }

    /// A .json fixture (path relative to fixtures/engine), its header checked.
    public func readJSON(_ path: String) throws -> JSONObject {
        let o = try JSONParser.parse(text(path)).fxObject()
        try checkHeader(o, path)
        return o
    }

    /// A .jsonl fixture: its header (checked) and the lines after it, each without its "\n".
    public func readLines(_ path: String) throws -> (header: JSONObject, lines: [String]) {
        // Split on the newline byte: Swift's Characters would keep "\r\n" together.
        var lines = try text(path).utf8.split(separator: 0x0A, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        lines.removeLast()
        guard let first = lines.first else { throw ConformanceError("\(path) is empty") }
        let header = try JSONParser.parse(first).fxObject()
        try checkHeader(header, path)
        if lines.contains(where: { $0.hasSuffix("\r") }) { throw ConformanceError("\(path) has \\r\\n line ends") }
        return (header, Array(lines.dropFirst()))
    }
}

/// A value made once, when first asked for, by whichever thread asks first.
final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, any Error>?

    func get(_ make: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if value == nil { value = Result { try make() } }
        return try value!.get()
    }
}

// ----- Reading fixture values -----

extension LinkedMap where V == JSON {
    /// A field of a fixture object that must be there.
    public func fx(_ key: String) throws -> JSON {
        guard let v = self[key] else { throw ConformanceError("no \"\(key)\" field in the fixture") }
        return v
    }
}

extension JSON {
    public func fxObject() throws -> JSONObject {
        guard let o = objectValue else { throw ConformanceError("not an object: \(short)") }
        return o
    }

    public func fxArray() throws -> [JSON] {
        guard let a = arrayValue else { throw ConformanceError("not a list: \(short)") }
        return a
    }

    public func fxString() throws -> String {
        guard case .string(let s) = self else { throw ConformanceError("not a string: \(short)") }
        return s
    }

    public func fxInt() throws -> Int {
        guard case .literal(let text) = self, let i = Int(text) else {
            throw ConformanceError("not an integer: \(short)")
        }
        return i
    }

    public func fxBool() throws -> Bool {
        switch self {
        case .literal("true"): return true
        case .literal("false"): return false
        default: throw ConformanceError("not a boolean: \(short)")
        }
    }

    /// A double (README section 2.1): an integer, or "x" and the 16 hex digits of its bits.
    public func fxDouble() throws -> Double {
        switch self {
        case .literal(let text):
            guard let i = Int64(text) else { break }
            return Double(i)
        case .string(let s):
            guard s.hasPrefix("x"), s.utf8.count == 17, let bits = UInt64(s.dropFirst(), radix: 16) else { break }
            return Double(bitPattern: bits)
        default: break
        }
        throw ConformanceError("not a double: \(short)")
    }

    public func fxOptString() throws -> String? { self == .null ? nil : try fxString() }
    public func fxOptInt() throws -> Int? { self == .null ? nil : try fxInt() }
    public func fxOptBool() throws -> Bool? { self == .null ? nil : try fxBool() }
    public func fxOptDouble() throws -> Double? { self == .null ? nil : try fxDouble() }

    /// A variable's value (README section 5): ["n", d], ["b", b], ["s", s], or null for a missing one.
    public func fxValue() throws -> EpicEngine.Value? {
        if self == .null { return nil }
        let a = try fxArray()
        guard a.count == 2 else { throw ConformanceError("not a value: \(short)") }
        switch try a[0].fxString() {
        case "n": return .number(try a[1].fxDouble())
        case "b": return .bool(try a[1].fxBool())
        case "s": return .string(try a[1].fxString())
        default: throw ConformanceError("not a value: \(short)")
        }
    }

    /// A variable list, in order.
    public func fxVars() throws -> VarStore {
        var out = VarStore()
        for pair in try fxArray() {
            let p = try pair.fxArray()
            guard p.count == 2, let v = try p[1].fxValue() else {
                throw ConformanceError("not a variable: \(pair.short)")
            }
            out[try p[0].fxString()] = v
        }
        return out
    }

    /// A field of an object that must be there.
    public func fx(_ key: String) throws -> JSON {
        guard let v = try fxObject()[key] else { throw ConformanceError("no \"\(key)\" in \(short)") }
        return v
    }

    /// The text, cut short for messages.
    public var short: String { Kt.take(kotlinxDescription, 200) }
}
