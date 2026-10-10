// ui/theme/EpicTheme.kt: the app's look, from the player's settings and the phone's.

import SwiftUI
import UIKit

/**
 * The app's look, from the player's settings and the phone's (docs/DESIGN.md › Everywhere; Android's EpicTheme.kt),
 * put in the environment for everything under it:
 * - the palette ([EnvironmentValues.epicColors]): Settings › Theme, the phone's dark mode, and Increase Contrast (Light
 *   becomes Light + increased contrast, Dark becomes High contrast). With Reduce Transparency the Paused and loading
 *   scrim is solid whatever the palette says (every palette's is, docs/DESIGN.md › Colour); with Differentiate Without
 *   Colour, decorative edges are 2 pt, so cards and bubbles aren't told apart by a shade alone (every state already
 *   has an icon and words);
 * - the type ([EnvironmentValues.epicType]): Settings › Font and Text size, Dynamic Type, Bold Text;
 * - Reduce Motion ([EnvironmentValues.epicReduceMotion]): the phone's, or Settings › Reduce motion;
 * - Button Shapes ([EnvironmentValues.epicButtonShapes]): buttons that are only words are underlined;
 * - the [settings] themselves, for what reads them as it draws (the transcript's highlight and speaker names).
 *
 * The theme's light or dark is set on the window itself ([WindowStyle]), so the status bar's icons, sheets, alerts and
 * menus follow the theme, not only the phone: High contrast is dark. [darkWindow] has it dark whatever the theme, while
 * the intro shows (navy in every theme, with light status bar icons over it; Android's IntroScreen sets its bar icons
 * so). Text and controls default to the palette's text and primary colours.
 */
struct EpicTheme: ViewModifier {
    let settings: AppSettings
    var darkWindow = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityShowButtonShapes) private var buttonShapes
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        let colors = palette
        content
            .environment(\.epicColors, colors)
            .environment(\.epicType, type)
            .environment(\.epicReduceMotion, reduceMotion || settings.reduceMotion)
            .environment(\.epicButtonShapes, buttonShapes)
            .environment(settings)
            .foregroundStyle(colors.text)
            .tint(colors.primary)
            .background { WindowStyle(style: style) }
    }

    private var palette: EpicColors {
        // With a theme of its own the window is in that scheme already; Match my phone follows the phone's.
        var colors = EpicColors.of(
            theme: settings.theme, systemDark: colorScheme == .dark, moreContrast: moreContrast)
        if reduceTransparency { colors.scrimOpacity = 1 }
        if differentiateWithoutColor { colors.edgeWidth = max(colors.edgeWidth, 2) }
        return colors
    }

    /// The phone asks for more contrast (Increase Contrast); in a Debug build, -EpicContrast increased too, as a UI
    /// test can't turn the phone's on (DebugLaunch).
    private var moreContrast: Bool {
        #if DEBUG
        if DebugLaunch.moreContrast { return true }
        #endif
        return colorSchemeContrast == .increased
    }

    private var type: EpicType {
        EpicType(
            atkinson: settings.font == .atkinson, scale: CGFloat(settings.textScale), dynamicTypeSize: dynamicTypeSize,
            boldText: legibilityWeight == .bold)
    }

    /// The window's light or dark: the phone's for Match my phone, else the theme's (High contrast is a dark one); dark
    /// under the intro.
    private var style: UIUserInterfaceStyle {
        if darkWindow { return .dark }
        switch settings.theme {
        case .system: return .unspecified
        case .light: return .light
        case .dark, .contrast: return .dark
        }
    }
}

/**
 * Sets the window it's in to the theme's light or dark (UIKit's overrideUserInterfaceStyle), or back to the phone's
 * (unspecified, for Match my phone), as soon as the theme changes. SwiftUI's preferredColorScheme(nil) doesn't reliably
 * go back to the phone's appearance until the app is launched again, so Dark or Light then Match my phone stayed dark
 * or light; the window's own setting has no such trouble. The sheets, alerts and menus in the window follow it, and so
 * does the colour scheme EpicTheme reads (Match my phone's light or dark). Only a probe: nothing to see or touch.
 */
private struct WindowStyle: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.style = style
    }

    final class Probe: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        /// Only when it differs: setting it changes the window's traits, which draws everything again.
        private func apply() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}

extension View {
    /// The app's look (EpicTheme), from [settings]: at the root, and again in each sheet. [darkWindow]: the window dark
    /// whatever the theme (the root's, while the intro shows).
    func epicTheme(_ settings: AppSettings, darkWindow: Bool = false) -> some View {
        modifier(EpicTheme(settings: settings, darkWindow: darkWindow))
    }
}

/**
 * Motion is reduced: the phone's Reduce Motion, or the app's own Settings › Reduce motion. The talking circle doesn't
 * pulse, the mic's ring holds still, the transcript jumps rather than scrolls. Android's LocalReduceMotion.
 */
nonisolated private struct EpicReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

/// Button Shapes is on: buttons that are only words get an underline (docs/DESIGN.md › Everywhere).
nonisolated private struct EpicButtonShapesKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    nonisolated var epicReduceMotion: Bool {
        get { self[EpicReduceMotionKey.self] }
        set { self[EpicReduceMotionKey.self] = newValue }
    }

    nonisolated var epicButtonShapes: Bool {
        get { self[EpicButtonShapesKey.self] }
        set { self[EpicButtonShapesKey.self] = newValue }
    }
}
