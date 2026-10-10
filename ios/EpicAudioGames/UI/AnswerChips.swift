// ui/GameScreen.kt's Options and Chip: the question's options, as quick replies at the end of the chat.

import EpicAppCore
import SwiftUI

/**
 * The question's options (its buttons), as chips at the feed's end, under the last line. Saying or typing is the main
 * way to answer; a chip sends its value, and the reply shows its label. They're the current question's only.
 * VoiceOver finds them in a container called "Options", each a button named by its words. GameScreen.kt's Options.
 */
struct AnswerChips: View {
    let game: GameController
    let buttons: [AnswerButton]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(buttons.indices, id: \.self) { i in
                Chip(label: buttons[i].label) { game.tap(buttons[i]) }
                    .accessibilityIdentifier("answer-\(buttons[i].value)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Options")
        .accessibilityIdentifier("chips")
    }
}

/**
 * A chip: a surface pill with a 2 pt outline, at least 48 pt tall and wide, its label as written in the label style
 * (wrapping between words when it's longer than a line). GameScreen.kt's Chip.
 */
private struct Chip: View {
    let label: String
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Button(action: action) {
            Text(label)
                .epicFont(.label)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minWidth: 48, minHeight: 48)
                .background(c.surface, in: Self.shape)
                .overlay { Self.shape.strokeBorder(c.outline, lineWidth: 2) }
                .contentShape(Self.shape)
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
        .accessibilityLabel(label)
    }
}

/**
 * Its subviews side by side, left to right, a new line when the next doesn't fit: each as wide as it would like, and
 * one wider than a line takes the whole line (its text wraps there, between words). Lines are [lineSpacing] apart,
 * their views centred on the line.
 */
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width, subviews)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2), anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The views in lines no wider than [width] (nil or infinite: one line).
    private func arrange(width: CGFloat?, _ subviews: Subviews) -> [Line] {
        let room = width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
        var lines: [Line] = []
        var line = Line()
        for (i, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if size.width > room {
                size = CGSize(width: room, height: view.sizeThatFits(ProposedViewSize(width: room, height: nil)).height)
            }
            if !line.items.isEmpty && line.width + spacing + size.width > room {
                lines.append(line)
                line = Line()
            }
            let start = line.items.isEmpty ? 0 : line.width + spacing
            line.items.append(Item(index: i, size: size))
            line.width = start + size.width
            line.height = max(line.height, size.height)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
