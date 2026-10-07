// ui/HomeScreen.kt: the game list, a card per game with its cover, its description, what's free, and its packs.

import EpicAppCore
import SwiftUI

/**
 * The game list: a card per game, with its cover, its description, what's free, and its packs. [scroll] is kept by
 * the app's model, so the list is where it was after a game. [installs]: read, so the cards show a pack installed.
 */
struct HomeView: View {
    let games: [GameInfo]
    let continuing: Set<String>
    let installs: Int
    let installed: (PackInfo) -> Bool
    @Binding var scroll: String?
    let onOpen: (GameInfo) -> Void
    let onStore: (GameInfo) -> Void
    #if DEBUG
    /// Debug builds: a long press on the title opens the Audio Lab.
    var onLab: (() -> Void)?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                list
                    .onAppear {
                        if let scroll { proxy.scrollTo(scroll, anchor: .top) }
                    }
            }
        }
        .background { Backdrop() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                OutlinedText("Put on your headphones, listen, and answer out loud!", size: 19, maxLines: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .id(Self.top)
                ForEach(games) { game in
                    GameCard(
                        game: game, continuing: continuing.contains(game.id), installed: installed,
                        onStore: { onStore(game) }, onOpen: { onOpen(game) })
                }
            }
            .scrollTargetLayout()
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 28, trailing: 16))
        }
        .scrollPosition(id: $scroll, anchor: .top)
        // Compose's LazyColumn draws no scroll bar.
        .scrollIndicators(.hidden)
    }

    /// The line above the cards, as a place in the list.
    static let top = "top"

    @ViewBuilder private var header: some View {
        #if DEBUG
        HeaderBar("EPIC AUDIO GAMES")
            .onLongPressGesture { onLab?() }
        #else
        HeaderBar("EPIC AUDIO GAMES")
        #endif
    }
}

private struct GameCard: View {
    let game: GameInfo
    let continuing: Bool
    let installed: (PackInfo) -> Bool
    let onStore: () -> Void
    let onOpen: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 22, style: .circular)

    var body: some View {
        // An M3 Card(onClick): the whole card opens the game, with a ripple while pressed. The packs pill is a
        // button of its own on top (Compose's clickable Pill inside the card).
        Button(action: onOpen) { card }
            .buttonStyle(RippleStyle(shape: Self.shape))
            // VoiceOver: one element, its packs an action of it (the pill is a button of its own too).
            .accessibilityActions {
                if !game.packs.isEmpty { Button("More stories and levels", action: onStore) }
            }
            .accessibilityIdentifier("game-\(game.id)")
            .overlayPreferenceValue(PillBounds.self) { anchor in
                if let anchor, let label = packsLabel {
                    GeometryReader { g in
                        let r = g[anchor]
                        // 44 pt to touch, though the pill is smaller (the space around it counts), as Android's 48 dp.
                        let touch = max(r.height, 44)
                        Button(action: onStore) {
                            Color.clear.contentShape(Rectangle())
                        }
                        // Compose's ripple on the pill isn't clipped to its round ends; it's the pill's height.
                        .buttonStyle(RippleStyle(shape: Band(height: r.height)))
                        .frame(width: r.width, height: touch)
                        .offset(x: r.minX, y: r.midY - touch / 2)
                        .accessibilityLabel(label)
                        .accessibilityIdentifier("packs-\(game.id)")
                    }
                }
            }
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 3)
    }

    /// Its packs: one to get (it opens the store), or all of them in.
    private var packsLabel: String? {
        guard !game.packs.isEmpty else { return nil }
        let toGet = game.packs.first { !installed($0) }
        return toGet.map { "+ \($0.title.uppercased())" } ?? "ALL PACKS INSTALLED"
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if let cover = Covers.image(game.id) {
                        Image(uiImage: cover).resizable().scaledToFill()
                    } else {
                        Palette.headerBottom
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if continuing {
                        Pill(text: "CONTINUE", background: Palette.gold, color: Palette.ink).padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title)
                    .textStyle(.titleLarge)
                    .foregroundStyle(Palette.title)
                Spacer().frame(height: 4)
                Text(game.blurb)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .multilineTextAlignment(.leading)
                Spacer().frame(height: 10)
                if let packsLabel {
                    Pill(text: packsLabel, background: Palette.gold, color: Palette.ink)
                        .anchorPreference(key: PillBounds.self, value: .bounds) { $0 }
                        .accessibilityHidden(true)      // the button on top says it
                    Spacer().frame(height: 8)
                }
                HStack(spacing: 0) {
                    if !game.free.isEmpty {
                        Pill(text: game.free.uppercased(), background: Palette.headerLine, color: Palette.ink)
                    }
                    Spacer(minLength: 0)
                    Pill(text: continuing ? "CARRY ON" : "PLAY", background: Palette.yes, color: .white, big: true)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(Self.shape)
        .contentShape(Self.shape)
    }
}

/// A band across the middle of its rect, [height] tall: the packs pill's pressed shade, in its larger touch area.
private struct Band: Shape {
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
    }
}

/// Where the packs pill is drawn on its card, for the button on top of it.
nonisolated private struct PillBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A game loading: the screen dimmed, with Material's spinning ring. It takes the touches meant for what's under it
/// (L8), and VoiceOver stays in it.
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            RingSpinner()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.isModal)
    }
}
