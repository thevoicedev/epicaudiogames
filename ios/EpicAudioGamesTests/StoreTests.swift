// Store.kt's buying, restoring and installing, with a fake App Store and a fake pack server.

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The store's part of Store.kt, with a fake App Store: a purchase is finished at once, then its pack downloaded (from
 * a fake server: a zip written here) and installed; the purchases are read again to get a pack that's missing; a
 * refund takes the pack away, once its game is closed (D11, L13); with no pack server nothing is bought (L6); with
 * no products, GET says the store isn't there; a failed download says so under its pack and is tried again; a full
 * disk says so; Ask to Buy waits; a download the last run left going is taken up; and what happens is usage data.
 * StoreKitTests runs the real StoreKit where its test service is available.
 */
@MainActor
@Suite(.serialized)
struct StoreTests {
    let scratch: URL
    let packs: PackStore
    let zip: URL
    let pack: PackInfo
    let game: GameInfo

    /// What the fake server was asked for, and the packs installed (touched on the main actor only).
    final class Log: @unchecked Sendable {
        var fetched: [URL] = []
        var installed: [String] = []
        var failing = false
        /// The next fetches fail with this, one each, before any [failing].
        var failures: [any Error] = []
    }

    init() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("StoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        packs = PackStore(root: scratch.appendingPathComponent("packs"))
        zip = scratch.appendingPathComponent("pack.zip")
        try StoreTests.writeZip(zip)
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber
        pack = PackInfo(
            id: "frootopia-stories", game: "frootopia", title: "Stories 2 to 5", description: "",
            product: "frootopia_stories", version: 1, size: size?.int64Value ?? 0, sha256: try FileHash.sha256(zip))
        game = GameInfo(id: "frootopia", title: "The Kingdom of Frootopia", blurb: "", free: "", packs: [pack])
    }

    /// The fake pack server: it serves the zip (a copy), unless the log says to fail.
    private func server(_ log: Log) -> FakeFetcher {
        let zip = zip
        let scratch = scratch
        return FakeFetcher { url in
            await MainActor.run { log.fetched.append(url) }
            if let error = await MainActor.run(body: { log.failures.isEmpty ? nil : log.failures.removeFirst() }) {
                throw error
            }
            if await MainActor.run(body: { log.failing }) { throw URLError(.notConnectedToInternet) }
            let copy = scratch.appendingPathComponent("download-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: zip, to: copy)
            return copy
        }
    }

    /// A store with [appStore] and the fake pack server, its fetches and installs logged.
    private func store(
        _ appStore: FakeAppStore, url: String = "https://packs.example.com/", log: Log = Log(),
        fetcher: FakeFetcher? = nil, retries: [Duration] = [.seconds(60)]
    ) -> Store {
        let store = Store(
            games: [game], packs: packs, packsURL: url, appStore: appStore, fetcher: fetcher ?? server(log),
            retryDelays: retries)
        store.onInstalled = { log.installed.append($0.id) }
        return store
    }

    private func cleanUp(_ store: Store) {
        store.stop()
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test func aPurchaseInstallsItsPackThenFinishes() async throws {
        let appStore = FakeAppStore()
        let log = Log()
        let store = store(appStore, log: log)
        defer { cleanUp(store) }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] == "£1.99" })
        #expect(!store.loading)
        await store.buy(pack)
        #expect(packs.isInstalled(pack))
        #expect(log.installed == ["frootopia-stories"])
        #expect(log.fetched.map(\.absoluteString) == ["https://packs.example.com/frootopia-stories-1.zip"])
        #expect(store.installs == 1)
        #expect(store.downloads.isEmpty)
        #expect(store.message == nil)
        #expect(store.failed.isEmpty)
        #expect(store.owned == ["frootopia_stories"])
        #expect(appStore.finished == ["frootopia_stories"], "the transaction wasn't finished")
        // Read again (the sheet opening): it's here, so nothing more is fetched; finished again, harmlessly.
        await store.restore()
        #expect(log.fetched.count == 1)
    }

    /// A pack bought before but not on this phone (another phone, or deleted) comes back when the store is opened;
    /// one bought on another device while the app is open comes as an update.
    @Test func restoringGetsAPackThatsMissing() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        let store = store(appStore, log: log)
        defer { cleanUp(store) }
        await store.restore()
        #expect(packs.isInstalled(pack))
        #expect(log.installed == ["frootopia-stories"])
        try packs.remove(pack)
        store.start()
        appStore.send(StorePurchase(product: "frootopia_stories", revoked: false, finish: {}))
        #expect(await until { packs.isInstalled(pack) })
    }

    /// The purchases left unfinished (the app closed before they were) are taken up at launch.
    @Test func anUnfinishedPurchaseIsTakenUpAtLaunch() async throws {
        let appStore = FakeAppStore()
        appStore.pending = ["frootopia_stories"]
        let store = store(appStore)
        defer { cleanUp(store) }
        store.start()
        #expect(await until { packs.isInstalled(pack) })
        #expect(await until { appStore.finished.contains("frootopia_stories") })
    }

    /// D11: a refund takes the pack away; while its game is open, only once it closes (L13).
    @Test func aRefundTakesThePackAwayOnceItsGameCloses() async throws {
        let appStore = FakeAppStore()
        let store = store(appStore)
        defer { cleanUp(store) }
        var open = true
        store.inUse = { $0 == "frootopia" && open }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] != nil })
        await store.buy(pack)
        #expect(packs.isInstalled(pack))
        let installs = store.installs
        appStore.send(StorePurchase(product: "frootopia_stories", revoked: true, finish: {}))
        try await Task.sleep(for: .milliseconds(300))
        #expect(packs.isInstalled(pack), "removed while its game was open")
        #expect(!store.owned.contains("frootopia_stories"))
        open = false
        store.gameClosed()
        #expect(!packs.isInstalled(pack))
        #expect(store.installs == installs + 1)      // the list and sheet see it go
        // Not open: at once.
        await store.buy(pack)
        #expect(packs.isInstalled(pack))
        appStore.send(StorePurchase(product: "frootopia_stories", revoked: true, finish: {}))
        #expect(await until { !packs.isInstalled(pack) })
    }

    /// L6: with no pack server, GET says so and nothing is bought (Store.kt says so first too).
    @Test func withNoPackServerNothingIsBought() async throws {
        let appStore = FakeAppStore()
        let store = store(appStore, url: "")
        defer { cleanUp(store) }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] != nil })
        await store.buy(pack)
        #expect(store.message == "Packs can't be downloaded in this version of the app yet.")
        #expect(appStore.bought.isEmpty)
        #expect(!packs.isInstalled(pack))
    }

    /// Store.kt's buy with no product details: the message, and the products asked for again.
    @Test func withNoProductsGETSaysTheStoreIsntThere() async throws {
        let appStore = FakeAppStore()
        let store = store(appStore)
        defer { cleanUp(store) }
        await store.buy(pack)           // not started: no products yet
        #expect(store.message == "The store isn't available right now. Check that you're signed in to the App Store.")
        #expect(appStore.bought.isEmpty)
        #expect(store.prices["frootopia_stories"] != nil, "the products weren't loaded again")
        // A purchase that goes wrong.
        appStore.failing = true
        await store.buy(pack)
        #expect(store.message == "The purchase didn't go through. Please try again.")
        #expect(!packs.isInstalled(pack))
    }

    /// Prices missing (the App Store wasn't there at launch) are asked for again when a sheet opens, and on restore.
    @Test func missingPricesAreAskedForAgain() async throws {
        let appStore = FakeAppStore()
        appStore.pricesFail = true
        let store = store(appStore)
        defer { cleanUp(store) }
        store.start()
        // At launch, and again as the purchases are read.
        #expect(await until { appStore.priceAsks >= 2 && !store.loading })
        #expect(store.prices.isEmpty)
        appStore.pricesFail = false
        store.sheet(open: true)
        #expect(await until { store.prices["frootopia_stories"] == "£1.99" })
        #expect(!store.loading)
    }

    /// A download that fails says so under its pack (not in another game's sheet); the purchase is finished all the
    /// same, and opening the store again tries again.
    @Test func aFailedDownloadIsTriedAgainLater() async throws {
        let appStore = FakeAppStore()
        let log = Log()
        log.failing = true
        let store = store(appStore, log: log)
        defer { cleanUp(store) }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] != nil })
        await store.buy(pack)
        #expect(store.failed[pack.id]
            == "Couldn't download Stories 2 to 5. Check your connection, and open the store again to retry.")
        #expect(store.message == nil)
        #expect(!packs.isInstalled(pack))
        #expect(store.owned.contains("frootopia_stories"))     // the sheet shows DOWNLOAD
        // fixed: finished at once (Store.kt acknowledges at once too); the download is tried again later.
        #expect(appStore.finished == ["frootopia_stories"])
        log.failing = false
        await store.restorePurchases()
        #expect(store.message == nil)
        #expect(store.failed.isEmpty)
        #expect(store.note == "Your purchases are restored.")
        #expect(appStore.syncs == 1)
        #expect(packs.isInstalled(pack))
    }

    /// A store sheet opening starts afresh: what it said before (here, another game's trouble) is gone.
    @Test func aSheetOpeningClearsWhatWasSaid() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        log.failing = true
        let store = store(appStore, log: log)
        defer { cleanUp(store) }
        await store.restore()
        #expect(store.failed[pack.id] != nil)
        store.message = "The purchase didn't go through. Please try again."
        log.failing = false
        store.sheet(open: true)
        #expect(store.message == nil)
        #expect(store.failed.isEmpty)
        #expect(await until { packs.isInstalled(pack) })      // and the purchases are read again
        store.message = "Something"
        store.sheet(open: false)
        #expect(store.message == nil)
    }

    /// A download that failed is tried again by itself, a while later.
    @Test func aFailedDownloadIsTriedAgainByItself() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        log.failures = [URLError(.timedOut)]
        let store = store(appStore, log: log, retries: [.milliseconds(100)])
        defer { cleanUp(store) }
        await store.restore()
        #expect(store.failed[pack.id] != nil)
        #expect(await until { packs.isInstalled(pack) })
        #expect(log.fetched.count == 2)
        #expect(store.failed.isEmpty)
    }

    /// A full disk is said as such (not as the connection), and isn't tried again by itself; with too little room, no
    /// download starts.
    @Test func aFullDiskSaysSo() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        log.failures = [CocoaError(.fileWriteOutOfSpace)]
        let store = store(appStore, log: log, retries: [.milliseconds(50)])
        defer { cleanUp(store) }
        await store.restore()
        #expect(store.failed[pack.id] == Store.noRoom(pack))
        #expect(Store.noRoom(pack).hasPrefix("There isn't enough space on your \(Store.device) for Stories 2 to 5."))
        // Named as the device it runs on: an iPad's says so (the tests may run on either).
        #expect(Store.noRoom(pack, on: "iPad").hasPrefix("There isn't enough space on your iPad for Stories 2 to 5."))
        #expect(["iPhone", "iPad", "Mac"].contains(Store.device))
        try await Task.sleep(for: .milliseconds(300))
        #expect(log.fetched.count == 1)
        #expect(!packs.isInstalled(pack))
    }

    /// "Restore purchases" says how it went: nothing to restore, or the App Store not there.
    @Test func restoringSaysHowItWent() async throws {
        let appStore = FakeAppStore()
        let store = store(appStore)
        defer { cleanUp(store) }
        await store.restorePurchases()
        #expect(store.note == "There are no purchases to restore.")
        #expect(store.message == nil)
        appStore.syncFails = true
        await store.restorePurchases()
        #expect(store.note == nil)
        #expect(store.message == "The store isn't available right now. Check that you're signed in to the App Store.")
    }

    /// Ask to Buy: the pack waits (PAYMENT PENDING) until the parent says yes, which comes as an update.
    @Test func askToBuyWaitsForItsYes() async throws {
        let appStore = FakeAppStore()
        appStore.askToBuy = true
        let store = store(appStore)
        defer { cleanUp(store) }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] != nil })
        await store.buy(pack)
        #expect(store.pending == ["frootopia_stories"])
        #expect(!packs.isInstalled(pack))
        appStore.send(StorePurchase(product: "frootopia_stories", revoked: false, finish: {}))
        #expect(await until { packs.isInstalled(pack) })
        #expect(store.pending.isEmpty)
    }

    /**
     * What the shop tells the usage data (Store.kt's onEvent): a purchase started and how it ended (cancelled, waiting
     * for Ask to Buy, then bought), each download (installed, or failed), and Restore purchases with what the account
     * has bought, or that the App Store couldn't be asked; never a price. Every event one the whitelist takes.
     */
    @Test func theShopsEventsAreUsageData() async throws {
        let appStore = FakeAppStore()
        let log = Log()
        let store = store(appStore, log: log)
        defer { cleanUp(store) }
        let events = TrackedEvents()
        store.onEvent = { name, props in events.add(Event(name: name, props: props)) }
        store.start()
        #expect(await until { store.prices["frootopia_stories"] != nil })
        appStore.cancelling = true
        await store.buy(pack)
        #expect(events.take() == [
            Events.purchaseStart("frootopia_stories"), Events.purchaseResult("frootopia_stories", .cancelled),
        ])
        appStore.cancelling = false
        appStore.askToBuy = true
        await store.buy(pack)
        #expect(events.take() == [
            Events.purchaseStart("frootopia_stories"), Events.purchaseResult("frootopia_stories", .pending),
        ])
        // The parent's yes: bought after all, and the pack comes down.
        appStore.send(StorePurchase(product: "frootopia_stories", revoked: false, finish: {}))
        #expect(await until { events.names.contains("pack_download") })
        let bought = events.take()
        #expect(bought.map(\.name) == ["purchase_result", "pack_download"])
        #expect(bought.first == Events.purchaseResult("frootopia_stories", .purchased))
        #expect(bought.last?.props["pack"] as? String == "frootopia-stories")
        #expect(bought.last?.props["result"] as? String == "installed")
        #expect(bought.last?.props["bytes"] as? Int64 == pack.size)
        // Restore purchases: what the account has bought (the App Store lists it now); or the App Store not there.
        appStore.owned = ["frootopia_stories"]
        await store.restorePurchases()
        #expect(events.take() == [Events.restore(.restored, count: 1)])
        appStore.syncFails = true
        await store.restorePurchases()
        #expect(events.take() == [Events.restore(.failed, count: 0)])
        // A download that fails says so too (the purchases read again, with the pack gone and no connection).
        try packs.remove(pack)
        log.failing = true
        await store.restore()
        let failed = events.take()
        #expect(failed.map(\.name) == ["pack_download"])
        #expect(failed.first?.props["result"] as? String == "failed")
        for e in bought + failed { #expect(Events.problem(e.name, e.props) == nil, "\(e)") }
    }

    /// Two asks for one pack (an update and the purchases read at launch) share one download.
    @Test func aSecondAskWaitsForTheSameDownload() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        let fetcher = server(log)
        fetcher.holding = true
        let store = store(appStore, log: log, fetcher: fetcher)
        defer { cleanUp(store) }
        async let first: Void = store.restore()
        async let second: Void = store.restore()
        #expect(await until { fetcher.started.count == 1 })
        try await Task.sleep(for: .milliseconds(200))
        fetcher.release()
        _ = await (first, second)
        #expect(fetcher.started.count == 1)
        #expect(packs.isInstalled(pack))
        #expect(store.installs == 1)
    }

    /// L10: "Download now" starts a download waiting for Wi-Fi again, with cellular; what the first still says is
    /// ignored.
    @Test func downloadNowLetsItUseCellular() async throws {
        let appStore = FakeAppStore()
        appStore.owned = ["frootopia_stories"]
        let log = Log()
        let fetcher = server(log)
        fetcher.holding = true
        let store = store(appStore, log: log, fetcher: fetcher)
        defer { cleanUp(store) }
        Task { await store.restore(cellular: false) }
        #expect(await until { fetcher.started.count == 1 })
        #expect(fetcher.started[0].cellular == false)
        #expect(store.downloads[pack.id] != nil)
        let first = fetcher.started[0].key
        store.downloadNow(pack)
        #expect(fetcher.cancelled == [first])
        #expect(fetcher.started.count == 2)
        #expect(fetcher.started[1].cellular)
        fetcher.events(first, .failed(FetchFailure(URLError(.cancelled))))
        #expect(store.failed.isEmpty, "the download let go said it failed")
        fetcher.release()
        #expect(await until { packs.isInstalled(pack) })
        #expect(store.downloads.isEmpty)
    }

    /// A download the app's last run left going (the system carried on with it) shows, and is installed once done;
    /// one that finished while the app wasn't running is installed as it's handed over.
    @Test func aDownloadFromTheLastRunIsTakenUp() async throws {
        let appStore = FakeAppStore()
        let log = Log()
        let fetcher = server(log)
        fetcher.left = ["frootopia-stories@1#old": RunningDownload(bytes: 100, cellular: true)]
        let store = store(appStore, log: log, fetcher: fetcher)
        defer { cleanUp(store) }
        store.start()
        #expect(await until { store.downloads[pack.id] != nil })
        let copy = scratch.appendingPathComponent("handed-over.zip")
        try FileManager.default.copyItem(at: zip, to: copy)
        fetcher.events("frootopia-stories@1#old", .finished(copy))
        #expect(await until { packs.isInstalled(pack) })
        #expect(log.fetched.isEmpty)
        #expect(log.installed == ["frootopia-stories"])
        #expect(!FileManager.default.fileExists(atPath: copy.path))

        // Finished before the app took it up: installed all the same.
        try packs.remove(pack)
        let again = scratch.appendingPathComponent("handed-over-2.zip")
        try FileManager.default.copyItem(at: zip, to: again)
        fetcher.events("frootopia-stories@1#gone", .finished(again))
        #expect(await until { packs.isInstalled(pack) })
        // One of another version (the app updated meanwhile) isn't.
        let stale = scratch.appendingPathComponent("stale.zip")
        try FileManager.default.copyItem(at: zip, to: stale)
        fetcher.events("frootopia-stories@0#older", .finished(stale))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    // ----- Helpers -----

    private func until(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// A pack zip as tools/make_pack.py writes them: STORED entries, pack.json first.
    nonisolated static func writeZip(_ url: URL) throws {
        let files: [(String, Data)] = [
            ("pack.json", Data(#"{"format": 1, "game": "frootopia", "id": "frootopia-stories", "nodes": {}}"#.utf8)),
            ("scenes/fr2-0.m4a", Data(repeating: 7, count: 4_096)),
        ]
        var out = Data()
        var central = Data()
        func le16(_ d: inout Data, _ v: Int) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func le32(_ d: inout Data, _ v: Int) { le16(&d, v & 0xFFFF); le16(&d, (v >> 16) & 0xFFFF) }
        for (name, data) in files {
            let offset = out.count
            let n = Data(name.utf8)
            le32(&out, 0x0403_4b50); le16(&out, 20); le16(&out, 0); le16(&out, 0); le16(&out, 0); le16(&out, 0)
            le32(&out, 0); le32(&out, data.count); le32(&out, data.count); le16(&out, n.count); le16(&out, 0)
            out.append(n)
            out.append(data)
            le32(&central, 0x0201_4b50); le16(&central, 20); le16(&central, 20); le16(&central, 0); le16(&central, 0)
            le16(&central, 0); le16(&central, 0); le32(&central, 0); le32(&central, data.count)
            le32(&central, data.count); le16(&central, n.count); le16(&central, 0); le16(&central, 0)
            le16(&central, 0); le16(&central, 0); le32(&central, 0); le32(&central, offset)
            central.append(n)
        }
        let start = out.count
        out.append(central)
        le32(&out, 0x0605_4b50); le16(&out, 0); le16(&out, 0); le16(&out, files.count); le16(&out, files.count)
        le32(&out, central.count); le32(&out, start); le16(&out, 0)
        try out.write(to: url)
    }
}

/// The App Store, faked: prices for the catalog's products, buying, the purchases owned and left unfinished, and
/// updates the test sends.
@MainActor
final class FakeAppStore: AppStoreClient, @unchecked Sendable {
    var owned: [String] = []
    var pending: [String] = []
    var bought: [String] = []
    var finished: [String] = []
    var syncs = 0
    var failing = false
    var pricesFail = false
    var priceAsks = 0
    var syncFails = false
    /// Buying waits for a parent's yes.
    var askToBuy = false
    /// Buying is cancelled (the player closes the App Store's sheet).
    var cancelling = false
    private var loaded = false
    /// Set by updates(), which the store calls on the main actor.
    nonisolated(unsafe) private var continuation: AsyncStream<StorePurchase>.Continuation?

    nonisolated func prices(_ products: Set<String>) async throws -> [String: String] {
        try await MainActor.run {
            priceAsks += 1
            if pricesFail { throw URLError(.notConnectedToInternet) }
            loaded = true
        }
        return Dictionary(uniqueKeysWithValues: products.map { ($0, "£1.99") })
    }

    nonisolated func purchase(_ product: String) async throws -> PurchaseOutcome? {
        try await MainActor.run {
            guard loaded else { return nil }
            if failing { throw URLError(.cannotConnectToHost) }
            if cancelling { return .nothing }
            if askToBuy { return .pending }
            bought.append(product)
            if !owned.contains(product) { owned.append(product) }
            return .bought(purchase(product))
        }
    }

    nonisolated func entitlements() async -> [StorePurchase] {
        await MainActor.run { owned.map(purchase) }
    }

    nonisolated func unfinished() async -> [StorePurchase] {
        await MainActor.run { pending.map(purchase) }
    }

    nonisolated func updates() -> AsyncStream<StorePurchase> {
        let (stream, continuation) = AsyncStream.makeStream(of: StorePurchase.self)
        self.continuation = continuation
        return stream
    }

    nonisolated func sync() async throws {
        try await MainActor.run {
            syncs += 1
            if syncFails { throw URLError(.notConnectedToInternet) }
        }
    }

    /// A purchase made elsewhere, or a refund.
    func send(_ purchase: StorePurchase) {
        continuation?.yield(purchase)
    }

    private func purchase(_ product: String) -> StorePurchase {
        StorePurchase(product: product, revoked: false) { [weak self] in
            await MainActor.run { _ = self?.finished.append(product) }
        }
    }
}

/**
 * The pack server, faked: each download serves what [serve] gives (a zip of its own, or an error), its events
 * coming as PackDownloader's do. [holding]: the downloads wait for [release]. [left]: the downloads a last run left.
 */
@MainActor
final class FakeFetcher: PackFetching {
    var events: (String, PackFetchEvent) -> Void = { _, _ in }
    var started: [(url: URL, key: String, cellular: Bool)] = []
    var cancelled: [String] = []
    var left: [String: RunningDownload] = [:]
    var holding = false
    private let serve: @Sendable (URL) async throws -> URL
    private var held: [(URL, String)] = []

    init(serve: @escaping @Sendable (URL) async throws -> URL) {
        self.serve = serve
    }

    func start(_ url: URL, key: String, cellular: Bool) {
        started.append((url, key, cellular))
        if holding {
            held.append((url, key))
        } else {
            fetch(url, key)
        }
    }

    func cancel(_ key: String) {
        cancelled.append(key)
        held.removeAll { $0.1 == key }
    }

    func running() async -> [String: RunningDownload] { left }

    /// The downloads held go on.
    func release() {
        holding = false
        let due = held
        held = []
        for (url, key) in due { fetch(url, key) }
    }

    private func fetch(_ url: URL, _ key: String) {
        let serve = serve
        Task {
            do {
                let zip = try await serve(url)
                events(key, .progress(1))
                events(key, .finished(zip))
            } catch {
                events(key, .failed(FetchFailure(error)))
            }
        }
    }
}
