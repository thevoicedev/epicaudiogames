// ui/GameScreen.kt, ui/Theme.kt and Listener.kt's details as Compose draws them: wrapped text width, the material
// icons' shapes, the spinner, and the mic's level.

import SwiftUI
import Testing
import UIKit
@testable import EpicAudioGames

@MainActor
struct ParityLookTests {
    private static let long = "Slurpy's Noodle Bar hums with the sound of slurping, and the smell of broth drifts out."

    /// The size SwiftUI gives [view] in [width].
    private func size(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// A Compose Text that wraps takes its whole maximum width; one that fits on a line is as wide as its text.
    @Test func wrappedTextTakesTheWholeWidth() {
        let text = Text(Self.long).font(Lilita.font(17))
        let plain = size(text.fixedSize(horizontal: false, vertical: true), width: 312)
        let wrapped = size(WrappedWidth { text }, width: 312)
        #expect(plain.width < 312, "the test text should leave a ragged edge: \(plain)")
        #expect(wrapped.width == 312)
        #expect(wrapped.height == plain.height)
        let short = Text("Yes!").font(Lilita.font(17))
        #expect(size(WrappedWidth { short }, width: 312).width == size(short, width: 312).width)
        #expect(size(WrappedWidth { short }, width: 312).width < 60)
    }

    /// The status under the circle: two lines start at the left edge, as Compose's wrapped Text does; one line is
    /// as wide as its text (and centred by the column).
    @Test func outlinedTextTakesTheWholeWidthOnceItWraps() {
        let label = OutlinedLabel()
        label.configure(text: "“" + Self.long + "”", size: 18, fill: .white, outline: Palette.inkUI, maxLines: 2,
                        scale: 3, category: .large)
        #expect(label.fitting(width: 393).width == 393)
        label.configure(text: "Your turn! Tap the mic to talk", size: 18, fill: .white, outline: Palette.inkUI,
                        maxLines: 2, scale: 3, category: .large)
        let one = label.fitting(width: 393)
        #expect(one.width < 393)
        #expect(one.width > 100)
        #expect(label.fitting(width: 393).height == label.fitting(width: .greatestFiniteMagnitude).height)
    }

    /// The icons are Material's: their drawn bounds on the 24-unit grid (GameScreen.kt's sizes give the dp).
    @Test func materialIconsHaveMaterialsShapes() {
        func bounds(_ icon: MaterialIcon) -> CGRect { icon.path.path.boundingRect }
        let play = bounds(.playArrow)
        #expect(play == CGRect(x: 8, y: 5, width: 11, height: 14))          // 29.3 × 37.3 dp at 64 dp
        let send = bounds(.send)
        #expect(abs(send.minX - 2) < 0.02 && abs(send.width - 21) < 0.02 && send.minY == 3 && send.height == 18)
        let more = bounds(.moreVert)
        #expect(abs(more.minX - 10) < 0.01 && abs(more.width - 4) < 0.01)
        #expect(abs(more.minY - 4) < 0.01 && abs(more.height - 16) < 0.01)
        let mic = bounds(.mic)
        #expect(abs(mic.minX - 5) < 0.01 && abs(mic.width - 14) < 0.01)     // 16.3 × 22.2 dp at 28 dp
        #expect(abs(mic.minY - 2) < 0.01 && abs(mic.height - 19) < 0.01)
        let off = bounds(.micOff)
        #expect(abs(off.minX - 3) < 0.01 && abs(off.maxX - 21) < 0.01)
        #expect(abs(off.minY - 2) < 0.01 && abs(off.maxY - 21) < 0.01)
        let back = bounds(.arrowBack)
        #expect(back == CGRect(x: 4, y: 4, width: 16, height: 16))
        // Scaled into its frame.
        let big = MaterialIcon.playArrow.path(in: CGRect(x: 0, y: 0, width: 64, height: 64)).boundingRect
        #expect(abs(big.width - 11 * 64 / 24) < 0.01 && abs(big.height - 14 * 64 / 24) < 0.01)
    }

    /// Material 3's indeterminate ring: the head runs ahead for 666 ms, then the tail catches up.
    @Test func theSpinnerGrowsAndShrinks() {
        #expect(RingSpinner.arc(at: 0).sweep < 1)
        #expect(abs(RingSpinner.arc(at: 666).sweep - 290) < 0.01)
        #expect(RingSpinner.arc(at: 999).sweep < 290)
        #expect(RingSpinner.arc(at: 1331).sweep < 5)
        // The base turns all along.
        #expect(RingSpinner.arc(at: 1332).start != RingSpinner.arc(at: 0).start)
    }

    /// The listening ring's level: a quiet room is 0, speaking up close 1.
    @Test func theMicsLevel() {
        func level(_ amplitude: Float) -> Float {
            let samples = [Float](repeating: amplitude, count: 480)
            return samples.withUnsafeBufferPointer { LevelMeter.level($0) }
        }
        #expect(level(0) == 0)
        #expect(level(0.0005) == 0)
        #expect(level(0.5) == 1)
        #expect(level(0.01) > 0.2 && level(0.01) < 0.5)
    }
}
