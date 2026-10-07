// ui/StoreSheet.kt: a game's packs, what each adds, its price, and buying it (or its download, or that it's in).

import EpicAppCore
import SwiftUI

/**
 * A game's packs: what each adds, its price, and buying it (or its download, that it's bought and waits to download
 * or for approval, or that it's installed). A pack's own trouble shows under it. As tall as what's in it; taller than
 * the screen (large text), it scrolls. VoiceOver says the troubles, the notes and the waiting as they come.
 */
struct StoreSheet: View {
    let game: GameInfo
    let store: Store
    @State private var height: CGFloat = 320

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Palette.card)
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
                case .downloading: break
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Up to four lines with large text, rather than cut short; it stops growing at the second accessibility
            // size, where a long word has no room to break.
            OutlinedText("MORE FROM \(game.title.uppercased())", size: 24, fill: Palette.goldUI, maxLines: 4,
                         isHeader: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .frame(maxWidth: .infinity, alignment: .leading)
            let _ = store.installs      // read, so the sheet shows a pack as installed once it is
            ForEach(game.packs) { pack in
                PackRow(pack: pack, store: store, installed: store.packs.isInstalled(pack))
            }
            if let message = store.message {
                Text(message)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.no)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("store-message")
            }
            if let note = store.note {
                Text(note)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("store-note")
            }
            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(Typography.labelLarge.font)
                    .foregroundStyle(Palette.title)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RippleStyle(shape: Capsule()))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        // ModalBottomSheet's drag handle takes 22 + 4 + 22 dp above the content; iOS's floats over it.
        .padding(.top, 48)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-sheet")
    }

    /// Says [text] with VoiceOver (nothing without it).
    private func announce(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

private struct PackRow: View {
    let pack: PackInfo
    let store: Store
    let installed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pack.title)
                .textStyle(.titleLarge)
                .foregroundStyle(Palette.title)
            if !pack.description.isEmpty {
                Text(pack.description)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.ink.opacity(0.85))
            }
            HStack(spacing: 0) {
                Text("\(pack.megabytes) MB download")
                    .textStyle(.bodySmall)
                    .foregroundStyle(Palette.ink.opacity(0.7))
                state
            }
            if let failed = store.failed[pack.id] {
                Text(failed)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.no)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// INSTALLED, its download, DOWNLOAD (bought, not here), PAYMENT PENDING, or its price.
    @ViewBuilder private var state: some View {
        if installed {
            Spacer(minLength: 0)
            Pill(text: "INSTALLED", background: Palette.headerLine, color: Palette.ink)
        } else if let download = store.downloads[pack.id] {
            switch download {
            case .downloading(let progress):
                // Compose's Row: the spacer and the bar share what's left (weight 1 each).
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                LinearProgress(progress: progress)
                    .frame(maxWidth: .infinity)
            case .installing:
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                LinearProgress(progress: 1)
                    .frame(maxWidth: .infinity)
            case .waitingForWiFi:
                // L10: it waits for Wi-Fi; the player can let it use cellular.
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Pill(text: "WAITING FOR WI-FI", background: Palette.headerLine, color: Palette.ink)
                    BuyButton(label: "DOWNLOAD NOW") { store.downloadNow(pack) }
                }
            case .waitingForNetwork:
                Spacer(minLength: 0)
                Pill(text: "WAITING FOR A CONNECTION", background: Palette.headerLine, color: Palette.ink)
            }
        } else if store.owned.contains(pack.product) {
            Spacer(minLength: 0)
            BuyButton(label: "DOWNLOAD") { store.downloadNow(pack) }
        } else if store.pending.contains(pack.product) {
            Spacer(minLength: 0)
            Pill(text: "PAYMENT PENDING", background: Palette.headerLine, color: Palette.ink)
        } else {
            Spacer(minLength: 0)
            let price = store.prices[pack.product]
            BuyButton(label: price ?? "GET", loading: price == nil && store.loading) {
                Task { await store.buy(pack) }
            }
        }
    }
}

/// The price (GET until it's known, a spinner while it's asked for: GET still works), DOWNLOAD or DOWNLOAD NOW.
private struct BuyButton: View {
    let label: String
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(label)
                    .font(Lilita.font(18))
                    .foregroundStyle(.white)
                    .opacity(loading ? 0 : 1)
                if loading {
                    ProgressView().tint(.white)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(Palette.yes, in: RoundedRectangle(cornerRadius: 18, style: .circular))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}
