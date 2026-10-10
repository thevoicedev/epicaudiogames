// ui/PackRows.kt: a game's packs as the Shop tab and the store sheet show them, their states, the store's messages and
// Restore purchases.

import EpicAppCore
import SwiftUI

// A game's packs, as the Shop tab and the store sheet show them (docs/DESIGN.md › Shop and the store sheet): each
// pack's title, what it adds, its download's size and its state, always as words with an icon, never colour alone;
// then the store's messages and Restore purchases. Store.swift does the buying and the downloads. VoiceOver is told the
// troubles, the notes and the downloads as they come ([storeAnnouncements]). Android: PackRows.kt.

/**
 * What a pack shows: its state, from what the store knows of it (Store.swift). Android's PackUiState, with iOS's own
 * download states as well (DownloadState: installing, or waiting for Wi-Fi or for a connection).
 */
nonisolated enum PackUiState: Equatable, Sendable {
    /// On this phone: a tick and "Installed".
    case installed
    /// Downloading, [percent] done (0 to 100): the bar and "Downloading, 40%". What VoiceOver is told by itself changes
    /// only at each [milestone] (0, 25, 50 and 75%), so it isn't talking all the way through.
    case downloading(percent: Int)
    /// Downloaded, and being checked and unpacked: "Installing…".
    case installing
    /// A download the player didn't ask for waits for Wi-Fi rather than use cellular or Low Data Mode (L10): "Waiting
    /// for Wi-Fi", and Download now.
    case waitingForWiFi
    /// No network at all: "Waiting for a connection" (it carries on when there is one).
    case waitingForNetwork
    /// Paid for (on this phone or another) but not here: "Bought", and its Download button.
    case bought
    /// Paid for with a payment still to be approved (Ask to Buy): a clock and "Payment pending".
    case pending
    /// For sale: "Buy for [price]", the App Store's own price text ("£1.99").
    case forSale(price: String)
    /// For sale, its price not known (yet): "Get", with a spinner while the store is asked ([loading]); it still works.
    case priceUnknown(loading: Bool)

    /**
     * A pack's state: [installed] (at the catalog's version), its [download] if one is going, whether it's [owned] or
     * its payment [pending], and its [price] if the store has said ([loading]: it's being asked). The first that
     * applies, in that order.
     */
    static func of(
        installed: Bool, download: DownloadState?, owned: Bool, pending: Bool, price: String?, loading: Bool
    ) -> PackUiState {
        if installed { return .installed }
        switch download {
        case .downloading(let progress)?: return .downloading(percent: percent(progress))
        case .installing?: return .installing
        case .waitingForWiFi?: return .waitingForWiFi
        case .waitingForNetwork?: return .waitingForNetwork
        case nil: break
        }
        if owned { return .bought }
        if pending { return .pending }
        if let price { return .forSale(price: price) }
        return .priceUnknown(loading: loading)
    }

    /// A download's [progress] (0 to 1) as a whole percent, 0 to 100: one that runs over its size (or a bad number)
    /// stays within the bar.
    static func percent(_ progress: Double) -> Int {
        guard !progress.isNaN else { return 0 }
        return Int(min(max(progress, 0), 1) * 100)
    }

    /// For a download, what VoiceOver last heard of it: 0, 25, 50 or 75 (percent). Nil for the other states.
    var milestone: Int? {
        guard case .downloading(let percent) = self else { return nil }
        return min(percent / 25 * 25, 75)
    }
}

/// The buy button's words, for a pack that's for sale: "Buy for £1.99", or "Get" until the price is known.
nonisolated func buyText(_ state: PackUiState) -> String? {
    switch state {
    case .forSale(let price): "Buy for \(price)"
    case .priceUnknown: "Get"
    default: nil
    }
}

/**
 * The buy button's name for VoiceOver: its words first, so Voice Control finds it by what it shows, then which pack it
 * is ("Buy for £1.99: The Werewolf, 45 more mysteries"; "Get The Werewolf, 45 more mysteries, loading the price"). Nil
 * for a pack that isn't for sale.
 */
nonisolated func buyLabel(_ state: PackUiState, game: String, pack: String) -> String? {
    let name = "\(game), \(pack)"
    switch state {
    case .forSale(let price): return "Buy for \(price): \(name)"
    case .priceUnknown(let loading): return loading ? "Get \(name), loading the price" : "Get \(name)"
    default: return nil
    }
}

/// A bought pack's Download button's name for VoiceOver, its words first: "Download 45 more mysteries for The Werewolf".
nonisolated func downloadLabel(game: String, pack: String) -> String { "Download \(pack) for \(game)" }

/// What VoiceOver hears of a download, at its milestones only: "45 more mysteries: downloading, 50%".
nonisolated func downloadingLabel(pack: String, milestone: Int) -> String { "\(pack): downloading, \(milestone)%" }

/// A pack's download size, to the nearest megabyte: "15 MB download".
nonisolated func downloadSize(_ bytes: Int64) -> String { "\((bytes + 500_000) / 1_000_000) MB download" }

/**
 * A game's packs: its [title] as a level-2 heading (in the Shop the game's, beside its small cover, which is only a
 * picture; in the store sheet "More from …", without it), then a row for each pack. [installed] says which are on this
 * phone. [focusHeading]: VoiceOver moves to the heading as it appears (the store sheet's). Android's ShopGameSection.
 */
struct ShopGameSection: View {
    let game: GameInfo
    let store: Store
    let installed: (PackInfo) -> Bool
    var title: String?
    var cover = true
    var focusHeading = false
    @Environment(\.epicColors) private var c
    @Environment(\.epicType) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // At accessibility text sizes the words need the room more than the picture does.
                if cover && !type.isAccessibilitySize { SmallCover(id: game.id) }
                if focusHeading {
                    // The store sheet's, once it has risen: iOS moves VoiceOver into a sheet itself as it does, so
                    // a heading focused sooner would lose it to the sheet's grabber.
                    SectionHeading(title ?? game.title)
                        .focusOnAppear(game.id, after: A11y.focusAfterTransition)
                } else {
                    SectionHeading(title ?? game.title)
                }
            }
            let _ = store.installs      // read, so a pack shows as installed once it is
            ForEach(Array(game.packs.enumerated()), id: \.element.id) { i, pack in
                if i > 0 { ShopDivider() }
                PackRow(pack: pack, game: game, store: store, installed: installed(pack))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A game's cover, small and square: a picture only (the heading beside it names the game).
private struct SmallCover: View {
    let id: String
    @Environment(\.epicColors) private var c

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let cover = Covers.image(id) {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                c.surface
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/**
 * A pack: its title (a level-3 heading), what it adds, its download's size, and its state ([PackUiState]):
 * "Installed", its download, that it's bought (with its Download button), that its payment is pending, or its Buy
 * button. A failed download says so under it, as it happens. VoiceOver reads each button by its full name. Android's
 * PackRow.
 */
struct PackRow: View {
    let pack: PackInfo
    let game: GameInfo
    let store: Store
    let installed: Bool
    @Environment(\.epicColors) private var c

    var body: some View {
        let state = PackUiState.of(
            installed: installed, download: store.downloads[pack.id], owned: store.owned.contains(pack.product),
            pending: store.pending.contains(pack.product), price: store.prices[pack.product], loading: store.loading)
        VStack(alignment: .leading, spacing: 8) {
            Text(pack.title)
                .epicFont(.itemTitle)
                .foregroundStyle(c.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h3)
            if !pack.description.isEmpty {
                Text(pack.description)
                    .epicFont(.body)
                    .foregroundStyle(c.text)
            }
            Text(downloadSize(pack.size))
                .epicFont(.secondary)
                .foregroundStyle(c.textMuted)
            status(state)
            if let failed = store.failed[pack.id] {
                StatusText(text: failed, kind: .error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pack-\(pack.id)")
    }

    @ViewBuilder private func status(_ state: PackUiState) -> some View {
        switch state {
        case .installed:
            PackStatus(icon: .checkCircle, text: "Installed", success: true)
        case .downloading(let percent):
            Downloading(pack: pack, percent: percent, progress: store.downloads[pack.id]?.progress ?? 0)
        case .installing:
            // The full bar is only a picture here: VoiceOver would read it as "Downloading, 100 percent".
            LinearProgress(progress: 1)
                .accessibilityHidden(true)
            Text("Installing…")
                .epicFont(.label)
                .foregroundStyle(c.text)
        case .waitingForWiFi:
            // L10: it waits for Wi-Fi; the player can let it use cellular.
            PackStatus(icon: .schedule, text: "Waiting for Wi-Fi")
            // Its words first, then which pack it is, as Buy's (a game's packs can all be waiting).
            EpicButton(
                "Download now", icon: .download, description: "Download now: \(game.title), \(pack.title)", wide: true
            ) {
                store.downloadNow(pack)
            }
            .accessibilityIdentifier("download-\(pack.id)")
        case .waitingForNetwork:
            PackStatus(icon: .schedule, text: "Waiting for a connection")
        case .bought:
            PackStatus(icon: .shoppingBagOutlined, text: "Bought")
            EpicButton(
                "Download \(pack.title)", icon: .download,
                description: downloadLabel(game: game.title, pack: pack.title), wide: true
            ) {
                store.downloadNow(pack)
            }
            .accessibilityIdentifier("download-\(pack.id)")
        case .pending:
            PackStatus(icon: .schedule, text: "Payment pending")
            Text("Waiting for the payment to be approved.")
                .epicFont(.secondary)
                .foregroundStyle(c.textMuted)
        case .forSale, .priceUnknown:
            // The App Store's own price text; until it's known, Get (with a spinner while it's asked for), which still
            // works. VoiceOver hears the words first, then what they buy.
            EpicButton(
                buyText(state) ?? "Get", description: buyLabel(state, game: game.title, pack: pack.title),
                busy: state == .priceUnknown(loading: true), wide: true
            ) {
                Task { await store.buy(pack) }
            }
            .accessibilityIdentifier("buy-\(pack.id)")
        }
    }
}

/// A pack's state as an icon and words ("Installed" in the success colour), read as its words.
private struct PackStatus: View {
    let icon: MaterialIcon
    let text: String
    var success = false
    @Environment(\.epicColors) private var c

    var body: some View {
        let color = success ? c.success : c.text
        HStack(spacing: 8) {
            IconView(icon: icon, size: 24, color: color)
            Text(text)
                .epicFont(.label)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}

/**
 * A download: the 8 pt bar (VoiceOver reads its percent) and "Downloading, 40%". What VoiceOver is told by itself
 * changes only at 0, 25, 50 and 75% ("45 more mysteries: downloading, 50%"), so it isn't talking all the way through;
 * and only where the store speaks ([EnvironmentValues.epicStoreSpeaks]), so a row out of sight doesn't say it as well.
 * Android's Downloading.
 */
private struct Downloading: View {
    let pack: PackInfo
    let percent: Int
    let progress: Double
    @Environment(\.epicStoreSpeaks) private var speaks
    @Environment(\.epicColors) private var c

    var body: some View {
        let milestone = PackUiState.downloading(percent: percent).milestone ?? 0
        VStack(alignment: .leading, spacing: 8) {
            LinearProgress(progress: progress)
            Text(verbatim: "Downloading, \(percent)%")
                .epicFont(.label)
                .foregroundStyle(c.text)
                .accessibilityLabel(downloadingLabel(pack: pack.title, milestone: milestone))
        }
        // The Shop and the store sheet have no game listening under them (the sheet pauses it).
        .onChange(of: milestone, initial: true) { _, now in
            if speaks { A11y.announce(downloadingLabel(pack: pack.title, milestone: now), unlessListening: false) }
        }
    }
}

/**
 * What the store has to say that isn't about one pack: a purchase that didn't go through, the store not being there
 * (an error, with its icon), or how Restore purchases went. Android's StoreMessages.
 */
struct StoreMessages: View {
    let store: Store

    var body: some View {
        if store.message != nil || store.note != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let message = store.message {
                    StatusText(text: message, kind: .error)
                        .accessibilityIdentifier("store-message")
                }
                if let note = store.note {
                    StatusText(text: note)
                        .accessibilityIdentifier("store-note")
                }
            }
        }
    }
}

/// Restore purchases, what it's for, and who handles the payments. Android's RestoreSection.
struct RestoreSection: View {
    let store: Store
    @Environment(\.epicColors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bought a pack on another phone? Restore it here.")
                .epicFont(.body)
                .foregroundStyle(c.text)
            EpicButton("Restore purchases", kind: .secondary, wide: true) {
                Task { await store.restorePurchases() }
            }
            .accessibilityIdentifier("restore")
            Text("Payments are handled by the App Store.")
                .epicFont(.secondary)
                .foregroundStyle(c.textMuted)
        }
    }
}

/// A line between a sheet's or the Shop's parts, in the theme's decorative edge. Android's ShopDivider.
struct ShopDivider: View {
    @Environment(\.epicColors) private var c

    var body: some View {
        c.outlineSubtle
            .frame(height: c.edgeWidth)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

extension View {
    /**
     * VoiceOver is told what the [store] says as it comes (docs/DESIGN.md › Everywhere › Status messages): a message,
     * a note, a pack's download failing, and a download waiting or installing (a download's progress says its own
     * milestones). Only while [speaks] (the screen showing it is the one in sight), so the Shop and a sheet never both
     * say it. Android's StatusText is a live region, which TalkBack hears only from what's on screen.
     */
    func storeAnnouncements(_ store: Store, speaks: Bool = true) -> some View {
        modifier(StoreAnnouncements(store: store, speaks: speaks))
    }
}

private struct StoreAnnouncements: ViewModifier {
    let store: Store
    let speaks: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.epicStoreSpeaks, speaks)
            .onChange(of: store.message) { _, now in announce(now) }
            .onChange(of: store.note) { _, now in announce(now) }
            .onChange(of: store.failed) { old, now in
                for (id, failure) in now where old[id] != failure { announce(failure) }
            }
            .onChange(of: store.downloads) { old, now in
                for (id, state) in now where old[id] != state {
                    switch state {
                    case .waitingForWiFi: announce("Waiting for Wi-Fi")
                    case .waitingForNetwork: announce("Waiting for a connection")
                    case .installing: announce("Installing")
                    case .downloading: break        // Downloading says its milestones
                    }
                }
            }
    }

    /// Says [text] with VoiceOver (nothing without it), after what it's saying: no game is listening under the Shop or
    /// the store sheet (which pauses it).
    private func announce(_ text: String?) {
        guard speaks, let text else { return }
        A11y.announce(text, unlessListening: false)
    }
}

/// Whether the store's news is said where this is (StoreAnnouncements): yes, unless a screen says it's out of sight.
nonisolated private struct EpicStoreSpeaksKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    nonisolated var epicStoreSpeaks: Bool {
        get { self[EpicStoreSpeaksKey.self] }
        set { self[EpicStoreSpeaksKey.self] = newValue }
    }
}
