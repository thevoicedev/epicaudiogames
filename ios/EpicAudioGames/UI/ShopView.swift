// ui/ShopScreen.kt: the Shop tab, every game's packs on the store sheet's rows, the store's messages and Restore
// purchases.

import EpicAppCore
import SwiftUI

/**
 * Where the Shop or a store sheet was opened from: the usage data's shop_view source (web/analytics/events.json). The
 * Shop tab, a game's card ("Get …"), a game's menu ("More stories and levels"), or a chapter's end that a pack
 * unlocks. Android's ShopSource.
 */
nonisolated enum ShopSource: String, CaseIterable, Sendable {
    case tab
    case card
    case menu
    case lockedEnd = "locked_end"

    var key: String { rawValue }
}

/**
 * The Shop tab (docs/DESIGN.md › Shop and the store sheet): its heading and what buying is like, then every game with
 * packs as a section of pack rows (PackRows.swift, the store sheet's), the store's messages, and Restore purchases.
 * Shown, it reads the purchases again ([onShown]: AppModel.shopShown, at most once a minute). A message the store has
 * (a purchase that didn't go through) is scrolled to as it comes, at once with Reduce Motion, unless VoiceOver is on:
 * VoiceOver says it, and the page doesn't move under the player's finger. [speaks]: the Shop is the tab in sight, with
 * nothing over it, so VoiceOver hears the store's news from here (a tab out of sight keeps its views). Android's
 * ShopScreen.kt.
 */
struct ShopView: View {
    let games: [GameInfo]
    let store: Store
    let installed: (PackInfo) -> Bool
    let speaks: Bool
    let onShown: @MainActor () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.epicReduceMotion) private var reduceMotion
    @Environment(\.epicColors) private var c

    /// The store's messages, as a place on the page.
    private static let messages = "messages"

    var body: some View {
        let forSale = games.filter { !$0.packs.isEmpty }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScreenHeader("Shop")
                            .accessibilityIdentifier("shop-heading")
                        Text("One-time purchases. No ads and no subscriptions. Packs download once, then play offline.")
                            .epicFont(.body)
                            .foregroundStyle(c.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readableWidth()
                    ForEach(forSale) { game in
                        VStack(alignment: .leading, spacing: 20) {
                            ShopDivider()
                            ShopGameSection(game: game, store: store, installed: installed)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("shop-game-\(game.id)")
                        }
                        .readableWidth()
                    }
                    if store.message != nil || store.note != nil {
                        StoreMessages(store: store)
                            .readableWidth()
                            .id(Self.messages)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        ShopDivider()
                        RestoreSection(store: store)
                    }
                    .readableWidth()
                }
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.message) { _, now in if now != nil { toMessages(proxy) } }
            .onChange(of: store.note) { _, now in if now != nil { toMessages(proxy) } }
        }
        .background { c.background.ignoresSafeArea() }
        .storeAnnouncements(store, speaks: speaks)
        .onAppear { onShown() }
    }

    /// The store's messages scrolled into view, once laid out (not with VoiceOver: it says them where the player is).
    private func toMessages(_ proxy: ScrollViewProxy) {
        guard !voiceOver else { return }
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.25)
        DispatchQueue.main.async {
            withAnimation(animation) { proxy.scrollTo(Self.messages, anchor: .top) }
        }
    }
}
