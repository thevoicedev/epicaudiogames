// GameMap.kt: a game map, as described in docs/MAP_FORMAT.md, read from its JSON with its packs merged in.

import Foundation

/// A game map. Variables hold Boolean, Double or String values.
public final class GameMap: Sendable {
    public let id: String
    public let title: String
    public let start: String
    public let vars: VarStore
    /// The variables that keep their values when the game starts again, in the map's order.
    public let keep: [String]
    /// "repeat" at a question plays the node's say again (true) or its reprompt (false).
    public let repeatSays: Bool
    public let who: LinkedMap<String>
    public let words: WordLists
    /// Symbol tables for seq answers, in the map's order: symbol to the words that mean it.
    public let symbols: LinkedMap<LinkedMap<[String]>>
    public let nodes: LinkedMap<Node>

    public init(
        id: String, title: String, start: String, vars: VarStore, keep: [String], repeatSays: Bool,
        who: LinkedMap<String>, words: WordLists, symbols: LinkedMap<LinkedMap<[String]>>, nodes: LinkedMap<Node>
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.vars = vars
        self.keep = keep
        self.repeatSays = repeatSays
        self.who = who
        self.words = words
        self.symbols = symbols
        self.nodes = nodes
    }

    public func node(_ id: String) throws -> Node {
        guard let n = nodes[id] else { throw MapError("\(id): no such node") }
        return n
    }

    public static func load(_ file: URL, packs: [URL] = []) throws -> GameMap {
        try parse(data: try Data(contentsOf: file), packs: packs.map { try Data(contentsOf: $0) })
    }

    /**
     * A map, with the packs the player has (their pack.json) merged in, in order: each pack's nodes are added or
     * replace the map's nodes of the same id, and its vars, keep, who and symbols are added (see Packs in
     * docs/MAP_FORMAT.md).
     */
    public static func parse(_ text: String, packs: [String] = []) throws -> GameMap {
        try build(([text] + packs).map { file in { try readObject(JSONParser.parse(file)) } })
    }

    public static func parse(data: Data, packs: [Data] = []) throws -> GameMap {
        try build(([data] + packs).map { file in { try readObject(JSONParser.parse(file)) } })
    }

    /**
     * The map (the first file) with its packs merged in, read. The JSON is freed a level at a time ([JSON.release])
     * whatever happens, since a map can carry JSON nested deeper than Swift's own freeing could take (kotlinx reads
     * any depth). Each file is read here, so this holds the only copy of what it frees.
     */
    private static func build(_ files: [() throws -> JSONObject]) throws -> GameMap {
        var root = try files[0]()
        let packs = files.dropFirst()
        do {
            for read in packs {
                var pack = try read()
                var merged: JSONObject
                do {
                    merged = try merge(root, pack)
                } catch {
                    JSON.release(&pack)
                    throw error
                }
                JSON.release(&pack)
                swap(&root, &merged)
                JSON.release(&merged)
            }
            let gameMap = try MapParser(root: root).map()
            JSON.release(&root)
            return gameMap
        } catch {
            JSON.release(&root)
            throw error
        }
    }

    /// The parsed text as an object; bad JSON fails as kotlinx's JsonDecodingException does (kind other).
    private static func readObject(_ parse: @autoclosure () throws -> JSON) throws -> JSONObject {
        var json: JSON
        do {
            json = try parse()
        } catch let e as JSONParseError {
            throw MapError.other("bad JSON: \(e)")
        }
        if case .object(let o) = json { return o }
        let notAnObject = MapError.other("Element class \(json.kotlinxClass) is not a JsonObject")
        JSON.release(&json)
        throw notAnObject
    }

    static func merge(_ map: JSONObject, _ pack: JSONObject) throws -> JSONObject {
        let game = try map["id"].map { try $0.primitiveContent() }
        let packGame = try pack["game"].map { try $0.primitiveContent() }
        if let packGame, game == nil || !Kt.utf16Equal(packGame, game!) {
            throw MapError("pack \(pack["id"]?.kotlinxDescription ?? "null") is for \(packGame), not \(game ?? "null")")
        }
        func obj(_ o: JSONObject, _ key: String) -> JSONObject { o[key]?.objectValue ?? JSONObject() }
        var out = map
        for key in ["nodes", "vars", "who", "symbols"] where pack.contains(key) {
            out[key] = .object(obj(map, key).merging(obj(pack, key)))
        }
        if pack.contains("keep") {
            // distinct(): kotlinx's equality, so "é" and "e" + U+0301 are both kept.
            var keep: [JSON] = []
            for k in (map["keep"]?.arrayValue ?? []) + (pack["keep"]?.arrayValue ?? []) where !keep.contains(k) {
                keep.append(k)
            }
            out["keep"] = .array(keep)
        }
        return out
    }

    static let defaultWords: [String: [String]] = [
        "yes": ["yes", "yeah", "yep", "sure", "ok", "okay"],
        "no": ["no", "nope", "nah"],
        "repeat": ["repeat", "say that again", "say it again"],
    ]
}
