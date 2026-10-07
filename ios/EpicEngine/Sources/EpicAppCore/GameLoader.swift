// MainActivity.kt's AppModel.open (lines 67-92): a game's map with its installed packs merged in, or Nuclear War's.

import Foundation

/// A pack installed on this phone: its catalog entry and the folder it's unpacked in (its pack.json and its audio).
public struct InstalledPack: Equatable, Sendable {
    public let pack: PackInfo
    public let folder: URL

    public init(pack: PackInfo, folder: URL) {
        self.pack = pack
        self.folder = folder
    }
}

/// What a game is played from: its map (with its packs merged in), or, for Nuclear War, which is written in code,
/// its audio (clips.json).
public enum LoadedGame: Sendable {
    case map(GameMap)
    case nuclearWar(NuclearAudio)

    /// A new play of it: a map's Session, or a game of Nuclear War. Each draws from a XorWowRandom seeded from the
    /// system, as the Kotlin engine's Random.Default does.
    public func makePlay() -> any Play {
        switch self {
        case .map(let map): Session(map)
        case .nuclearWar(let audio): NuclearWar(audio: audio)
        }
    }
}

/**
 * Loads games away from the main thread (a big map takes a moment) and keeps the last two loaded, each with the packs
 * that were installed when it was loaded: the key names them, so installing a pack loads the map again.
 */
public actor GameLoader {
    /// The app's Games folder: <id>/map.json for each map, nuclear-war/clips.json.
    public let games: URL
    public let capacity: Int
    /// The games loaded, the most recently used last.
    private var loaded: [(key: String, game: LoadedGame)] = []

    public init(games: URL, capacity: Int = 2) {
        self.games = games
        self.capacity = max(capacity, 1)
    }

    /// The game's id and its installed packs' ids and versions: "frootopia+frootopia-stories@1".
    public static func key(_ info: GameInfo, _ installed: [InstalledPack]) -> String {
        info.id + installed.map { "+\($0.pack.id)@\($0.pack.version)" }.joined()
    }

    /// The game, with [installed] (its packs on this phone, in the catalog's order) merged into its map.
    public func load(_ info: GameInfo, installed: [InstalledPack]) throws -> LoadedGame {
        let key = Self.key(info, installed)
        if let i = loaded.firstIndex(where: { $0.key == key }) {
            let hit = loaded.remove(at: i)
            loaded.append(hit)
            return hit.game
        }
        let game: LoadedGame
        if info.id == NuclearWar.id {
            game = .nuclearWar(try NuclearAudio.load(file("\(info.id)/clips.json")))
        } else {
            game = .map(try GameMap.parse(
                data: Data(contentsOf: file("\(info.id)/map.json")),
                packs: installed.map { try Data(contentsOf: $0.folder.appendingPathComponent("pack.json")) }
            ))
        }
        loaded.append((key, game))
        if loaded.count > capacity { loaded.removeFirst(loaded.count - capacity) }
        return game
    }

    /// The keys of the games kept, the most recently used last.
    public var keys: [String] { loaded.map(\.key) }

    private func file(_ path: String) -> URL { games.appendingPathComponent(path, isDirectory: false) }
}
