// ui/GameScreen.kt's EndPanel: the end, what was reached, and what next.

import EpicAppCore
import SwiftUI

/**
 * The end: what was reached, and what next, on the raised surface. With less room than it needs, it scrolls (the text
 * grows as far as the phone's text size goes). VoiceOver moves to its heading a moment after it appears (Android's
 * pane is named by the heading, which takes TalkBack's focus the same way). GameScreen.kt's EndPanel.
 */
struct EndPanel: View {
    let game: GameController
    let onStore: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)

    var body: some View {
        if let end = game.end {
            PanelScroll {
                panel(end)
            }
            .clipShape(Self.shape)
            .frame(maxWidth: .infinity)
            .background {
                // Its edge round its top and down its sides: the stroke's outer half and its bottom are cut off, so
                // what shows is the edge's width, inside the panel.
                ZStack {
                    Self.shape.fill(c.surfaceRaised)
                    Self.shape
                        .stroke(c.outlineSubtle, lineWidth: 2 * c.edgeWidth)
                        .padding(.bottom, -4 * c.edgeWidth)
                }
                .clipShape(Self.shape)
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("end-panel")
        }
    }

    private func panel(_ end: End) -> some View {
        VStack(spacing: 12) {
            PaneHeading(text: end.heading, key: end)
                .accessibilityIdentifier("end-heading")
            Text(end.title)
                .epicFont(.itemTitle)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            let canGoOn = game.canGoOn
            if end.locked != nil && !canGoOn {
                if let pack = game.info.packs.first(where: { $0.id == end.locked }) {
                    let more = end.kind == "chapter"
                        ? "What happens next is in \(pack.title)." : "There's more: \(pack.title)."
                    Text(more)
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)
                    EpicButton("Get \(pack.title)", wide: true, action: onStore)
                        .accessibilityIdentifier("end-get")
                } else {
                    Text("What happens next is coming soon, in a story pack.")
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)
                }
            }
            if canGoOn {
                EpicButton("Next chapter", wide: true) { game.nextChapter() }
                    .accessibilityIdentifier("end-next")
            }
            EpicButton(end.kind == "gameover" ? "Try again" : "Play again", kind: .secondary, wide: true) {
                game.playAgain()
            }
            .accessibilityIdentifier("end-again")
            EpicButton("Back to games", kind: .secondary, wide: true) { game.leave() }
                .accessibilityIdentifier("end-back")
        }
        .padding(20)
        .readableWidth(alignment: .center)
    }
}

extension End {
    /// The end panel's heading, in sentence case as everywhere (docs/DESIGN.md › Principles); the watch shows it too
    /// (WatchBridge).
    var heading: String {
        switch kind {
        case "chapter": "Chapter complete"
        case "gameover": "Game over"
        default: "The end"
        }
    }
}
