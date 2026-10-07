// ui/GameScreen.kt's Feed, Spoken and Reply (lines 181-243): the transcript as it's spoken, and the answer chips.

import EpicAppCore
import SwiftUI
import UIKit

/**
 * The transcript, kept at its newest words, with the question's options (the chips) at its end. It scrolls to its
 * end whenever what's in it changes size (an entry comes, an entry grows as a line joins it, the chips come or go),
 * as the room for it shrinks (the keyboard, the end panel), as it grows while the keyboard goes away, and when the
 * scrolling that put the keyboard away stops, each time once laid out, so the end of a tall entry shows too.
 * Its rows aren't lazy: a lazy stack scrolled to its end before its rows were measured stopped short, or drew nothing.
 */
struct FeedView: View {
    let game: GameController
    /// The feed's end, under the chips: what it scrolls to.
    private static let bottom = "feed-end"
    /// How tall the feed is: only less room (the keyboard coming up, the end panel) scrolls it, so a drag putting
    /// the keyboard away isn't cut short.
    @State private var height: CGFloat = 0
    /// The keyboard is going away: the feed follows it as it grows, until a moment after it's gone (the room can
    /// still be growing when the keyboard says it's hidden).
    @State private var keyboardLeaving = false
    /// The player is scrolling the transcript (a drag, or what's left of it). A scroll asked for meanwhile is lost,
    /// so when a drag puts the keyboard away the feed goes back to its end once the scrolling stops.
    @State private var scrolling = false
    @State private var endAfterScroll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let feed = game.feed
        let chips = game.end == nil ? game.ask?.buttons ?? [] : []
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(feed.enumerated()), id: \.element.id) { i, item in
                            FeedRow(game: game, index: i, item: item)
                        }
                        if !chips.isEmpty {
                            AnswerChips(game: game, buttons: chips)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { _ in
                        toEnd(proxy, animated: true)
                    }
                    Color.clear.frame(height: 0).id(Self.bottom)
                }
            }
            .defaultScrollAnchor(.bottom)
            .accessibilityIdentifier("feed")
            // Dragging the transcript down into the keyboard puts it away (Android's Back); a tap or a send doesn't.
            .scrollDismissesKeyboard(.interactively)
            // Compose's LazyColumn draws no scroll bar.
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { now in
                let shrank = now < height
                height = now
                if shrank || keyboardLeaving { toEnd(proxy, animated: false) }
            }
            // The keyboard put away, once the drag that did it is over: the newest words again (Android scrolls so
            // as its Back puts the keyboard away).
            .modifier(ScrollPhaseWatch(scrolling: $scrolling) {
                if endAfterScroll {
                    endAfterScroll = false
                    toEnd(proxy, animated: true)
                }
            })
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardLeaving = true
                if scrolling { endAfterScroll = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                if scrolling { endAfterScroll = true } else { toEnd(proxy, animated: true) }
                // iOS 17 can't tell when a scroll stops: by now the drag that put the keyboard away is usually over.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    keyboardLeaving = false
                    if !scrolling { toEnd(proxy, animated: false) }
                }
            }
        }
    }

    /// Scrolls to the feed's end once this layout is done (scrolled during it, it can land short of the end).
    private func toEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !game.feed.isEmpty || game.ask != nil else { return }
        let animation: Animation? = animated && !reduceMotion ? .easeOut(duration: 0.25) : nil
        DispatchQueue.main.async {
            withAnimation(animation) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }
}

/// Whether the player is scrolling, and a call when the scrolling stops (iOS 18's scroll phases; iOS 17 has none).
private struct ScrollPhaseWatch: ViewModifier {
    @Binding var scrolling: Bool
    let stopped: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                scrolling = phase.isScrolling
                if phase == .idle { stopped() }
            }
        } else {
            content
        }
    }
}

/// One entry. Only the entry being spoken reads how much of it has been said, so the highlight redraws it alone.
private struct FeedRow: View {
    let game: GameController
    let index: Int
    let item: FeedItem

    var body: some View {
        switch item.kind {
        case .spoken(let who, let name, let text):
            SpokenBubble(who: who, name: name, text: text, said: game.activeEntry == index ? game.activeChars : nil)
        case .reply(let text):
            ReplyBubble(text: text)
        case .note(let text):
            OutlinedText(text, size: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }
}

/// A line of the game. While it's being spoken, the words still to come are paler.
private struct SpokenBubble: View {
    let who: String
    let name: String
    let text: String
    /// How many of its characters have been said (UTF-16 units), while it's being spoken.
    let said: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !Kt.trim(name).isEmpty && who != "NARRATOR" {
                Text(name.uppercased())
                    .font(Lilita.font(13, relativeTo: .caption))
                    .foregroundStyle(speakerColor(who))
            }
            WrappedWidth {
                Text(attributed)
                    .textStyle(.bodyLarge)
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Palette.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 4, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18,
                style: .circular))
        // One element for VoiceOver, its speaker first ("Gribbo: …"). Not announced as it comes: the voice says it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Kt.trim(name).isEmpty || who == "NARRATOR" ? text : "\(name): \(text)")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("spoken")
        .frame(maxWidth: 340, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        guard let said else { return AttributedString(text) }
        let parts = Transcript.highlight(text, saidChars: said)
        var rest = AttributedString(parts.rest)
        rest.foregroundColor = Palette.ink.opacity(0.35)
        return AttributedString(parts.said) + rest
    }
}

/// What the player said, typed or tapped.
private struct ReplyBubble: View {
    let text: String

    var body: some View {
        WrappedWidth {
            Text(text)
                .textStyle(.bodyLarge)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Palette.reply,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 4,
                style: .circular))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You said: \(text)")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("reply")
        .frame(maxWidth: 300, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/**
 * Compose's Text width: as wide as its text on one line, but once the text wraps, the whole width it may have
 * (Compose lays a wrapped paragraph out at its maximum width; a SwiftUI Text hugs its widest line). So the bubbles of
 * more than one line share a straight right edge, as on Android.
 */
struct WrappedWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let oneLine = text.sizeThatFits(.unspecified)
        guard let width = proposal.width, width.isFinite, oneLine.width > width else {
            return text.sizeThatFits(proposal)
        }
        return CGSize(width: width, height: text.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
