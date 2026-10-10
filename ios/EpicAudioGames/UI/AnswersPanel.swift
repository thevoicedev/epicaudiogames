// ui/GameScreen.kt's AnswerBar, AnswerField and MicButton: the text box, Send and the mic. The options are chips in
// the feed.

import EpicAppCore
import SwiftUI
import UIKit

/**
 * The bar under the transcript: the text box, Send and the mic. Saying or typing is the main way to answer. In the
 * [compact] layout (accessibility text sizes) the text box has a row of its own, and Send and the mic show their words
 * under it. GameScreen.kt's AnswerBar.
 */
struct AnswersPanel: View {
    let game: GameController
    let compact: Bool
    /// What's typed: GameView's, so it stays as an iPad's window changes between one pane and two (this panel is made
    /// again in the other layout).
    @Binding var text: String
    /// The answer box has the keys, as GameView's keyboard needs to know (Space types there, rather than skipping).
    @Binding var typing: Bool
    /// The mic tapped (GameView: listen, ask for the mic, or say it's off).
    let onTalk: @MainActor () -> Void
    @FocusState private var focused: Bool
    @Environment(\.epicColors) private var c
    @Environment(\.epicType) private var type

    var body: some View {
        VStack(spacing: 0) {
            c.outlineSubtle.frame(height: c.edgeWidth)
            Group {
                if compact {
                    VStack(spacing: 8) {
                        field
                        // Side by side while their words fit on one line each; the mic's longer names ("Talk (the
                        // microphone is off)") at the largest text don't, and then each has a row of its own, so no
                        // word is broken (GameScreen.kt's SharedRow).
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { sendAndTalk }
                            VStack(spacing: 8) { sendAndTalk }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        field
                        IconActionButton(icon: .send, description: "Send", action: send)
                            .accessibilityIdentifier("send")
                        MicButton(game: game, words: false, onTap: onTalk)
                    }
                }
            }
            .padding(12)
            .readableWidth()
        }
        .background { c.surfaceRaised.ignoresSafeArea(.container, edges: .bottom) }
        // Typing is the answer coming: the mic doesn't open by itself meanwhile.
        .onChange(of: focused) { _, now in
            game.typing = now
            typing = now
        }
        .onChange(of: text) { game.typed() }
        // Paused, the keyboard goes away: what's typed waits for the tap that carries on.
        .onChange(of: game.paused) { _, paused in
            if paused { focused = false }
        }
        .onDisappear {
            game.typing = false
            typing = false
        }
    }

    /**
     * The text box, labelled "Type an answer" (its name for VoiceOver and Voice Control, and its placeholder). Its 2 pt
     * outline turns into the 3 pt focus colour while it's being typed in. It's one line: what's typed scrolls sideways.
     */
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return TextField(
            "Type an answer", text: $text,
            prompt: Text("Type an answer").font(type.font(.body)).foregroundStyle(c.textMuted)
        )
        .epicFont(.body)
        .foregroundStyle(c.text)
        .tint(c.text)
        .textInputAutocapitalization(.never)
        .submitLabel(.send)
        .focused($focused)
        .accessibilityIdentifier("answer-field")
        .onSubmit {
            send()
            // The keyboard stays up for the next answer, as Android's does; not over a pause ("stop" typed).
            guard !game.paused else {
                focused = false
                return
            }
            focused = true
            DispatchQueue.main.async { if !game.paused { focused = true } }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(c.surface, in: shape)
        .overlay { shape.strokeBorder(focused ? c.focus : c.outline, lineWidth: focused ? 3 : 2) }
        .frame(maxWidth: .infinity)
    }

    /// The compact layout's Send and the mic, with their words.
    @ViewBuilder private var sendAndTalk: some View {
        EpicButton("Send", kind: .secondary, icon: .send, wide: true, action: send)
            .accessibilityIdentifier("send")
        MicButton(game: game, words: true, onTap: onTalk)
    }

    /// Sends what's typed (if anything), and empties the box either way.
    private func send() {
        if !Kt.trim(text).isEmpty { game.answer(text) }
        text = ""
    }
}

/**
 * The mic: 56 pt, primary; while listening, the listening colour with a stop icon; with the mic refused or no speech
 * recognition, outlined, with a crossed-out mic. Not allowed, a tap asks for the mic while iOS still can, and else
 * says it's off, with the way to Settings (GameView). Named as the circle's way to talk: Talk, Stop listening, or why
 * it can't ([CircleAction.mic]). With [words] (the compact layout), a wide button showing that name.
 * GameScreen.kt's MicButton.
 */
private struct MicButton: View {
    let game: GameController
    let words: Bool
    let onTap: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    var body: some View {
        let canTalk = game.micAllowed && game.micWorks
        let talk = CircleAction.mic(listening: game.listening, micAllowed: game.micAllowed, micWorks: game.micWorks)
        // On the listening colour, the background's colour (dark on a light green, light on a dark one).
        let tint = game.listening ? c.background : canTalk ? c.onPrimary : c.text
        let fill = game.listening ? c.ringListening : canTalk ? c.primary : c.surface
        let outlined = !game.listening && !canTalk
        let icon = game.listening ? MaterialIcon.stop : canTalk ? MaterialIcon.mic : MaterialIcon.micOffOutlined
        Button(action: onTap) {
            if words {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                HStack(spacing: 8) {
                    IconView(icon: icon, size: 24, color: tint)
                    Text(talk.label)
                        .epicFont(.label)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(fill, in: shape)
                .overlay { if outlined { shape.strokeBorder(c.outline, lineWidth: 2) } }
                .contentShape(shape)
            } else {
                IconView(icon: icon, size: 28, color: tint)
                    .frame(width: 56, height: 56)
                    .background(fill, in: Circle())
                    .overlay { if outlined { Circle().strokeBorder(c.outline, lineWidth: 2) } }
                    .contentShape(Circle())
            }
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
        .accessibilityLabel(talk.label)
        // VoiceOver says nothing after the tap: the mic is listening.
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityInputLabels(A11y.inputLabels(talk.label, "Talk", "Microphone", "Mic"))
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
