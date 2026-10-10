// ui/HomeScreen.kt: Games, its heading, how to play in a line, and a card per game with its cover and its packs.

import EpicAppCore
import SwiftUI

/**
 * Games: its heading, how to play in a line, and a card per game: one column, at most 640 pt wide, or on an expanded
 * window (a 13-inch iPad, an iPad on its side, a wide Mac window) two, each at most [cardMaxWidth] (docs/DESIGN.md ›
 * Tablets…). Centred, the whole width scrolls. [scroll] is kept by the app's model, so the list is where it was after
 * a game, in either layout (by the game at its top). [installs]: read, so the cards show a pack installed.
 *
 * With [focusHeading] (the intro or onboarding just ended: docs/DESIGN.md › Everywhere › Focus), VoiceOver moves to the
 * heading a moment after it shows; [onHeadingFocused] says it's done, so it isn't done again. Android: HomeScreen.kt.
 */
struct HomeView: View {
    let games: [GameInfo]
    let continuing: Set<String>
    let installs: Int
    let installed: (PackInfo) -> Bool
    @Binding var scroll: String?
    let onOpen: @MainActor (GameInfo) -> Void
    let onStore: @MainActor (GameInfo) -> Void
    var focusHeading = false
    var onHeadingFocused: @MainActor () -> Void = {}
    #if DEBUG
    /// Debug builds: a long press on the heading opens the Audio Lab.
    var onLab: (@MainActor () -> Void)?
    #endif
    @Environment(\.epicWindow) private var window
    @Environment(\.epicColors) private var c

    /// The widest a game's card gets, two to a row on an expanded window.
    static let cardMaxWidth: CGFloat = 480

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onAppear {
                    // The first card at the top is the list's top: its heading shows too.
                    guard let scroll else { return }
                    proxy.scrollTo(scroll == games.first?.id ? Self.top : scroll, anchor: .top)
                }
        }
        .background { c.background.ignoresSafeArea() }
    }

    private var list: some View {
        ScrollView {
            if window.widthClass == .expanded {
                grid
            } else {
                column
            }
        }
        .scrollPosition(id: $scroll, anchor: .top)
        // Compose's LazyColumn draws no scroll bar.
        .scrollIndicators(.hidden)
        // The status bar's strip is the background's too, so the list never scrolls under its icons (as Android's):
        // a line with no height over the list's top, its background reaching up into the safe area.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(c.background)
        }
    }

    /// A phone's (and a medium window's) list: the heading, then the cards, one under another.
    private var column: some View {
        LazyVStack(spacing: 16) {
            heading
                .readableWidth()
                .id(Self.top)
            ForEach(games) { game in
                card(game)
                    .readableWidth()
            }
        }
        .scrollTargetLayout()
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
    }

    /// An expanded window's: the heading over the whole grid (its words still at most 640 pt wide), then the cards two
    /// to a row, each at most [cardMaxWidth], the rows' tops in line. VoiceOver reads the cards row by row.
    private var grid: some View {
        let columns = [
            GridItem(.flexible(maximum: Self.cardMaxWidth), spacing: 16, alignment: .top),
            GridItem(.flexible(maximum: Self.cardMaxWidth), alignment: .top),
        ]
        return LazyVGrid(columns: columns, spacing: 16) {
            Section {
                ForEach(games) { game in
                    card(game)
                }
            } header: {
                heading
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(Self.top)
            }
        }
        .scrollTargetLayout()
        .frame(maxWidth: 2 * Self.cardMaxWidth + 16)
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
        .frame(maxWidth: .infinity)
    }

    private func card(_ game: GameInfo) -> some View {
        GameCard(
            game: game, continuing: continuing.contains(game.id), installed: installed,
            onStore: { onStore(game) }, onOpen: { onOpen(game) })
    }

    /// The heading and the line under it, as a place in the list.
    static let top = "top"

    private var heading: some View {
        // A request for VoiceOver to come here, while it's asked for.
        let focus: Bool? = focusHeading ? true : nil
        return VStack(alignment: .leading, spacing: 8) {
            #if DEBUG
            ScreenHeader("Games")
                .accessibilityIdentifier("games-heading")
                .focusWhen(focus, then: onHeadingFocused)
                .onLongPressGesture { onLab?() }
            #else
            ScreenHeader("Games")
                .accessibilityIdentifier("games-heading")
                .focusWhen(focus, then: onHeadingFocused)
            #endif
            Text("Put on your headphones, listen, and answer out loud.")
                .epicFont(.body)
                .foregroundStyle(c.text)
        }
    }
}

/**
 * A game's card, with two things to do. The card itself (its cover, title, blurb, what's free, "In progress", and
 * "Play ›" or "Carry on ›") opens the game: VoiceOver reads it as one button, "The Werewolf. In progress. … 5 stories
 * free. Carry on.", with "More stories and levels" in its actions while a pack is still to get; Voice Control knows it
 * by its title and "Play <title>". Under it, its own button gets that pack: "Get 45 more mysteries" (for VoiceOver,
 * "… for The Werewolf"), or with every pack in, the words "All packs installed". HomeScreen.kt's GameCard.
 */
private struct GameCard: View {
    let game: GameInfo
    let continuing: Bool
    let installed: (PackInfo) -> Bool
    let onStore: @MainActor () -> Void
    let onOpen: @MainActor () -> Void
    @Environment(\.epicColors) private var c
    @Environment(\.epicType) private var type

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        let action = continuing ? "Carry on" : "Play"
        let toGet = game.packs.first { !installed($0) }
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) { face(action) }
                .buttonStyle(RippleStyle(shape: Rectangle()))
                .hoverEffect()
                .accessibilityLabel(
                    sentences(game.title, continuing ? "In progress" : nil, game.blurb, game.free, action))
                .accessibilityInputLabels(
                    A11y.inputLabels(game.title, "\(action) \(game.title)", "Play \(game.title)"))
                .accessibilityActions {
                    if toGet != nil { Button("More stories and levels", action: onStore) }
                }
                .accessibilityIdentifier("game-\(game.id)")
            if !game.packs.isEmpty {
                c.outlineSubtle.frame(height: c.edgeWidth)
                if let toGet {
                    EpicButton(
                        "Get \(toGet.title)", kind: .secondary, icon: .add,
                        description: "Get \(toGet.title) for \(game.title)", wide: true, action: onStore)
                        .accessibilityIdentifier("packs-\(game.id)")
                        .padding(16)
                } else {
                    HStack(spacing: 8) {
                        IconView(icon: .checkCircle, size: 24, color: c.success)
                        Text("All packs installed")
                            .epicFont(.body)
                            .foregroundStyle(c.text)
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface)
        .clipShape(Self.shape)
        .overlay { Self.shape.strokeBorder(c.outlineSubtle, lineWidth: c.edgeWidth) }
    }

    /// What the card shows: its cover (not at accessibility text sizes, where the words need the room more), "In
    /// progress", the title, blurb and what's free, and what a tap does, as words that look like the button it is.
    private func face(_ action: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !type.isAccessibilitySize {
                CoverFrame {
                    if let cover = Covers.image(game.id) {
                        Image(uiImage: cover).resizable().scaledToFill()
                    } else {
                        c.surfaceRaised
                    }
                }
                .clipped()
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                if continuing { Badge(text: "In progress", icon: .bookmark) }
                Text(game.title)
                    .epicFont(.itemTitle)
                    .foregroundStyle(c.text)
                if !Kt.trim(game.blurb).isEmpty {
                    Text(game.blurb)
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                }
                if !Kt.trim(game.free).isEmpty {
                    Text(game.free)
                        .epicFont(.secondary)
                        .foregroundStyle(c.textMuted)
                }
                HStack(spacing: 4) {
                    Text(action)
                        .epicFont(.label)
                        .foregroundStyle(c.onPrimary)
                    IconView(icon: .keyboardArrowRight, size: 24, color: c.onPrimary)
                }
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
                .background(c.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A game's cover: as wide as the card and 9/16 of that tall, at most 180 pt (cropped on a wide screen).
private struct CoverFrame: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: width, height: min(width * 9 / 16, 180))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Parts read as sentences, one after another: each gets a full stop unless it ends a sentence already (HomeScreen.kt's
/// sentences).
nonisolated func sentences(_ parts: String?...) -> String {
    parts.compactMap { $0 }.map { Kt.trim($0) }.filter { !$0.isEmpty }
        .map { part in part.last.map { ".!?…".contains($0) } == true ? part : part + "." }
        .joined(separator: " ")
}

/**
 * A game loading, over what was there (the scrim hides it, solid as docs/DESIGN.md › Colour asks): a spinner and
 * "Opening The Werewolf", which VoiceOver hears as it appears. It takes the touches meant for what's under it (L8),
 * and VoiceOver stays in it. MainActivity.kt's Opening.
 */
struct LoadingOverlay: View {
    let title: String
    @Environment(\.epicColors) private var c

    var body: some View {
        ZStack {
            c.scrim
            VStack(spacing: 16) {
                RingSpinner(color: c.primary)
                Text("Opening \(title)")
                    .epicFont(.label)
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening \(title)")
        .accessibilityAddTraits(.isModal)
        // No game is open yet, so no mic is listening.
        .onAppear { A11y.announce("Opening \(title)", unlessListening: false) }
    }
}
