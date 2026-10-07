// Library.kt (lines 8-38): the games on the list (games/catalog.json) and the packs that can be bought for them.

import Foundation

/// A game on the list (Games/catalog.json, from games/catalog.json), with the packs that can be bought for it.
public struct GameInfo: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let blurb: String
    public let free: String
    public let packs: [PackInfo]

    public init(id: String, title: String, blurb: String, free: String, packs: [PackInfo]) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.free = free
        self.packs = packs
    }
}

/// A pack of more stories or levels: an in-app product, downloaded as <id>-<version>.zip from the pack server.
public struct PackInfo: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let game: String
    public let title: String
    public let description: String
    /// The App Store product: the catalog's "appstore" id when it has one, else its "product" (the Play id).
    public let product: String
    /// The Google Play product, the catalog's "product".
    public let playProduct: String
    public let version: Int
    public let size: Int64
    public let sha256: String

    public init(
        id: String, game: String, title: String, description: String, product: String, playProduct: String? = nil,
        version: Int, size: Int64, sha256: String
    ) {
        self.id = id
        self.game = game
        self.title = title
        self.description = description
        self.product = product
        self.playProduct = playProduct ?? product
        self.version = version
        self.size = size
        self.sha256 = sha256
    }

    /// The size in whole megabytes, rounded half up, as StoreSheet.kt shows it ("15 MB download").
    public var megabytes: Int64 { (size + 500_000) / 1_000_000 }

    /// The room a download needs: its zip, and the pack unpacked from it (Packs.kt's hasRoom: 2.2 times its size).
    public var roomNeeded: Int64 { size * 22 / 10 }

    /// The pack at another version (the one on the phone: Packs.kt's installed copies it so).
    public func at(version: Int) -> PackInfo {
        PackInfo(id: id, game: game, title: title, description: description, product: product,
                 playProduct: playProduct, version: version, size: size, sha256: sha256)
    }

    /// The zip on the pack server (Store.kt): "<id>-<version>.zip".
    public var zipName: String { "\(id)-\(version).zip" }

    /// The zip's address on the pack server at [base], with any slashes at its end taken off first (Store.kt's
    /// `trimEnd('/')`). Nil when there's no server.
    public func downloadURL(_ base: String) -> URL? {
        var trimmed = Substring(base)
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        if trimmed.isEmpty { return nil }
        return URL(string: "\(trimmed)/\(zipName)")
    }
}

/// A catalog that can't be read (Android's org.json throws a JSONException).
public struct CatalogError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/// The game list, read as Library.kt's Catalog reads it with Android's org.json.
public enum Catalog {
    public static func load(_ file: URL) throws -> [GameInfo] { try parse(data: Data(contentsOf: file)) }

    public static func parse(_ text: String) throws -> [GameInfo] { try read(JSONParser.parse(text)) }

    public static func parse(data: Data) throws -> [GameInfo] { try read(JSONParser.parse(data)) }

    private static func read(_ json: JSON) throws -> [GameInfo] {
        guard let root = json.objectValue else { throw CatalogError("catalog.json isn't a JSON object") }
        guard case .array(let games)? = root["games"] else { throw CatalogError("No value for games") }
        return try games.map { g in
            guard let g = g.objectValue else { throw CatalogError("a game isn't a JSON object") }
            let id = try OrgJSON.getString(g, "id")
            var packs: [PackInfo] = []
            if case .array(let list)? = g["packs"] {
                packs = try list.map { p in
                    guard let p = p.objectValue else { throw CatalogError("a pack of \(id) isn't a JSON object") }
                    let play = try OrgJSON.getString(p, "product")
                    let appStore = OrgJSON.optString(p, "appstore")
                    return PackInfo(
                        id: try OrgJSON.getString(p, "id"), game: id, title: try OrgJSON.getString(p, "title"),
                        description: OrgJSON.optString(p, "description"),
                        product: appStore.isEmpty ? play : appStore, playProduct: play,
                        version: Int(try OrgJSON.getInt(p, "version")), size: try OrgJSON.getLong(p, "size"),
                        sha256: try OrgJSON.getString(p, "sha256")
                    )
                }
            }
            return GameInfo(
                id: id, title: try OrgJSON.getString(g, "title"), blurb: OrgJSON.optString(g, "blurb"),
                free: OrgJSON.optString(g, "free"), packs: packs
            )
        }
    }
}

/// Android's org.json getters, on the values JSONTokener reads: text as it is, numbers coerced.
enum OrgJSON {
    /// getString: text as it is; a number, true, false or null as org.json prints the value it read.
    static func getString(_ o: JSONObject, _ key: String) throws -> String {
        guard let v = o[key] else { throw CatalogError("No value for \(key)") }
        return text(v)
    }

    /// optString: as getString, or "" when the key isn't there.
    static func optString(_ o: JSONObject, _ key: String) -> String { o[key].map(text) ?? "" }

    /// getInt: an Integer as it is, a Long cut to 32 bits, a Double or numeric text truncated (and saturated).
    static func getInt(_ o: JSONObject, _ key: String) throws -> Int32 {
        guard let v = o[key] else { throw CatalogError("No value for \(key)") }
        switch number(v) {
        case .long(let l)?: return Int32(truncatingIfNeeded: l)
        case .double(let d)?: return int32(d)
        case nil: throw CatalogError("Value \(text(v)) at \(key) cannot be converted to int")
        }
    }

    /// getLong: an Integer or Long as it is, a Double or numeric text truncated (and saturated).
    static func getLong(_ o: JSONObject, _ key: String) throws -> Int64 {
        guard let v = o[key] else { throw CatalogError("No value for \(key)") }
        switch number(v) {
        case .long(let l)?: return l
        case .double(let d)?: return Kt.saturatingLong(d)
        case nil: throw CatalogError("Value \(text(v)) at \(key) cannot be converted to long")
        }
    }

    private enum Number {
        case long(Int64)
        case double(Double)
    }

    /// JSONTokener's number (an Integer or Long without a ".", else a Double), or text read with parseDouble.
    private static func number(_ v: JSON) -> Number? {
        switch v {
        case .literal(let raw):
            if raw == "true" || raw == "false" { return nil }
            if !raw.contains("."), let l = Int64(raw) { return .long(l) }
            return Kt.toDoubleOrNull(raw).map(Number.double)
        case .string(let s):
            return Kt.toDoubleOrNull(s).map(Number.double)
        case .null, .object, .array:
            return nil
        }
    }

    private static func text(_ v: JSON) -> String {
        switch v {
        case .string(let s): return s
        case .literal(let raw):
            if raw == "true" || raw == "false" { return raw }
            if !raw.contains("."), let l = Int64(raw) { return String(l) }
            return Kt.doubleString(Kt.toDoubleOrNull(raw) ?? 0)
        case .null: return "null"
        case .object, .array: return JSONWriter.write(v, escaping: .orgJSON)
        }
    }

    /// Java's (int) cast of a double: NaN is 0, the rest truncated and saturated.
    private static func int32(_ d: Double) -> Int32 {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int32.max }
        if d <= -2147483648.0 { return Int32.min }
        return Int32(d)
    }
}
