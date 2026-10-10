// ui/GameScreen.kt's Chips laid out: side by side, a new line when the next doesn't fit, never squeezed into columns.

import SwiftUI
import Testing
import UIKit
@testable import EpicAudioGames

@MainActor
struct ChipsTests {
    /// The size SwiftUI gives [view] in [width].
    private func size(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private func chips(_ widths: [CGFloat]) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 0) {
            ForEach(widths.indices, id: \.self) { i in Color.red.frame(width: widths[i], height: 44) }
        }
    }

    /// Left to right, as many to a line as fit (8 pt apart), then the next line.
    @Test func chipsWrapOntoNewLines() {
        #expect(size(chips([100, 100, 100]), width: 400).height == 44)
        #expect(size(chips([100, 100, 100]), width: 316).height == 44)
        #expect(size(chips([100, 100, 100]), width: 315).height == 88)
        #expect(size(chips([100, 100, 100]), width: 150).height == 132)
        // Unbounded, one line as wide as the chips.
        let ideal = UIHostingController(rootView: chips([100, 50])).sizeThatFits(
            in: CGSize(width: CGFloat.infinity, height: .infinity))
        #expect(ideal == CGSize(width: 158, height: 44))
    }

    /// A chip as wide as its label: "Blacksmith" in a third of a phone's width isn't broken mid-word (the old button
    /// grid broke it "BLACKSMIT / H"); a label longer than a line takes the line, wrapping between words. In the
    /// chips' own font: Atkinson Hyperlegible Next Bold, the label style.
    @Test func aLabelIsNeverSqueezed() {
        // Large text: a third of the width is less than the word.
        let word = Text("Blacksmith").font(.custom(Atkinson.bold, fixedSize: 44))
        let one = size(word, width: .greatestFiniteMagnitude)
        #expect(one.width > (353 - 16) / 3)
        let perLine = max(1, Int((353 + 8) / (one.width + 8)))
        let lines = (9 + perLine - 1) / perLine
        let flow = FlowLayout { ForEach(0..<9, id: \.self) { _ in word } }
        #expect(size(flow, width: 353).height == CGFloat(lines) * one.height, "a word was broken onto two lines")
        let long = "A label much longer than a line of a phone's width can hold at all"
        let label = Font.custom(Atkinson.bold, fixedSize: 18)
        let wrapped = size(FlowLayout { Text(long).font(label) }, width: 200)
        #expect(wrapped.width == 200)
        #expect(wrapped.height > size(Text("A").font(label), width: 200).height * 1.5)
    }
}
