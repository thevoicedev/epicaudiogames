// ui/GameScreen.kt's Feed, Spoken, transcriptText and Reply: the transcript as it's spoken, and the answer chips.

import EpicAppCore
import SwiftUI
import UIKit

/**
 * The transcript, kept at its newest words, with the question's options (the chips) at its end. It scrolls to its
 * end whenever what's in it changes size (an entry comes, an entry grows as a line joins it, the chips come or go),
 * as the room for it shrinks (the keyboard, the end panel), as it grows while the keyboard goes away, and when the
 * scrolling that put the keyboard away stops, each time once laid out, so the end of a tall entry shows too (at once
 * with Reduce Motion). Its rows aren't lazy: a lazy stack scrolled to its end before its rows were measured stopped
 * short, or drew nothing. In the [compact] layout, the game's title is its first line.
 *
 * With VoiceOver on, it keeps still, so nothing moves under the player's finger: VoiceOver moves through the lines
 * itself. It scrolls to its end only when the chips, a reply or the end panel appear (docs/DESIGN.md › Game ›
 * Transcript; GameScreen.kt's Feed does the same with TalkBack). [showChips] false: the chips are in the other pane
 * (GameView's wide layout).
 */
struct FeedView: View {
    let game: GameController
    let compact: Bool
    var showChips = true
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
    /// The phone's Reduce Motion, or Settings' (EpicTheme).
    @Environment(\.epicReduceMotion) private var reduceMotion
    /// VoiceOver is on (as it changes): the transcript keeps still for it.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.epicColors) private var c

    var body: some View {
        let feed = game.feed
        let chips = game.end == nil ? game.ask?.buttons ?? [] : []
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        if compact {
                            // The screen's title, here rather than in the header: still its level-1 heading.
                            Text(game.info.title)
                                .epicFont(.itemTitle)
                                .foregroundStyle(c.heading)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityHeading(.h1)
                                .readableWidth()
                        }
                        ForEach(Array(feed.enumerated()), id: \.element.id) { i, item in
                            FeedRow(game: game, index: i, item: item)
                        }
                        if showChips && !chips.isEmpty {
                            AnswerChips(game: game, buttons: chips)
                                .readableWidth()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { _ in
                        follow(proxy, animated: true)
                    }
                    Color.clear.frame(height: 0).id(Self.bottom)
                }
            }
            // Held at its end as it grows; with VoiceOver, where the player left it.
            .defaultScrollAnchor(voiceOver ? nil : UnitPoint.bottom)
            .accessibilityIdentifier("feed")
            // Dragging the transcript down into the keyboard puts it away (Android's Back); a tap or a send doesn't.
            .scrollDismissesKeyboard(.interactively)
            // Compose's LazyColumn draws no scroll bar.
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { now in
                let shrank = now < height
                height = now
                if voiceOver {
                    // The end panel takes room from the feed: once that's laid out, its end again.
                    if game.end != nil { toEnd(proxy, animated: false) }
                } else if shrank || keyboardLeaving {
                    toEnd(proxy, animated: false)
                }
            }
            // With VoiceOver, what the player needs next coming: the question's options, a reply, the end panel.
            .onChange(of: chips) { _, now in
                if voiceOver && !now.isEmpty { toEnd(proxy, animated: true) }
            }
            .onChange(of: Self.replies(feed)) { _, now in
                if voiceOver && now > 0 { toEnd(proxy, animated: true) }
            }
            .onChange(of: game.end != nil) { _, ending in
                if voiceOver && ending { toEnd(proxy, animated: true) }
            }
            // The keyboard put away, once the drag that did it is over: the newest words again (Android scrolls so
            // as its Back puts the keyboard away).
            .modifier(ScrollPhaseWatch(scrolling: $scrolling) {
                if endAfterScroll {
                    endAfterScroll = false
                    follow(proxy, animated: true)
                }
            })
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardLeaving = true
                if scrolling { endAfterScroll = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                if scrolling { endAfterScroll = true } else { follow(proxy, animated: true) }
                // iOS 17 can't tell when a scroll stops: by now the drag that put the keyboard away is usually over.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    keyboardLeaving = false
                    if !scrolling { follow(proxy, animated: false) }
                }
            }
        }
    }

    /// How many replies the feed has: one more is an answer given.
    private static func replies(_ feed: [FeedItem]) -> Int {
        feed.filter { if case .reply = $0.kind { true } else { false } }.count
    }

    /// The newest words kept in view: to the feed's end, unless VoiceOver is on (then it keeps still).
    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        if !voiceOver { toEnd(proxy, animated: animated) }
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
    @Environment(\.epicColors) private var c

    var body: some View {
        switch item.kind {
        case .spoken(let who, let name, let text):
            SpokenBubble(
                who: who, name: name, text: text, readAs: item.readAs,
                said: game.activeEntry == index ? game.activeChars : nil)
        case .reply(let text):
            ReplyBubble(text: text, readAs: item.readAs)
        case .note(let text):
            // "Welcome back!", "Starting again!": centred, in the secondary style.
            Text(text)
                .epicFont(.secondary)
                .foregroundStyle(c.textMuted)
                .multilineTextAlignment(.center)
                .padding(.vertical, 2)
                .readableWidth(alignment: .center)
        }
    }
}

/**
 * A line of the game: its speaker's name in bold above a bubble (not for the narrator, nor with Settings › Show who's
 * speaking off), the words in the transcript style. The line being spoken has an accent bar on its leading edge and an
 * accent border, and its current word is highlighted ([transcriptText]). VoiceOver reads it as one element, its
 * speaker first whether the name shows or not (FeedItem.readAs), and isn't told of it as it comes: the game is already
 * saying it. GameScreen.kt's Spoken.
 */
private struct SpokenBubble: View {
    let who: String
    let name: String
    let text: String
    /// What VoiceOver says for it, its speaker first (FeedItem.readAs).
    let readAs: String
    /// How many of its characters have been said (UTF-16 units), while it's being spoken.
    let said: Int?
    /// Settings › Transcript (EpicTheme puts them here); without them, their defaults.
    @Environment(AppSettings.self) private var settings: AppSettings?
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    /// The current line's bar, down its leading edge (the right, in a right-to-left language).
    private static let bar: CGFloat = 4

    var body: some View {
        let current = said != nil
        VStack(alignment: .leading, spacing: 4) {
            if settings?.speakerNames ?? true, !Kt.trim(name).isEmpty, who != "NARRATOR" {
                Text(name)
                    .epicFont(.speaker)
                    .foregroundStyle(c.text)
            }
            WrappedWidth {
                Text(transcriptText(
                    text, saidChars: said, highlight: settings?.highlightWords ?? true,
                    wholeLine: settings?.wholeLine ?? true, colors: c))
                    .epicFont(.transcript)
                    .foregroundStyle(c.text)
            }
            // Room for the bar on every line, so the words don't shift as a line stops being the current one.
            .padding(.leading, Self.bar + 14)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background(c.surface)
            .overlay(alignment: .leading) {
                if current { c.accent.frame(width: Self.bar) }
            }
            .clipShape(Self.shape)
            .overlay {
                Self.shape.strokeBorder(current ? c.accent : c.outlineSubtle, lineWidth: current ? 2 : c.edgeWidth)
            }
        }
        .padding(.trailing, 32)
        // One element for VoiceOver, its speaker first ("Gribbo: …"). Not announced as it comes: the voice says it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readAs)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("spoken")
        .readableWidth()
    }
}

/**
 * A line's words. Not being spoken ([saidChars] nil), as they are. Being spoken: the word the voice is on in inverse
 * colours (if [highlight]), and the words still to come at full strength ([wholeLine]) or hidden: clear, so they keep
 * their place and nothing moves as they're said. Never faded: pale words were hard to read. GameScreen.kt's
 * transcriptText; the word is EpicAppCore's Transcript.currentWord.
 */
func transcriptText(
    _ text: String, saidChars: Int?, highlight: Bool, wholeLine: Bool, colors: EpicColors
) -> AttributedString {
    guard let saidChars else { return AttributedString(text) }
    let cut = Transcript.currentWord(text, saidChars: saidChars)
    var word = AttributedString(cut.word)
    if highlight {
        word.foregroundColor = colors.highlightText
        word.backgroundColor = colors.highlightBg
    }
    var after = AttributedString(cut.after)
    if !wholeLine { after.foregroundColor = Color.clear }
    return AttributedString(cut.before) + word + after
}

/// What the player said, typed or tapped, at the right under "You". VoiceOver reads it "You said: …" (FeedItem.readAs).
/// GameScreen.kt's Reply.
private struct ReplyBubble: View {
    let text: String
    let readAs: String
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("You")
                .epicFont(.speaker)
                .foregroundStyle(c.text)
            WrappedWidth {
                Text(text)
                    .epicFont(.transcript)
                    .foregroundStyle(c.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(c.replySurface, in: Self.shape)
            .overlay { Self.shape.strokeBorder(c.replyEdge, lineWidth: c.edgeWidth) }
        }
        .padding(.leading, 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readAs)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("reply")
        .readableWidth(alignment: .trailing)
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
