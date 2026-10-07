// SaveStore.swift: Library.kt's Saves, in Application Support/Saves/<id>.json.

import Foundation
import Testing

@testable import EpicAppCore

struct SaveStoreTests {
    @Test func fileStoreKeepsEachGamesPlace() throws {
        let scratch = try Scratch()
        let store = FileSaveStore(directory: scratch.folder("Saves"))
        #expect(store.load("noodle-rush") == nil)
        #expect(!store.inProgress("noodle-rush"))

        let saved = Saved(node: "q3", vars: ["n": 2.0, "mode": "x", "ok": true, "half": 0.5], ended: false)
        store.store("noodle-rush", saved)
        #expect(store.load("noodle-rush") == saved)
        #expect(store.inProgress("noodle-rush"))
        #expect(try String(contentsOf: store.file("noodle-rush"), encoding: .utf8)
            == #"{"node":"q3","vars":{"n":2,"mode":"x","ok":true,"half":0.5},"ended":false}"#)
        // Written whole: nothing else is left in the folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == ["noodle-rush.json"])

        store.store("noodle-rush", Saved(node: "end", vars: [:], ended: true))
        #expect(store.load("noodle-rush")?.ended == true)
        #expect(!store.inProgress("noodle-rush"))
        #expect(store.load("pirate-quest") == nil)

        store.clear("noodle-rush")
        #expect(store.load("noodle-rush") == nil)
        #expect(!FileManager.default.fileExists(atPath: store.file("noodle-rush").path))
        store.clear("noodle-rush")
    }

    @Test func standardStoreIsInApplicationSupport() throws {
        let store = try FileSaveStore.standard()
        #expect(store.directory.lastPathComponent == "Saves")
        #expect(store.directory.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    /// org.json can't write NaN: Android's toString gives null, and putting null removes the save.
    @Test func aSaveThatCantBeWrittenClearsIt() throws {
        let scratch = try Scratch()
        let stores: [any SaveStore] = [FileSaveStore(directory: scratch.folder("Saves")), MemorySaveStore()]
        for store in stores {
            store.store("g", Saved(node: "a", vars: ["n": 1.0], ended: false))
            #expect(store.load("g") != nil)
            store.store("g", Saved(node: "a", vars: ["n": .number(.nan)], ended: false))
            #expect(store.load("g") == nil)
            store.store("g", Saved(node: "a", vars: ["n": .number(.infinity)], ended: false))
            #expect(store.load("g") == nil)
        }
    }

    /// A save that can't be read is none (the game starts afresh); a missing "ended" is false.
    @Test func unreadableSavesAreNone() throws {
        let scratch = try Scratch()
        let store = FileSaveStore(directory: scratch.folder("Saves"))
        try scratch.write("Saves/a.json", "{not json")
        try scratch.write("Saves/b.json", #"{"node":"q","vars":{"level":3}}"#)
        try scratch.write("Saves/c.json", #"{"node":"q","vars":{"level":3,"name":"Zed"},"ended":true}"#)
        try scratch.write("Saves/d.json", #"{"vars":{}}"#)
        #expect(store.load("a") == nil)
        #expect(store.load("b") == Saved(node: "q", vars: ["level": 3.0], ended: false))
        #expect(store.load("c") == Saved(node: "q", vars: ["level": 3.0, "name": "Zed"], ended: true))
        #expect(store.load("d") == nil)
        #expect(store.inProgress("b"))
        #expect(!store.inProgress("c"))
    }

    @Test func memoryStoreWritesWhatTheFileStoreWrites() throws {
        let store = MemorySaveStore()
        let saved = Saved(node: "q3", vars: ["n": 2.0, "z": -0.0], ended: false)
        store.store("g", saved)
        #expect(store.json("g") == #"{"node":"q3","vars":{"n":2,"z":-0},"ended":false}"#)
        #expect(store.load("g")?.node == "q3")
        store.clear("g")
        #expect(store.json("g") == nil)
    }

    /// Nuclear War's save (its state and settings as text variables) goes through the same store, and opens again.
    @Test func nuclearWarSavesInTheSameStore() throws {
        let scratch = try Scratch()
        let store = FileSaveStore(directory: scratch.folder("Saves"))
        let game = NuclearWar(audio: .placeholder(), random: XorWowRandom(seed: 7))
        let first = try game.start()
        #expect(first.ask != nil)
        store.store(NuclearWar.id, game.save())
        let saved = try #require(store.load(NuclearWar.id))
        #expect(saved == game.save())
        #expect(store.inProgress(NuclearWar.id))

        let again = NuclearWar(audio: .placeholder(), random: XorWowRandom(seed: 7))
        let opening = try OpenPolicy.android.open(again, saved: saved) { NuclearWar(audio: .placeholder()) }
        #expect(opening.welcomeBack)
        #expect(!opening.clearSave)
        #expect(opening.game === again)
        #expect(opening.turn.node == first.node)
    }
}
