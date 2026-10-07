// ui/GameScreen.kt's Answers (lines 245-310): the text box, Send and the mic. The options are chips in the feed.

import EpicAppCore
import SwiftUI
import UIKit

/// The bar under the transcript: the text box, Send and the mic. Saying or typing is the main way to answer.
struct AnswersPanel: View {
    let game: GameController
    /// The mic tapped (GameView: listen, ask for the mic, or say it's off).
    let onTalk: () -> Void
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField(
                "", text: $text,
                prompt: Text("Type an answer").font(Typography.bodyLarge.font).foregroundStyle(Palette.placeholder)
            )
            .font(Typography.bodyLarge.font)
            .foregroundStyle(Palette.ink)
            .tint(Palette.choice)
            .textInputAutocapitalization(.never)
            .submitLabel(.send)
            .focused($typing)
            .accessibilityIdentifier("answer-field")
            .onSubmit {
                send()
                // The keyboard stays up for the next answer, as Android's does; not over a pause ("stop" typed).
                guard !game.paused else {
                    typing = false
                    return
                }
                typing = true
                DispatchQueue.main.async { if !game.paused { typing = true } }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .circular))
            .frame(maxWidth: .infinity)
            // Ink, as white is too faint on the bar.
            Button(action: send) {
                IconView(icon: .send, color: Palette.ink)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("send")
            MicButton(game: game, onTap: onTalk)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.22).ignoresSafeArea(.container, edges: .bottom))
        // Typing is the answer coming: the mic doesn't open by itself meanwhile.
        .onChange(of: typing) { _, now in game.typing = now }
        .onChange(of: text) { game.typed() }
        // Paused, the keyboard goes away: what's typed waits for the tap that carries on.
        .onChange(of: game.paused) { _, paused in
            if paused { typing = false }
        }
        .onDisappear { game.typing = false }
    }

    /// Sends what's typed (if anything), and empties the box either way.
    private func send() {
        if !Kt.trim(text).isEmpty { game.answer(text) }
        text = ""
    }
}

/**
 * The mic: green while listening, blue when it can listen, grey (and crossed out) when it can't. Not allowed, a tap
 * asks for the mic while iOS still can, and else says it's off, with the way to Settings (GameView).
 */
private struct MicButton: View {
    let game: GameController
    let onTap: () -> Void

    var body: some View {
        let canTalk = game.micAllowed && game.micWorks
        Button(action: onTap) {
            // Ink on the listening green, as white is too faint there.
            IconView(icon: canTalk ? .mic : .micOff, size: 28, color: game.listening ? Palette.ink : .white)
                .frame(width: 54, height: 54)
                .background(game.listening ? Palette.listen : canTalk ? Palette.choice : Palette.gray, in: Circle())
                .contentShape(Circle())
        }
        // Compose's clickable: a ripple, clipped to the circle.
        .buttonStyle(RippleStyle(shape: Circle()))
        .accessibilityLabel(game.listening ? "Stop listening" : canTalk ? "Talk" : "Talk (the microphone is off)")
        // VoiceOver says nothing after the tap: the mic is listening.
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityIdentifier("mic")
    }
}

/**
 * Compose's verticalScroll on the end panel: as tall as its content, scrolling when the screen has less room than
 * that (a small phone, large text). GameView gives it its room before the transcript's, as Compose's Column measures
 * the panels before the weighted feed.
 */
struct PanelScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        UpToContentHeight {
            ScrollView(.vertical) {
                content()
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // The transcript is what puts the keyboard away.
            .scrollDismissesKeyboard(.never)
        }
    }
}

/// Its one subview as tall as it would like to be, but no taller than the height it's offered.
struct UpToContentHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let height = proposal.height.map { min($0, ideal.height) } ?? ideal.height
        return CGSize(width: proposal.width ?? ideal.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
