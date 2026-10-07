// Store.kt's purchase flow against StoreKit itself: its local test session (Config/EpicAudioGames.storekit).

import EpicAppCore
import StoreKit
import StoreKitTest
import XCTest
@testable import EpicAudioGames

/**
 * StoreKitClient with StoreKit's test session: the catalog's three products load with their prices, a purchase
 * installs its pack and is finished, and a refund takes the pack away. StoreKit's test service only answers a session
 * Xcode set up; where it doesn't (SKInternalErrorDomain 3 from a command-line run), this is skipped.
 */
@MainActor
final class StoreKitTests: XCTestCase {
    func testAPurchaseThroughStoreKit() async throws {
        let config = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/EpicAudioGames.storekit")
        let session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        // Without the test service the session's settings don't take (disableDialogs reads back false), and StoreKit
        // asks the sandbox App Store instead, which has the products now: their prices load, and a purchase waits for
        // ever for a confirmation sheet that a unit test can't show.
        try XCTSkipIf(!session.disableDialogs, "StoreKit's test service isn't available to this run")
        session.clearTransactions()
        defer { session.clearTransactions() }
        let client = StoreKitClient()
        let prices = try await client.prices(["frootopia_stories", "alien_customs_levels", "the_werewolf_stories"])
        try XCTSkipIf(prices.isEmpty, "StoreKit's test service isn't available to this run")
        XCTAssertEqual(prices.count, 3)

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("StoreKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let zip = scratch.appendingPathComponent("pack.zip")
        try StoreTests.writeZip(zip)
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber
        let pack = PackInfo(id: "frootopia-stories", game: "frootopia", title: "Stories 2 to 5", description: "",
                            product: "frootopia_stories", version: 1, size: size?.int64Value ?? 0,
                            sha256: try FileHash.sha256(zip))
        let packs = PackStore(root: scratch.appendingPathComponent("packs"))
        let server = FakeFetcher { _ in
            let copy = scratch.appendingPathComponent("\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: zip, to: copy)
            return copy
        }
        let store = Store(
            games: [GameInfo(id: "frootopia", title: "F", blurb: "", free: "", packs: [pack])], packs: packs,
            packsURL: "https://packs.example.com", appStore: client, fetcher: server)
        defer { store.stop() }
        store.start()
        for _ in 0..<100 where store.prices["frootopia_stories"] == nil { try await Task.sleep(for: .milliseconds(50)) }
        await store.buy(pack)
        XCTAssertTrue(packs.isInstalled(pack))
        let unfinished = await client.unfinished().filter { $0.product == "frootopia_stories" }
        XCTAssertTrue(unfinished.isEmpty, "the transaction wasn't finished")

        let bought = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == "frootopia_stories" })
        try session.refundTransaction(identifier: bought.identifier)
        for _ in 0..<100 where packs.isInstalled(pack) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(packs.isInstalled(pack), "a refund leaves the pack")
    }
}
