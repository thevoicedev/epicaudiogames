// ui/theme/Type.kt: Atkinson Hyperlegible Next, the type styles, Settings' text size and font, and Bold Text.

import SwiftUI
import UIKit

/**
 * Atkinson Hyperlegible Next (Braille Institute, SIL Open Font License 1.1): letters made to be told apart, for low
 * vision. The static Regular, Bold and ExtraBold files, unmodified (their licence is content/app/licences/), bundled
 * from Android's res/font by scripts/bundle_content.sh and listed in Info.plist's UIAppFonts. These are their
 * PostScript names (the ExtraBold's family name is a family of its own, so the fonts are found by these).
 */
nonisolated enum Atkinson {
    static let regular = "AtkinsonHyperlegibleNext-Regular"
    static let bold = "AtkinsonHyperlegibleNext-Bold"
    static let extraBold = "AtkinsonHyperlegibleNext-ExtraBold"
}

/// The three weights docs/DESIGN.md's type uses.
nonisolated enum EpicWeight: Sendable {
    case regular, bold, extraBold

    /// One weight heavier, for Bold Text: Regular draws Bold, Bold draws ExtraBold (the heaviest there is).
    var heavier: EpicWeight {
        switch self {
        case .regular: .bold
        case .bold, .extraBold: .extraBold
        }
    }

    /// The Atkinson face at this weight.
    var face: String {
        switch self {
        case .regular: Atkinson.regular
        case .bold: Atkinson.bold
        case .extraBold: Atkinson.extraBold
        }
    }

    /// The phone's own font at this weight (SF's heavy is its 800, as ExtraBold is).
    var system: Font.Weight {
        switch self {
        case .regular: .regular
        case .bold: .bold
        case .extraBold: .heavy
        }
    }

    var systemUI: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .bold: .bold
        case .extraBold: .heavy
        }
    }
}

/**
 * The type styles (docs/DESIGN.md › Type; Android's Type.kt has the same names): a base size in points, a weight, a
 * line height (times the size), and the Dynamic Type style it grows like. Nothing is under 16 pt at the standard text
 * size, and nothing stops growing: no Dynamic Type caps, no line limits but the one-line answer field.
 */
nonisolated enum EpicTextStyle: CaseIterable, Sendable {
    /// The intro's wordmark.
    case display
    /// Tab headings, onboarding and help topic headings.
    case title
    /// Section headings, the end and pause headings, sheet titles.
    case headline
    /// Game and pack titles, help list items, the game's header.
    case itemTitle
    /// Transcript lines and replies.
    case transcript
    /// Paragraphs.
    case body
    /// Buttons, chips, the status line.
    case label
    /// Speaker names, "You", badges.
    case speaker
    /// Download sizes, notes, setting hints.
    case secondary

    var size: CGFloat {
        switch self {
        case .display: 34
        case .title: 30
        case .headline: 22
        case .itemTitle, .transcript: 20
        case .body, .label: 18
        case .speaker, .secondary: 16
        }
    }

    var weight: EpicWeight {
        switch self {
        case .display: .extraBold
        case .title, .headline, .itemTitle, .label, .speaker: .bold
        case .transcript, .body, .secondary: .regular
        }
    }

    /// The line height, as a multiple of the size.
    var lineHeight: CGFloat {
        switch self {
        case .display: 1.2
        case .title, .label: 1.25
        case .headline, .itemTitle, .speaker: 1.3
        case .transcript: 1.5
        case .body: 1.45
        case .secondary: 1.4
        }
    }

    /// The Dynamic Type style whose growth it follows (docs/DESIGN.md's "iOS scales like").
    var scalesLike: UIFont.TextStyle {
        switch self {
        case .display, .title: .largeTitle
        case .headline: .title2
        case .itemTitle: .title3
        case .transcript, .body, .label: .body
        case .speaker: .subheadline
        case .secondary: .callout
        }
    }
}

/**
 * The type in use (EpicTheme provides it): Atkinson Hyperlegible Next or the phone's font (Settings › Font), Settings ›
 * Text size (Standard 1, Large 1.15, Larger 1.3), the phone's text size (Dynamic Type) on top of that, and Bold Text.
 *
 * Sizes are worked out here rather than left to Font.custom(_:size:relativeTo:): the app's text size multiplies the
 * base size first, then UIFontMetrics grows it as its Dynamic Type style grows, and the font is made at that fixed
 * size. Bold Text is done by hand for Atkinson (a named face doesn't change by itself): Regular draws Bold and Bold
 * draws ExtraBold, as Android's font resolver does. The phone's font (SF) is made bolder by SwiftUI itself, so it
 * isn't moved again here. Android: Type.kt's epicType.
 */
nonisolated struct EpicType: Equatable, Sendable {
    /// Atkinson Hyperlegible Next, or (Settings › Font › Phone's font) the system font at the same sizes.
    var atkinson: Bool
    /// Settings › Text size: 1, 1.15 or 1.3.
    var scale: CGFloat
    /// The phone's text size.
    var dynamicTypeSize: DynamicTypeSize
    /// Bold Text is on (legibilityWeight .bold).
    var boldText: Bool

    init(atkinson: Bool = true, scale: CGFloat = 1, dynamicTypeSize: DynamicTypeSize = .large, boldText: Bool = false) {
        self.atkinson = atkinson
        self.scale = scale
        self.dynamicTypeSize = dynamicTypeSize
        self.boldText = boldText
    }

    /// The text is at an accessibility size: game covers are hidden and the game takes its compact layout (Android:
    /// font scale 1.6 or more).
    var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    /// [style]'s weight as drawn: one heavier with Bold Text, for Atkinson.
    func weight(_ style: EpicTextStyle) -> EpicWeight {
        atkinson && boldText ? style.weight.heavier : style.weight
    }

    /// [style]'s size in points: its base size, times Settings' text size, grown as its Dynamic Type style grows.
    @MainActor
    func pointSize(_ style: EpicTextStyle) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let metrics = UIFontMetrics(forTextStyle: style.scalesLike)
        return metrics.scaledValue(for: style.size * scale, compatibleWith: traits)
    }

    @MainActor
    func font(_ style: EpicTextStyle) -> Font {
        let size = pointSize(style)
        if atkinson { return Font.custom(weight(style).face, fixedSize: size) }
        return Font.system(size: size, weight: weight(style).system)
    }

    /**
     * The room SwiftUI adds between [style]'s lines to make its line height: the line height less the font's own
     * (Atkinson's is 1.3 times its size, SF's about 1.2), never less than nothing.
     */
    @MainActor
    func lineSpacing(_ style: EpicTextStyle) -> CGFloat {
        let size = pointSize(style)
        let own = atkinson
            ? UIFont(name: weight(style).face, size: size)?.lineHeight ?? size * 1.3
            : UIFont.systemFont(ofSize: size, weight: weight(style).systemUI).lineHeight
        return max(size * style.lineHeight - own, 0)
    }
}

/// The type in use, from EpicTheme; Atkinson at the standard size until a theme says otherwise.
nonisolated private struct EpicTypeKey: EnvironmentKey {
    static var defaultValue: EpicType { EpicType() }
}

extension EnvironmentValues {
    /// The theme's type where a view draws: `@Environment(\.epicType) private var type`, or `.epicFont(.body)`.
    nonisolated var epicType: EpicType {
        get { self[EpicTypeKey.self] }
        set { self[EpicTypeKey.self] = newValue }
    }
}

/// A type style from the theme: its font and its line spacing.
private struct EpicFont: ViewModifier {
    let style: EpicTextStyle
    @Environment(\.epicType) private var type

    func body(content: Content) -> some View {
        content
            .font(type.font(style))
            .lineSpacing(type.lineSpacing(style))
    }
}

extension View {
    /// Text in one of the theme's type styles (docs/DESIGN.md › Type): `Text("Games").epicFont(.title)`.
    func epicFont(_ style: EpicTextStyle) -> some View {
        modifier(EpicFont(style: style))
    }
}
