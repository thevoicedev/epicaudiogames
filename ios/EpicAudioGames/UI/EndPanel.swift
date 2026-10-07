// ui/GameScreen.kt's EndPanel and EndButton (lines 330-379): the end, what was reached, and what next.

import EpicAppCore
import SwiftUI

/// The end: what was reached, and what next. With less room than it needs, it scrolls.
struct EndPanel: View {
    let game: GameController
    let onStore: () -> Void

    var body: some View {
        if let end = game.end {
            PanelScroll {
                panel(end)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .circular))
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .circular)
                    .fill(Palette.card)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("end-panel")
        }
    }

    private func panel(_ end: End) -> some View {
        VStack(spacing: 10) {
            // It stops growing at the second accessibility size: larger, CHAPTER COMPLETE! has no room to break.
            OutlinedText(heading(end), size: 30, fill: Palette.goldUI, maxLines: 2, alignment: .center, isHeader: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            Text(end.title)
                .textStyle(.titleLarge)
                .foregroundStyle(Palette.title)
                .multilineTextAlignment(.center)
            let canGoOn = game.canGoOn
            if end.locked != nil && !canGoOn {
                if let pack = game.info.packs.first(where: { $0.id == end.locked }) {
                    let more = end.kind == "chapter"
                        ? "What happens next is in \(pack.title)." : "There's more: \(pack.title)."
                    Text(more)
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    // Dark text on the gold: white is too faint there.
                    FilledButton(label: "GET \(pack.title.uppercased())", color: Palette.gold, text: Palette.ink,
                                 action: onStore)
                } else {
                    Text("What happens next is coming soon, in a story pack.")
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                }
            }
            if canGoOn {
                FilledButton(label: "NEXT CHAPTER", color: Palette.yes) { game.nextChapter() }
            }
            FilledButton(label: end.kind == "gameover" ? "TRY AGAIN" : "PLAY AGAIN", color: Palette.choice) {
                game.playAgain()
            }
            FilledButton(label: "BACK TO GAMES", color: Palette.headerBottom) { game.leave() }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
    }

    private func heading(_ end: End) -> String {
        switch end.kind {
        case "chapter": "CHAPTER COMPLETE!"
        case "gameover": "GAME OVER"
        default: "THE END"
        }
    }
}
