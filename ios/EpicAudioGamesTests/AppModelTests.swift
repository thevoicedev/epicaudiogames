// MainActivity.kt's AppModel: the list's CONTINUE read again as it shows, packInstalled reopening a game (L14), the
// store sheet and the background.

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/// The app's model with the app's own games, saves in memory, packs in a scratch folder, and silent audio.
@MainActor
@Suite(.serialized)
struct AppModelTests {
    let saves = MemorySaveStore()
    let scratch: URL
    let packs: PackStore

    init() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests-\(UUID().uuidString)")
        packs = PackStore(root: scratch.appendingPathComponent("packs"))
    }

    private func model() -> AppModel {
        AppModel(saves: saves, packs: packs, hearing: AppModel.Hearing.none, silent: true, startStore: false)
    }

    private func info(_ model: AppModel, _ id: String) throws -> GameInfo {
        try #require(model.games.first { $0.id == id })
    }

    /// The placeholder pack folder (ios/scripts/placeholder_content.py), installed as the store would.
    private func installFrootopiaPack() throws -> Bool {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/placeholder-packs/frootopia-stories")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("pack.json").path) else { return false }
        try FileManager.default.createDirectory(at: packs.root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: packs.root.appendingPathComponent("frootopia-stories"))
        return true
    }

    private func until(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Android reads each game's save as the list is drawn: a game that reached its end elsewhere (here: the save
    /// written behind the list's back) shows PLAY as soon as the list shows again, even under the loading overlay.
    @Test func theListReadsWhatCanBeCarriedOnEachTimeItShows() async throws {
        saves.store("noodle-rush", Saved(node: "nr-start", vars: [:], ended: false))
        let model = model()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(model.continuing == ["noodle-rush"])
        saves.store("noodle-rush", Saved(node: "nr-start", vars: [:], ended: true))
        model.open(try info(model, "pirate-quest"))
        #expect(model.opening != nil)
        #expect(model.continuing.isEmpty)
        #expect(await until { model.game != nil })
        model.home()
        #expect(model.game == nil)
    }

    /// With no recogniser, the mic doesn't work and nothing is asked; whether it's allowed is as the phone says
    /// (GameScreen.kt sets micAllowed from the permission either way).
    @Test func withNoRecogniserTheMicIsOff() async throws {
        let model = model()
        defer { try? FileManager.default.removeItem(at: scratch) }
        model.open(try info(model, "noodle-rush"))
        #expect(await until { model.game != nil })
        let game = try #require(model.game)
        #expect(!game.micWorks)
        #expect(game.micAllowed == MicPermission.granted)
        model.home()
    }

    /// L14: Frootopia waiting at the chapter end its pack unlocks opens there again once the pack is in, NEXT CHAPTER
    /// showing: bought before that end (while it played) or at it (once the store sheet closes). From the list too.
    /// fixed: only the pack's own game, at an end the pack unlocks, is opened again; other games and ends aren't.
    @Test func aGameWaitingAtTheEndItsPackUnlocksOpensThereWithIt() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        saves.store("frootopia", Saved(node: "fr-53", vars: [:], ended: false))
        let model = model()
        let frootopia = try info(model, "frootopia")
        let pack = try #require(frootopia.packs.first)

        // Bought while it played: nothing happens until it reaches the end the pack unlocks.
        model.open(frootopia)
        #expect(await until { model.game?.ask != nil })
        let playing = try #require(model.game)
        guard try installFrootopiaPack() else {         // no placeholder packs on this machine
            model.home()
            return
        }
        #expect(packs.isInstalled(pack))
        model.packInstalled()
        #expect(model.game === playing)
        try await reachTheLockedEnd(playing)
        #expect(await until { model.game != nil && model.game !== playing && model.game?.end != nil })
        let reopened = try #require(model.game)
        #expect(reopened.end?.kind == "chapter")
        #expect(reopened.canGoOn, "no NEXT CHAPTER")
        // It has the pack now: nothing more to do.
        model.packInstalled()
        #expect(model.game === reopened)

        // Bought at that end, from its store sheet: opened again once the sheet closes.
        model.home()
        try FileManager.default.removeItem(at: packs.root.appendingPathComponent(pack.id))
        saves.store("frootopia", Saved(node: "fr-53", vars: [:], ended: false))
        model.open(frootopia)
        #expect(await until { model.game?.ask != nil })
        let again = try #require(model.game)
        try await reachTheLockedEnd(again)
        #expect(again.end?.locked == pack.id)
        model.showStore(frootopia)
        #expect(!again.paused, "paused at its end")
        _ = try installFrootopiaPack()
        model.packInstalled()
        #expect(model.game === again, "opened again under the store sheet")
        model.showStore(nil)
        #expect(await until { model.game != nil && model.game !== again && model.game?.end != nil })
        #expect(model.game?.canGoOn == true)

        // From the list: at that end, NEXT CHAPTER showing.
        model.home()
        model.open(frootopia)
        #expect(await until { model.game?.end != nil })
        #expect(model.game?.canGoOn == true)
        model.home()
    }

    /// The store sheet pauses a game playing (it waits for a tap once the sheet closes); a game at its end isn't.
    @Test func theStoreSheetPausesTheGame() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        let frootopia = try info(model, "frootopia")
        model.open(frootopia)
        #expect(await until { model.game != nil })
        let game = try #require(model.game)
        model.showStore(frootopia)
        #expect(game.paused)
        #expect(!game.speaking)
        model.showStore(nil)
        #expect(model.storeFor == nil)
        #expect(model.game === game)
        model.home()
    }

    /// While a game loads, no store sheet opens over it.
    @Test func noStoreSheetWhileAGameLoads() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.open(try info(model, "frootopia"))
        #expect(model.opening != nil)
        model.showStore(try info(model, "the-werewolf"))
        #expect(model.storeFor == nil)
        #expect(await until { model.game != nil })
        model.home()
    }

    /// A game that finishes loading while the app is in the background waits for it to come back.
    @Test func aGameLoadedInTheBackgroundStartsWhenTheAppIsBack() async throws {
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = model()
        model.onScreen(false)
        model.open(try info(model, "noodle-rush"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.game == nil)
        #expect(model.opening != nil)
        model.onScreen(true)
        #expect(await until { model.game?.speaking == true })
        model.home()
    }

    /// Answers fr-53 "no": Quick Ending (fr-55), the chapter end Frootopia's pack unlocks.
    private func reachTheLockedEnd(_ game: GameController) async throws {
        game.answer("no")
        game.skip()
        #expect(await until { game.end != nil })
        #expect(game.end?.kind == "chapter")
    }
}
