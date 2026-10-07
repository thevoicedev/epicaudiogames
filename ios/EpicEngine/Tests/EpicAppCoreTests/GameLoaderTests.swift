// GameLoader.swift: MainActivity.kt's loading of a game, with its installed packs, keeping the last two.

import Foundation
import Testing

@testable import EpicAppCore

struct GameLoaderTests {
    private func map(_ game: LoadedGame) throws -> GameMap {
        guard case .map(let map) = game else { throw LoaderTestError("not a map") }
        return map
    }

    @Test func loadsMapsAndNuclearWar() async throws {
        let loader = GameLoader(games: try AppTestRepo.games())
        let noodle = try map(await loader.load(AppTestRepo.game("noodle-rush"), installed: []))
        #expect(noodle.id == "noodle-rush")
        #expect(LoadedGame.map(noodle).makePlay() is Session)

        let war = try await loader.load(AppTestRepo.game(NuclearWar.id), installed: [])
        guard case .nuclearWar(let audio) = war else {
            Issue.record("Nuclear War isn't loaded from its clips")
            return
        }
        #expect(audio.who["HOST"] != nil)
        let play = war.makePlay()
        #expect(play is NuclearWar)
        #expect(try play.start().ask != nil)
    }

    /// Two games are kept, the one used last kept longest; a game loaded again is the same map.
    @Test func keepsTheLastTwo() async throws {
        let loader = GameLoader(games: try AppTestRepo.games())
        let a = try AppTestRepo.game("noodle-rush")
        let b = try AppTestRepo.game("signal-decoders")
        let c = try AppTestRepo.game("pirate-quest")
        let a1 = try map(await loader.load(a, installed: []))
        let b1 = try map(await loader.load(b, installed: []))
        #expect(try map(await loader.load(a, installed: [])) === a1)
        #expect(await loader.keys == ["signal-decoders", "noodle-rush"])
        _ = try await loader.load(c, installed: [])
        #expect(await loader.keys == ["noodle-rush", "pirate-quest"])
        #expect(try map(await loader.load(a, installed: [])) === a1)
        #expect(try map(await loader.load(b, installed: [])) !== b1)
        #expect(await loader.keys == ["noodle-rush", "signal-decoders"])
    }

    /// The packs installed are merged into the map, and named in the key, so installing one loads the map again.
    @Test func mergesInstalledPacks() async throws {
        let games = try AppTestRepo.games()
        let scratch = try Scratch()
        let frootopia = try AppTestRepo.game("frootopia")
        let pack = try #require(frootopia.packs.first)
        let folder = scratch.folder("packs/\(pack.id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: games.appendingPathComponent("frootopia/packs/\(pack.id).json"),
            to: folder.appendingPathComponent("pack.json"))
        let installed = [InstalledPack(pack: pack, folder: folder)]
        #expect(GameLoader.key(frootopia, installed) == "frootopia+frootopia-stories@1")
        #expect(GameLoader.key(frootopia, []) == "frootopia")

        let loader = GameLoader(games: games)
        let free = try map(await loader.load(frootopia, installed: []))
        let full = try map(await loader.load(frootopia, installed: installed))
        #expect(free !== full)
        #expect(!free.nodes.contains("fr2-0"))
        #expect(full.nodes.contains("fr2-0"))
        #expect(free.nodes["fr-55"]?.end?.locked == "frootopia-stories")
        #expect(full.nodes["fr-55"]?.end?.locked == nil)
        #expect(await loader.keys == ["frootopia", "frootopia+frootopia-stories@1"])
    }

    @Test func aGameThatIsntThereFails() async throws {
        let loader = GameLoader(games: try AppTestRepo.games())
        let missing = GameInfo(id: "no-such-game", title: "", blurb: "", free: "", packs: [])
        await #expect(throws: (any Error).self) { try await loader.load(missing, installed: []) }
        #expect(await loader.keys.isEmpty)
    }
}

private struct LoaderTestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
}
