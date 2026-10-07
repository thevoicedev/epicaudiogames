// ui/GameScreen.kt's Chips: the question's options, as quick replies at the end of the chat.

import EpicAppCore
import SwiftUI

/**
 * The question's options (its buttons), as small chips at the feed's end, under the last line. Saying or typing is the
 * main way to answer; a chip sends its value, and the reply shows its label. They're the current question's only.
 * VoiceOver finds them in a container called "Options", each a button.
 */
struct AnswerChips: View {
    let game: GameController
    let buttons: [AnswerButton]

    var body: some View {
        // Each chip has 4 pt above and below it to touch, so the lines are 8 pt apart to the eye.
        FlowLayout(spacing: 8, lineSpacing: 0) {
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
 * A chip: a white pill edged in the reply's colour, its label as written, in ink. It looks 36 pt tall (and at least 48
 * wide), and is at least 44 pt to touch: the space above and below it counts.
 */
private struct Chip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Lilita.font(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minWidth: 48, minHeight: 36)
                .background(Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.reply, lineWidth: 2))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
