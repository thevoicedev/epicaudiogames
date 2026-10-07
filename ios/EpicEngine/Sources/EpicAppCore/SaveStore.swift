// Library.kt's Saves (lines 41-75): each game's place, kept between plays, as the JSON SavedCodec reads and writes.

import Foundation

/**
 * Each game's place: the node it waits at, its variables, and whether it has ended. Kept between plays. Map games and
 * Nuclear War (whose state and settings are text variables) go through the same store, as on Android.
 */
public protocol SaveStore: AnyObject, Sendable {
    /// The game's save; nil when there is none or it can't be read (the game then starts afresh).
    func load(_ game: String) -> Saved?

    /**
     * Keeps the game's place. A save that can't be written as JSON (a NaN or infinite number) clears the game's save
     * instead, as Android ends up doing: org.json's toString gives null for it, and putting null removes the key.
     */
    func store(_ game: String, _ saved: Saved)

    func clear(_ game: String)
}

extension SaveStore {
    /// A game that was left part-way: not at an end, nor left with a plain quit (both save as ended).
    public func inProgress(_ game: String) -> Bool { load(game).map { !$0.ended } ?? false }
}

/// The saves on the phone: Application Support/Saves/<game>.json, each written whole (atomically).
public final class FileSaveStore: SaveStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's own: Application Support/Saves.
    public static func standard() throws -> FileSaveStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FileSaveStore(directory: support.appendingPathComponent("Saves", isDirectory: true))
    }

    public func file(_ game: String) -> URL { directory.appendingPathComponent("\(game).json", isDirectory: false) }

    public func load(_ game: String) -> Saved? {
        guard let data = try? Data(contentsOf: file(game)) else { return nil }
        return SavedCodec.decode(data)
    }

    public func store(_ game: String, _ saved: Saved) {
        let data: Data
        do {
            data = try SavedCodec.encodeData(saved)
        } catch {
            clear(game)
            return
        }
        // Like SharedPreferences.apply, a write that fails is let go: the game carries on, from its last save.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(game), options: .atomic)
    }

    public func clear(_ game: String) {
        try? FileManager.default.removeItem(at: file(game))
    }
}

/// Saves kept in memory (tests and previews), written and read through SavedCodec as the file store's are.
public final class MemorySaveStore: SaveStore, @unchecked Sendable {
    private let lock = NSLock()
    private var saves: [String: String]

    /// [json]: each game's save as written ({"node", "vars", "ended"}).
    public init(_ json: [String: String] = [:]) {
        saves = json
    }

    /// The JSON kept for a game.
    public func json(_ game: String) -> String? { lock.withLock { saves[game] } }

    public func load(_ game: String) -> Saved? {
        guard let text = json(game) else { return nil }
        return SavedCodec.decode(text)
    }

    public func store(_ game: String, _ saved: Saved) {
        let text = try? SavedCodec.encode(saved)
        lock.withLock { saves[game] = text }
    }

    public func clear(_ game: String) {
        lock.withLock { _ = saves.removeValue(forKey: game) }
    }
}
