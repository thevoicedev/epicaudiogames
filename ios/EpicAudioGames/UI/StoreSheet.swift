// ui/StoreSheet.kt: one game's packs over the game or the Games tab, on the Shop's own rows (PackRows), with Restore
// purchases and Close.

import EpicAppCore
import SwiftUI

/**
 * One game's packs, over the game or the Games tab (docs/DESIGN.md › Shop and the store sheet): the heading "More from
 * <game>", the Shop's own rows for its packs (PackRows.swift), the store's messages, Restore purchases, and Close. As
 * tall as what's in it (taller than the screen, it scrolls); at accessibility text sizes, the whole screen (on an
 * iPad's wide window it's the system's form sheet). VoiceOver moves to its heading as it opens and is told the
 * troubles, the notes, the waiting and the download's progress as they come; Close, a swipe down, Escape on a keyboard
 * and VoiceOver's escape (the two-finger scrub) close it, and Magic Tap does nothing (the game under it stays paused).
 * Android's StoreSheet.kt.
 */
struct StoreSheet: View {
    let game: GameInfo
    let store: Store
    let installed: (PackInfo) -> Bool
    @State private var height: CGFloat = 320
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epicColors) private var c
    @Environment(\.epicType) private var type

    /// The sheet's corners (presentationCornerRadius), which its edge follows.
    private static let corner: CGFloat = 28

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents(type.isAccessibilitySize ? [.large] : [.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Self.corner)
        .presentationBackground {
            // Edged round its top and down its sides (its foot is off the screen): in the contrast palettes the sheet
            // is the colour of what's under it, and without an edge its top would be lost. The sheet cuts off the
            // stroke's outer half.
            ZStack {
                c.surfaceRaised
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .stroke(c.outlineSubtle, lineWidth: 2 * c.edgeWidth)
                    .padding(.bottom, -60)
            }
        }
        // The sheet pauses the game, so no mic is listening while it speaks.
        .storeAnnouncements(store)
        // Magic Tap here has nothing to do: taken, so iOS doesn't hand it to what's playing (NowPlaying), which would
        // carry the game on under the sheet, the mic opening while VoiceOver reads the store's news. The help sheet
        // takes it the same way.
        .accessibilityAction(.magicTap) {}
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShopGameSection(
                game: game, store: store, installed: installed, title: "More from \(game.title)", cover: false,
                focusHeading: true)
            ShopDivider()
            StoreMessages(store: store)
            RestoreSection(store: store)
            // Escape on a keyboard is Close too (docs/DESIGN.md › Tablets… › Keyboard).
            EpicButton("Close", kind: .secondary, wide: true) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("store-close")
        }
        .padding(.horizontal, 20)
        // Under the sheet's drag indicator, which floats over it.
        .padding(.top, 36)
        .padding(.bottom, 16)
        .readableWidth()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store-sheet")
    }
}
