// What's left of ui/Theme.kt's helpers: colours from their hex, and the pressed look. The palette, the type and the
// theme are UI/Design's (Tokens, Typography, EpicTheme), as Android's are ui/theme's.

import SwiftUI
import UIKit

extension Color {
    /// An sRGB colour from 0xRRGGBB, as Compose's Color(0xFFRRGGBB). Nonisolated, so the palettes can be made anywhere.
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// A filled button's press: a little darker while held.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}
