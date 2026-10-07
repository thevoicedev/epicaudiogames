// Store.kt: buying packs (StoreKit 2 here, Play Billing there) and getting them.

import EpicAppCore
import Foundation
import Network
import Observation
import UIKit
import os

/**
 * Buying packs (non-consumable in-app purchases) and getting them. A purchase is finished as soon as the App Store
 * says it's bought (Store.kt acknowledges one at once too): it's the player's whether or not its download works yet.
 * Then the pack's zip is downloaded from the pack server, checked and unpacked (PackStore). A pack bought before (on
 * this phone or another, with the same Apple Account) that isn't here is downloaded whenever the purchases are read:
 * at launch, when the app comes back, when a store sheet opens, and a few times more by itself after a download fails.
 *
 * Downloads go on in the background (PackDownloader): one the system finished, or carried on with, while the app
 * wasn't running is taken up at launch. One the player didn't ask for (at launch, or as the app comes back) waits for
 * Wi-Fi rather than use cellular or Low Data Mode (L10); "Download now" lets it.
 *
 * In a build with no pack server, GET says the packs can't be downloaded yet, before anything is bought (L6). A
 * refunded purchase takes its pack off the phone, once its game is closed (D11, L13).
 *
 * Debug builds also install any <pack>-<version>.zip found in Documents/incoming (put there with the Files app, or
 * simctl), to try packs without a store or a server.
 */
@Observable
final class Store {
    /// Each product's price, as the App Store shows it ("£1.99"), once known.
    private(set) var prices: [String: String] = [:]
    /// The prices are being asked for (the sheet's GET shows a spinner).
    private(set) var loading = false
    /// The packs downloading, and how each is getting on.
    private(set) var downloads: [String: DownloadState] = [:]
    /// Why a pack's download failed, by pack: its own game's sheet says so, under it.
    private(set) var failed: [String: String] = [:]
    /// The products bought (their packs, if not here, show DOWNLOAD), and those waiting for approval (Ask to Buy).
    private(set) var owned: Set<String> = []
    private(set) var pending: Set<String> = []
    /// Something to tell the player that isn't about one pack (the store not being there, a purchase going wrong).
    var message: String?
    /// How "Restore purchases" went, when nothing went wrong.
    var note: String?
    /// Bumped when a pack is installed (or taken away), so the screens and maps pick it up.
    private(set) var installs = 0

    @ObservationIgnored let packs: PackStore
    /// A pack was installed: called once for each install (the open game may be waiting for it).
    @ObservationIgnored var onInstalled: (PackInfo) -> Void = { _ in }
    /// Whether a game is open: a refunded pack of its own waits until it closes.
    @ObservationIgnored var inUse: (String) -> Bool = { _ in false }

    @ObservationIgnored private let all: [PackInfo]
    @ObservationIgnored private let packsURL: String
    @ObservationIgnored private let appStore: any AppStoreClient
    @ObservationIgnored private let fetcher: any PackFetching
    /// How long to wait before trying a failed download again by itself, each time.
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var refunded: [PackInfo] = []
    /// The downloads going, by pack.
    @ObservationIgnored private var going: [String: Download] = [:]
    /// Downloads let go (started again with cellular): what they still say is ignored.
    @ObservationIgnored private var dropped: Set<String> = []
    @ObservationIgnored private var retries: [String: Int] = [:]
    @ObservationIgnored private var listening = false
    @ObservationIgnored private var network = DownloadState.Network.unknown
    @ObservationIgnored private var monitor: NWPathMonitor?

    /// A download going: its name with the fetcher, whether it may use cellular, and who waits for it.
    private struct Download {
        let pack: PackInfo
        let key: String
        let cellular: Bool
        var received: Int64 = 0
        var installing = false
        var waiting: [CheckedContinuation<Bool, Never>] = []
    }

    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "store")

    /// [packsURL]: the pack server (Info.plist's EpicPacksURL); empty when this build has none.
    init(
        games: [GameInfo], packs: PackStore, packsURL: String, appStore: any AppStoreClient = StoreKitClient(),
        fetcher: any PackFetching = PackDownloader.shared,
        retryDelays: [Duration] = [.seconds(15), .seconds(60), .seconds(300)]
    ) {
        all = games.flatMap(\.packs)
        self.packs = packs
        self.packsURL = packsURL
        self.appStore = appStore
        self.fetcher = fetcher
        self.retryDelays = retryDelays
    }

    /**
     * Store.kt's start: transactions listened for from launch, the downloads the last run left going taken up, then
     * the prices, and the purchases made before.
     */
    func start() {
        packs.cleanUp()
        #if DEBUG
        installIncoming()
        #endif
        guard !all.isEmpty else { return }
        listen()
        watchNetwork()
        let updates = appStore.updates()
        tasks.append(Task { [weak self] in
            for await purchase in updates {
                guard let self else { return }
                // Ask to Buy's yes was asked for: it may use cellular. A purchase on another device waits for Wi-Fi.
                await self.handle(purchase, cellular: self.pending.contains(purchase.product))
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            await self.adopt()
            await self.loadProducts()
            for purchase in await self.appStore.unfinished() { await self.handle(purchase, cellular: false) }
            await self.restore(cellular: false)
        })
    }

    /// Stops listening for transactions and the network (tests; the app's store lasts as long as the app).
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        monitor?.cancel()
        monitor = nil
    }

    /**
     * The packs bought before: any not on this phone are downloaded ([cellular]: on cellular and in Low Data Mode
     * too), and any purchase not finished is. Prices still missing are asked for again.
     */
    func restore(cellular: Bool = true) async {
        _ = await readPurchases(cellular: cellular)
    }

    /// The sheet's "Restore purchases": the App Store is asked again for this account's purchases (it may ask the
    /// player to sign in), then as [restore], saying how it went.
    func restorePurchases() async {
        message = nil
        note = nil
        do {
            try await appStore.sync()
        } catch {
            Self.log.error("can't sync with the App Store: \(error, privacy: .public)")
            message = Self.unavailable
        }
        let (ok, bought) = await readPurchases(cellular: true)
        if ok && message == nil { note = bought ? Self.restored : Self.nothingToRestore }
    }

    /// A store sheet opening (or closing): what was said before goes; opening reads the purchases again.
    func sheet(open: Bool) {
        message = nil
        note = nil
        guard open else { return }
        failed = [:]
        Task { await restore(cellular: true) }
    }

    func buy(_ pack: PackInfo) async {
        message = nil
        note = nil
        if packsURL.isEmpty {
            // L6: nothing is bought that couldn't be downloaded (Store.kt says so too).
            message = Self.noServer
            return
        }
        do {
            switch try await appStore.purchase(pack.product) {
            case nil:
                message = Self.unavailable
                await loadProducts()
            case .bought(let purchase)?:
                await handle(purchase, cellular: true)
            case .pending?:
                pending.insert(pack.product)        // Ask to Buy: the purchase comes later, as an update
            case .nothing?:
                break
            }
        } catch {
            Self.log.error("purchase failed: \(error, privacy: .public)")
            message = Self.purchaseFailed
        }
    }

    /// DOWNLOAD (bought, not here) or "Download now" (waiting for Wi-Fi): the pack downloads, on cellular too.
    func downloadNow(_ pack: PackInfo) {
        guard let d = going[pack.id] else {
            Task { _ = await download(pack, cellular: true) }
            return
        }
        guard !d.cellular, !d.installing, let url = pack.downloadURL(packsURL) else { return }
        dropped.insert(d.key)
        fetcher.cancel(d.key)
        let key = Self.key(pack)
        going[pack.id] = Download(pack: pack, key: key, cellular: true, waiting: d.waiting)
        refresh()
        listen()
        fetcher.start(url, key: key, cellular: true)
    }

    /// A game closed: the packs refunded while it was open are taken away now (L13).
    func gameClosed() {
        let due = refunded
        refunded = []
        due.forEach(remove)
    }

    // ----- Purchases -----

    private func loadProducts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            for (id, price) in try await appStore.prices(Set(all.map(\.product))) { prices[id] = price }
        } catch {
            Self.log.error("can't load the products: \(error, privacy: .public)")
        }
    }

    /// The purchases this account has, each handled; whether every download went, and whether any was bought.
    private func readPurchases(cellular: Bool) async -> (ok: Bool, bought: Bool) {
        if all.contains(where: { prices[$0.product] == nil }) { await loadProducts() }
        let purchases = await appStore.entitlements()
        var ok = true
        for purchase in purchases { ok = await handle(purchase, cellular: cellular) && ok }
        return (ok, purchases.contains { !$0.revoked })
    }

    /// A purchase: finished at once, then its packs downloaded if they aren't here (false if one isn't).
    @discardableResult
    private func handle(_ purchase: StorePurchase, cellular: Bool) async -> Bool {
        let bought = all.filter { $0.product == purchase.product }
        if purchase.revoked {
            owned.remove(purchase.product)
            bought.forEach(refund)
            await purchase.finish()
            return true
        }
        owned.insert(purchase.product)
        pending.remove(purchase.product)
        await purchase.finish()
        var ok = true
        for pack in bought where !packs.isInstalled(pack) {
            ok = await download(pack, cellular: cellular) && ok
        }
        return ok
    }

    /// D11: a refunded or revoked pack comes off the phone, once its game isn't open (L13).
    private func refund(_ pack: PackInfo) {
        if inUse(pack.game) {
            if !refunded.contains(pack) { refunded.append(pack) }
        } else {
            remove(pack)
        }
    }

    private func remove(_ pack: PackInfo) {
        do {
            try packs.remove(pack)
            installs += 1
        } catch {
            Self.log.error("can't remove \(pack.id, privacy: .public): \(error, privacy: .public)")
        }
    }

    // ----- Downloads -----

    static let noServer = "Packs can't be downloaded in this version of the app yet."
    static let unavailable = "The store isn't available right now. Check that you're signed in to the App Store."
    static let purchaseFailed = "The purchase didn't go through. Please try again."
    static let restored = "Your purchases are restored."
    static let nothingToRestore = "There are no purchases to restore."

    static func couldntDownload(_ pack: PackInfo) -> String {
        "Couldn't download \(pack.title). Check your connection, and open the store again to retry."
    }

    static func noRoom(_ pack: PackInfo) -> String {
        "There isn't enough space on your iPhone for \(pack.title). It needs about "
            + "\((pack.roomNeeded + 500_000) / 1_000_000) MB free."
    }

    /// Downloads a pack's zip and installs it; a second ask waits for the same download. False if it couldn't.
    private func download(_ pack: PackInfo, cellular: Bool) async -> Bool {
        if going[pack.id] != nil {
            return await withCheckedContinuation { going[pack.id]?.waiting.append($0) }
        }
        guard let url = pack.downloadURL(packsURL) else {
            message = Self.noServer
            return false
        }
        guard packs.hasRoom(for: pack) else {
            failed[pack.id] = Self.noRoom(pack)
            return false
        }
        failed[pack.id] = nil
        listen()
        let key = Self.key(pack)
        going[pack.id] = Download(pack: pack, key: key, cellular: cellular)
        refresh()
        return await withCheckedContinuation { c in
            going[pack.id]?.waiting.append(c)
            fetcher.start(url, key: key, cellular: cellular)
        }
    }

    /// A download's name: "<pack>@<version>#<n>", unique to it.
    private static func key(_ pack: PackInfo) -> String {
        "\(pack.id)@\(pack.version)#\(UUID().uuidString.prefix(8))"
    }

    /// The catalog's pack a download is of, if it's of its version.
    private func pack(of key: String) -> PackInfo? {
        let name = key.split(separator: "#", maxSplits: 1).first.map(String.init) ?? key
        guard let at = name.lastIndex(of: "@"), let version = Int(name[name.index(after: at)...]) else { return nil }
        let id = String(name[..<at])
        return all.first { $0.id == id && $0.version == version }
    }

    /// The fetcher's events come here (once the store starts, or downloads).
    private func listen() {
        guard !listening else { return }
        listening = true
        fetcher.events = { [weak self] key, event in self?.fetched(key, event) }
    }

    /// The downloads the app's last run left going (the system carried on with them): shown, and installed once done.
    private func adopt() async {
        for (key, running) in await fetcher.running() {
            guard let pack = pack(of: key), !packs.isInstalled(pack), going[pack.id] == nil || going[pack.id]?.key == key
            else {
                dropped.insert(key)
                fetcher.cancel(key)
                continue
            }
            if going[pack.id] == nil {
                going[pack.id] = Download(pack: pack, key: key, cellular: running.cellular, received: running.bytes)
            }
        }
        refresh()
    }

    private func fetched(_ key: String, _ event: PackFetchEvent) {
        if dropped.contains(key) {
            // A download let go (started again, or left from the last run): what it still says is ignored.
            if event.progress == nil { dropped.remove(key) }
            event.discard()
            return
        }
        guard let pack = pack(of: key) else {
            event.discard()
            return
        }
        // One from the app's last run that went on, or finished, before it was taken up.
        if going[pack.id] == nil, !event.failed, !packs.isInstalled(pack) {
            going[pack.id] = Download(pack: pack, key: key, cellular: true)
        }
        guard let d = going[pack.id], d.key == key else {
            // Another download of a pack that's here, or downloading already: it's let go.
            if event.progress != nil {
                dropped.insert(key)
                fetcher.cancel(key)
            }
            event.discard()
            return
        }
        let id = pack.id
        switch event {
        case .progress(let bytes):
            going[id]?.received = bytes
            refresh()
        case .finished(let zip):
            going[id]?.installing = true
            refresh()
            Task { await install(d.pack, zip) }
        case .failed(let failure):
            Self.log.error("can't get \(id, privacy: .public): \(failure, privacy: .public)")
            done(id, ok: false, failure: failure)
        }
    }

    private func install(_ pack: PackInfo, _ zip: URL) async {
        // The check and the unpacking go on if the app is left meanwhile (or was launched for this).
        let background = UIApplication.shared.beginBackgroundTask(withName: "install \(pack.id)")
        defer {
            try? FileManager.default.removeItem(at: zip)
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        do {
            try await Self.install(pack, zip, packs)
            installed(pack)
            done(pack.id, ok: true)
        } catch {
            Self.log.error("can't install \(pack.id, privacy: .public): \(error, privacy: .public)")
            done(pack.id, ok: false, failure: FetchFailure(error))
        }
    }

    /// A download over: those waiting for it are told; one that failed says why, and is tried again later.
    private func done(_ id: String, ok: Bool, failure: FetchFailure? = nil) {
        guard let d = going.removeValue(forKey: id) else { return }
        refresh()
        if let failure {
            if failure.diskFull {
                failed[id] = Self.noRoom(d.pack)
            } else {
                failed[id] = Self.couldntDownload(d.pack)
                retryLater(d.pack, cellular: d.cellular)
            }
        } else {
            retries[id] = nil
        }
        d.waiting.forEach { $0.resume(returning: ok) }
    }

    /// A download that failed is tried again by itself, a while later, a few times (opening a sheet tries too).
    private func retryLater(_ pack: PackInfo, cellular: Bool) {
        let n = retries[pack.id, default: 0]
        guard n < retryDelays.count else { return }
        retries[pack.id] = n + 1
        let delay = retryDelays[n]
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, !self.packs.isInstalled(pack) else { return }
            await self.restore(cellular: cellular)
        })
    }

    private func installed(_ pack: PackInfo) {
        installs += 1
        onInstalled(pack)
    }

    /// The downloads as the sheet shows them, from how far each has got and the network.
    private func refresh() {
        downloads = going.mapValues {
            DownloadState.of(received: $0.received, size: $0.pack.size, cellular: $0.cellular,
                             installing: $0.installing, network: network)
        }
    }

    /// Wi-Fi, cellular, Low Data Mode or none: a download that can't use the network says what it waits for.
    private func watchNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let network = DownloadState.Network(
                connected: path.status == .satisfied, expensive: path.isExpensive, constrained: path.isConstrained)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.network = network
                    self?.refresh()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.epicaudiogames.app.network"))
        self.monitor = monitor
    }

    /// Checking and unpacking a pack (the Werewolf's is 133 MB) takes a while: not on the main actor.
    @concurrent
    nonisolated private static func install(_ pack: PackInfo, _ zip: URL, _ packs: PackStore) async throws {
        try packs.install(pack, zip: zip)
    }

    #if DEBUG
    /// Store.kt's installIncoming: a zip dropped in Documents/incoming is installed, if it's the catalog's.
    private func installIncoming() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = documents.appendingPathComponent("incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let all = all
        tasks.append(Task { [weak self] in
            for pack in all {
                let zip = dir.appendingPathComponent(pack.zipName)
                guard let self, FileManager.default.fileExists(atPath: zip.path), !self.packs.isInstalled(pack) else {
                    continue
                }
                do {
                    try await Self.install(pack, zip, self.packs)
                    self.installed(pack)
                } catch {
                    self.message = "\(pack.zipName) isn't the catalog's \(pack.id)."
                }
            }
        })
    }
    #endif
}

extension PackFetchEvent {
    var progress: Int64? {
        if case .progress(let bytes) = self { return bytes }
        return nil
    }

    var failed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// A zip no download wants any more is deleted.
    func discard() {
        if case .finished(let zip) = self { try? FileManager.default.removeItem(at: zip) }
    }
}
