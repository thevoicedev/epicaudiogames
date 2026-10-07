// AudioPlayer.kt's uri (lines 158-173): where a clip's audio is, in the game's installed packs or in its own content.

import Foundation

/**
 * Finds a game's clips: <path>.m4a, .mp3 or .opus (the first there), in its installed packs first (in the catalog's
 * order: Packs.installed), then in the app's own Content/<id>/. Names match exactly, case and all, as on the phone,
 * whose file system tells case apart (the simulator's and the Mac's don't): every folder on the way is looked up in
 * a listing of its parent, read once. One is made for each game opened, as Android's AudioPlayer is.
 */
public final class ContentResolver: @unchecked Sendable {
    public static let extensions = [".m4a", ".mp3", ".opus"]

    public let gameId: String
    /// The app's Content folder, which holds a folder per game.
    public let content: URL
    /// The game's installed packs' folders, in the catalog's order.
    public let packs: [URL]
    public let extensions: [String]

    private let lock = NSLock()
    /// Each folder's names, by its path: each name under itself, and under any canonically equal names.
    private var listings: [String: [String: [String]]] = [:]

    public init(gameId: String, content: URL, packs: [URL], extensions: [String] = ContentResolver.extensions) {
        self.gameId = gameId
        self.content = content
        self.packs = packs
        self.extensions = extensions
    }

    /**
     * The file for a clip's path ("voice/intro", without its extension); nil when there's none. Android plays the
     * game's "<path>.m4a" regardless, which fails and holds up the turn; the app plays on without it
     * (docs/IOS_PARITY.md, L5).
     */
    public func url(_ path: String) -> URL? {
        let pieces = Kt.split(path, "/")
        let name = pieces[pieces.count - 1]
        let dirs = pieces.dropLast().filter { !$0.isEmpty && $0 != "." }
        let names = extensions.map { name + $0 }
        for pack in packs {
            for n in names {
                if let f = find(pack, dirs, [n]) { return f }
            }
        }
        return find(content, [gameId] + dirs, names)
    }

    /// A file of the game's own content by its name, as written ("cover.jpg"); nil when there's none.
    public func bundled(_ name: String) -> URL? { find(content, [gameId], [name]) }

    /// The first of [names] in the folder [dirs] under [root], every name matched exactly.
    private func find(_ root: URL, _ dirs: [String], _ names: [String]) -> URL? {
        var dir = root
        for d in dirs {
            guard has(dir, d) else { return nil }
            dir = dir.appendingPathComponent(d, isDirectory: true)
        }
        for n in names where has(dir, n) {
            return dir.appendingPathComponent(n, isDirectory: false)
        }
        return nil
    }

    private func has(_ dir: URL, _ name: String) -> Bool {
        let listing = lock.withLock {
            if let l = listings[dir.path] { return l }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let l = Dictionary(grouping: names, by: { $0 })
            listings[dir.path] = l
            return l
        }
        // Swift's == takes "é" and "e" + U+0301 as the same; the name must be the same text, as Kotlin compares it.
        return listing[name]?.contains { Kt.utf16Equal($0, name) } ?? false
    }
}
