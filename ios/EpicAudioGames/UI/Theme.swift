// ui/Theme.kt: the Mini Games look. Lilita One, a light blue backdrop, a slate blue header bar, white outlined titles.

import EpicAppCore
import SwiftUI
import UIKit

extension Color {
    /// An sRGB colour from 0xRRGGBB, as Compose's Color(0xFFRRGGBB).
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    init(_ rgb: RGBColor) {
        self.init(hex: rgb.hex)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Palette {
    static let headerTop = Color(hex: 0x4E6383)
    static let headerBottom = Color(hex: 0x5E86AF)
    static let headerLine = Color(hex: 0xDDE8F3)
    static let backdropCenter = Color(hex: 0x90D3E9)
    static let backdropEdge = Color(hex: 0x3E7FC3)
    static let ink = Color(hex: 0x1F3B5C)
    static let title = Color(hex: 0x2F72B9)
    static let yes = Color(hex: 0x28A745)
    static let no = Color(hex: 0xDC3545)
    static let choice = Color(hex: 0x007BFF)
    static let gold = Color(hex: 0xFFC107)
    static let listen = Color(hex: 0x3DDC84)
    static let card = Color(hex: 0xFFFFFF)
    static let reply = Color(hex: 0xFFF3C4)

    /// Compose's Color.Gray (the mic when it can't listen).
    static let gray = Color(hex: 0x888888)
    /// Material 3's onSurfaceVariant (a text field's placeholder).
    static let placeholder = Color(hex: 0x49454F)

    static let inkUI = UIColor(hex: 0x1F3B5C)
    static let goldUI = UIColor(hex: 0xFFC107)
}

/// Speaker name colours, picked by name so each character keeps theirs.
func speakerColor(_ who: String) -> Color { Color(SpeakerPalette.color(who)) }

/// Lilita One, the app's font (res/font/lilita_one.ttf, bundled as Fonts/lilita_one.ttf).
enum Lilita {
    static let name = "LilitaOne"

    /// The font at [size] points (Compose's sp), growing with the reader's text size as sp does.
    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(name, size: size, relativeTo: style)
    }

    static func uiFont(_ size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    /// The font's own line height at [size] (ascent plus descent; it has no leading).
    static func lineHeight(_ size: CGFloat) -> CGFloat { uiFont(size).lineHeight }
}

/// Theme.kt's typography (EpicTheme): Lilita One in ink, some with a line height.
struct Typography {
    let size: CGFloat
    /// Compose's lineHeight; nil for the font's own.
    let lineHeight: CGFloat?
    let relativeTo: Font.TextStyle

    static let titleLarge = Typography(size: 22, lineHeight: nil, relativeTo: .title2)
    static let bodyLarge = Typography(size: 17, lineHeight: 23, relativeTo: .body)
    static let bodyMedium = Typography(size: 15, lineHeight: 20, relativeTo: .subheadline)
    static let bodySmall = Typography(size: 13, lineHeight: 17, relativeTo: .footnote)
    static let labelLarge = Typography(size: 17, lineHeight: nil, relativeTo: .body)

    var font: Font { Lilita.font(size, relativeTo: relativeTo) }

    /// The space between lines that makes Compose's line height: a single line is the font's own height, as
    /// Compose trims the extra above the first line and below the last.
    var lineSpacing: CGFloat {
        guard let lineHeight else { return 0 }
        return max(lineHeight - Lilita.lineHeight(size), 0)
    }
}

extension View {
    func textStyle(_ style: Typography) -> some View {
        font(style.font).lineSpacing(style.lineSpacing)
    }
}

/// The light blue backdrop, brightest at the top middle.
struct Backdrop: View {
    var body: some View {
        GeometryReader { g in
            RadialGradient(
                colors: [Palette.backdropCenter, Palette.backdropEdge],
                center: UnitPoint(x: 0.5, y: 0.25),
                startRadius: 0,
                endRadius: max(g.size.width, g.size.height) * 0.75
            )
        }
        .ignoresSafeArea()
    }
}

/// The header bar, under the status bar: a back arrow (in a game), the title, and any actions. A long title takes two
/// lines, and the bar grows for it.
struct HeaderBar<Actions: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var actions: Actions

    init(_ title: String, onBack: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.onBack = onBack
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 0) {
            if let onBack {
                Button(action: onBack) {
                    IconView(icon: .arrowBack)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Spacer().frame(width: 10)
            }
            OutlinedText(title, size: 24, maxLines: 2, isHeader: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 60)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Palette.headerLine.frame(height: 2)
        }
        .background {
            LinearGradient(colors: [Palette.headerTop, Palette.headerBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// A round-ended label (HomeScreen.kt's Pill): CONTINUE, a game's packs, what's free, PLAY.
struct Pill: View {
    let text: String
    let background: Color
    let color: Color
    var big = false

    var body: some View {
        Text(text)
            .font(Lilita.font(big ? 18 : 13))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, big ? 22 : 12)
            .padding(.vertical, big ? 8 : 5)
            .background(background, in: Capsule())
    }
}

/// A Material 3 filled button's press: a little darker while held.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/// Material 3's Button as Theme and GameScreen use it: a coloured rounded box with Lilita text, white unless
/// [text] says (ink on gold: white on it is too faint).
struct FilledButton: View {
    let label: String
    let color: Color
    var text: Color = .white
    var size: CGFloat = 20
    var corner: CGFloat = 18
    var vertical: CGFloat = 12
    var horizontal: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Lilita.font(size))
                .foregroundStyle(text)
                .multilineTextAlignment(.center)
                .padding(.vertical, vertical)
                .padding(.horizontal, horizontal)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .circular))
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .circular))
        }
        .buttonStyle(PressStyle())
    }
}
