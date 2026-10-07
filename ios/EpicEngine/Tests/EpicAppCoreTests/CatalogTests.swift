// Catalog.swift: games/catalog.json read as Library.kt reads it with org.json.

import Foundation
import Testing

@testable import EpicAppCore

struct CatalogTests {
    @Test func readsTheCatalogInItsOrder() throws {
        let games = try AppTestRepo.catalog()
        #expect(games.map(\.id) == [
            "frootopia", "noodle-rush", "signal-decoders", "pirate-quest", "leaning-tower-of-pizza", "alien-customs",
            "the-werewolf", "nuclear-war",
        ])
        let frootopia = games[0]
        #expect(frootopia.title == "The Kingdom of Frootopia")
        #expect(frootopia.free == "Story 1 free")
        let pack = try #require(frootopia.packs.first)
        #expect(pack.id == "frootopia-stories")
        #expect(pack.game == "frootopia")
        #expect(pack.title == "Stories 2 to 5")
        #expect(pack.product == "frootopia_stories")
        #expect(pack.playProduct == "frootopia_stories")
        #expect(pack.version == 1)
        #expect(pack.size == 14_558_828)
        #expect(pack.sha256 == "4e25148c79b8d900bc42baa9ab9477ae0c7ea363f01a18ab114dab548b8d06db")
        #expect(games[1].packs.isEmpty)
        #expect(games.flatMap(\.packs).map(\.id)
            == ["frootopia-stories", "alien-customs-levels", "the-werewolf-stories"])
    }

    /// optString gives "" for a missing key (and "null" for null); a missing "packs" is none; sizes are Longs.
    @Test func defaults() throws {
        let games = try Catalog.parse(
            #"""
            {"games": [
              {"id": "g", "title": "G"},
              {"id": "h", "title": "H", "blurb": null, "free": 3, "packs": [
                {"id": "p", "title": "P", "product": "play_p", "version": 2, "size": 5000000000, "sha256": "ab"}
              ]},
              {"id": "i", "title": "I", "packs": {"not": "a list"}}
            ]}
            """#
        )
        #expect(games.map(\.id) == ["g", "h", "i"])
        #expect(games[0].blurb == "")
        #expect(games[0].free == "")
        #expect(games[0].packs.isEmpty)
        #expect(games[1].blurb == "null")
        #expect(games[1].free == "3")
        #expect(games[2].packs.isEmpty)
        let p = try #require(games[1].packs.first)
        #expect(p.description == "")
        #expect(p.game == "h")
        #expect(p.version == 2)
        #expect(p.size == 5_000_000_000)
        #expect(p.megabytes == 5000)
    }

    /// The App Store's product id, when the catalog has one ("appstore"); else Play's ("product").
    @Test func appStoreProductFallsBackToPlays() throws {
        let games = try Catalog.parse(
            #"""
            {"games": [{"id": "g", "title": "G", "packs": [
              {"id": "a", "title": "A", "product": "play_a", "appstore": "ios_a", "version": 1, "size": 1,
               "sha256": ""},
              {"id": "b", "title": "B", "product": "play_b", "appstore": "", "version": 1, "size": 1, "sha256": ""},
              {"id": "c", "title": "C", "product": "play_c", "version": 1, "size": 1, "sha256": ""}
            ]}]}
            """#
        )
        let packs = games[0].packs
        #expect(packs.map(\.product) == ["ios_a", "play_b", "play_c"])
        #expect(packs.map(\.playProduct) == ["play_a", "play_b", "play_c"])
    }

    /// getInt and getLong coerce as Android's org.json does: numeric text, truncated Doubles.
    @Test func numbersAsOrgJSONTakesThem() throws {
        let games = try Catalog.parse(
            #"""
            {"games": [{"id": 7, "title": "T", "packs": [
              {"id": "a", "title": "A", "product": "p", "version": "3", "size": 1e3, "sha256": ""},
              {"id": "b", "title": "B", "product": "p", "version": 2.9, "size": "12.7", "sha256": ""}
            ]}]}
            """#
        )
        #expect(games[0].id == "7")
        #expect(games[0].packs.map(\.version) == [3, 2])
        #expect(games[0].packs.map(\.size) == [1000, 12])
    }

    @Test func missingFieldsFail() throws {
        #expect(throws: CatalogError.self) { try Catalog.parse(#"{"list": []}"#) }
        #expect(throws: CatalogError.self) { try Catalog.parse(#"{"games": [{"title": "no id"}]}"#) }
        func pack(_ fields: String) -> String { #"{"games": [{"id": "g", "title": "G", "packs": [{\#(fields)}]}]}"# }
        let named = #""id": "a", "title": "A", "product": "p", "#
        #expect(throws: CatalogError.self) { try Catalog.parse(pack(named + #""version": 1, "size": 1"#)) }
        #expect(throws: CatalogError.self) {
            try Catalog.parse(pack(named + #""version": true, "size": 1, "sha256": """#))
        }
        #expect(try Catalog.parse(pack(named + #""version": 1, "size": 1, "sha256": """#)).count == 1)
    }

    /// StoreSheet.kt's "(size + 500000) / 1000000 MB", and Store.kt's zip and its address (`trimEnd('/')`).
    @Test func downloadSizesAndNames() throws {
        func pack(_ size: Int64) -> PackInfo {
            PackInfo(id: "frootopia-stories", game: "frootopia", title: "", description: "", product: "p", version: 1,
                     size: size, sha256: "")
        }
        #expect(pack(499_999).megabytes == 0)
        #expect(pack(500_000).megabytes == 1)
        #expect(pack(1_499_999).megabytes == 1)
        #expect(pack(14_558_828).megabytes == 15)
        #expect(pack(133_444_602).megabytes == 133)
        let p = pack(1)
        #expect(p.zipName == "frootopia-stories-1.zip")
        #expect(p.downloadURL("https://packs.example.com/v1//")?.absoluteString
            == "https://packs.example.com/v1/frootopia-stories-1.zip")
        #expect(p.downloadURL("http://localhost:8765")?.absoluteString
            == "http://localhost:8765/frootopia-stories-1.zip")
        #expect(p.downloadURL("") == nil)
        #expect(p.downloadURL("///") == nil)
    }
}
