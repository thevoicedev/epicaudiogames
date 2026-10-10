// ui/theme/Tokens.kt: the app's colours by what they're for, in four palettes (docs/DESIGN.md › Colour).

import SwiftUI

/**
 * The app's colours by what they're for (docs/DESIGN.md › Colour; the same names as Android's ui/theme/Tokens.kt), in
 * four palettes: [dark], [light], [contrast] (black, white and yellow) and [lightIncreased] (Light when the phone asks
 * for more contrast). Every text colour is at least 7:1 on the backgrounds it's used on, everything else that means
 * something at least 3:1 (ThemeContrastTests checks each pair). Text never takes an opacity: a fainter word is a harder
 * one to read.
 *
 * Nonisolated, so the environment's default ([EnvironmentValues.epicColors]) can be one of them.
 */
nonisolated struct EpicColors: Equatable, Sendable {
    /// Dark palettes have light status bar icons (EpicTheme sets the window's light or dark).
    let isDark: Bool
    /// Screens.
    let background: Color
    /// Cards, transcript bubbles, chips, the text field.
    let surface: Color
    /// Headers, sheets, the end panel, the answer bar.
    let surfaceRaised: Color
    /// The player's own replies ("You said").
    let replySurface: Color
    /// All body text.
    let text: Color
    /// Secondary text and placeholders: still 7:1, never pale.
    let textMuted: Color
    /// Headings, and links (always underlined).
    let heading: Color
    /// Primary buttons, the mic; [onPrimary] is what's on them.
    let primary: Color
    let onPrimary: Color
    /// The current line's bar and the speaking ring: never text.
    let accent: Color
    /// 2 pt borders: chips, the text field, secondary buttons.
    let outline: Color
    /// Decorative edges: bubbles, cards, dividers ([edgeWidth] wide).
    let outlineSubtle: Color
    /// "Installed", "Microphone allowed": always with an icon.
    let success: Color
    /// Failures: always with an icon and words.
    let error: Color
    /// The talking circle's ring, by state (each also has its own icon and ring style).
    let ringSpeaking: Color
    let ringListening: Color
    let ringIdle: Color
    /// The word being spoken, in inverse colours.
    let highlightBg: Color
    let highlightText: Color
    /// The 3 pt keyboard focus ring (Android draws it; iOS's own ring follows Full Keyboard Access's colour).
    let focus: Color
    /// The download bar, 8 pt tall.
    let progressFill: Color
    let progressTrack: Color
    /// The download bar's border, where its track is the same as the background (the contrast palettes).
    let progressEdge: Color?
    /// The reply bubble's edge: High contrast gives it a 2 pt yellow border, as its fill is black.
    let replyEdge: Color
    /// How wide decorative edges are: 2 pt in the contrast palettes, where they're all that separates a bubble (and
    /// with Differentiate Without Colour, EpicTheme).
    var edgeWidth: CGFloat
    /// How much of what's under it the Paused and loading scrim hides: all of it, in every palette (docs/DESIGN.md ›
    /// Colour: words showing through behind the buttons are hard to read with low vision), and with Reduce
    /// Transparency whatever a palette says (EpicTheme).
    var scrimOpacity: Double

    /// The Paused and loading overlay: the background, solid. Never a text colour.
    var scrim: Color { background.opacity(scrimOpacity) }

    static let dark = EpicColors(
        isDark: true,
        background: Color(hex: 0x0B1430),
        surface: Color(hex: 0x16275E),
        surfaceRaised: Color(hex: 0x1B2D66),
        replySurface: Color(hex: 0x2E2A12),
        text: Color(hex: 0xF6F8FF),
        textMuted: Color(hex: 0xC9D2F0),
        heading: Color(hex: 0xFFD54F),
        primary: Color(hex: 0xFFD54F),
        onPrimary: Color(hex: 0x1A1400),
        accent: Color(hex: 0xFFD54F),
        outline: Color(hex: 0x8E9CCB),
        outlineSubtle: Color(hex: 0x2C3D7A),
        success: Color(hex: 0x8FE3B0),
        error: Color(hex: 0xFFB4AB),
        ringSpeaking: Color(hex: 0xFFD54F),
        ringListening: Color(hex: 0x8FE3B0),
        ringIdle: Color(hex: 0x8E9CCB),
        highlightBg: Color(hex: 0xFFD54F),
        highlightText: Color(hex: 0x0B1430),
        focus: Color(hex: 0xFFD54F),
        progressFill: Color(hex: 0xFFD54F),
        progressTrack: Color(hex: 0x3A4A86),
        progressEdge: nil,
        replyEdge: Color(hex: 0x2C3D7A),
        edgeWidth: 1,
        scrimOpacity: 1
    )

    static let light = EpicColors(
        isDark: false,
        background: Color(hex: 0xF3F5FB),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xFFFFFF),
        replySurface: Color(hex: 0xFFF3C4),
        text: Color(hex: 0x0B1430),
        textMuted: Color(hex: 0x3B4566),
        heading: Color(hex: 0x16275E),
        primary: Color(hex: 0x16275E),
        onPrimary: Color(hex: 0xFFFFFF),
        accent: Color(hex: 0x8A6100),
        outline: Color(hex: 0x6B7699),
        outlineSubtle: Color(hex: 0xD5DAEA),
        success: Color(hex: 0x0F5C33),
        error: Color(hex: 0xA4161A),
        ringSpeaking: Color(hex: 0x8A6100),
        ringListening: Color(hex: 0x0F5C33),
        ringIdle: Color(hex: 0x6B7699),
        highlightBg: Color(hex: 0x16275E),
        highlightText: Color(hex: 0xFFFFFF),
        focus: Color(hex: 0x16275E),
        progressFill: Color(hex: 0x16275E),
        progressTrack: Color(hex: 0xC9CFE3),
        progressEdge: nil,
        replyEdge: Color(hex: 0xD5DAEA),
        edgeWidth: 1,
        scrimOpacity: 1
    )

    /// High contrast: black, white and yellow, whatever the phone's dark mode.
    static let contrast = EpicColors(
        isDark: true,
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x000000),
        surfaceRaised: Color(hex: 0x000000),
        replySurface: Color(hex: 0x000000),
        text: Color(hex: 0xFFFFFF),
        textMuted: Color(hex: 0xFFFFFF),
        heading: Color(hex: 0xFFFF00),
        primary: Color(hex: 0xFFFF00),
        onPrimary: Color(hex: 0x000000),
        accent: Color(hex: 0xFFFF00),
        outline: Color(hex: 0xFFFFFF),
        outlineSubtle: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x7CFF9B),
        error: Color(hex: 0xFF9E9E),
        ringSpeaking: Color(hex: 0xFFFF00),
        ringListening: Color(hex: 0x7CFF9B),
        ringIdle: Color(hex: 0xFFFFFF),
        highlightBg: Color(hex: 0xFFFF00),
        highlightText: Color(hex: 0x000000),
        focus: Color(hex: 0xFFFF00),
        progressFill: Color(hex: 0xFFFF00),
        progressTrack: Color(hex: 0x000000),
        progressEdge: Color(hex: 0xFFFFFF),
        replyEdge: Color(hex: 0xFFFF00),
        edgeWidth: 2,
        scrimOpacity: 1
    )

    /// Light when the phone asks for more contrast: pure white, black text, navy for what was gold.
    static let lightIncreased = EpicColors(
        isDark: false,
        background: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xFFFFFF),
        replySurface: Color(hex: 0xFFF3C4),
        text: Color(hex: 0x000000),
        textMuted: Color(hex: 0x000000),
        heading: Color(hex: 0x0B1430),
        primary: Color(hex: 0x0B1430),
        onPrimary: Color(hex: 0xFFFFFF),
        accent: Color(hex: 0x0B1430),
        outline: Color(hex: 0x000000),
        outlineSubtle: Color(hex: 0x000000),
        success: Color(hex: 0x0B4D2A),
        error: Color(hex: 0x8B0000),
        ringSpeaking: Color(hex: 0x0B1430),
        ringListening: Color(hex: 0x0B4D2A),
        ringIdle: Color(hex: 0x000000),
        highlightBg: Color(hex: 0x0B1430),
        highlightText: Color(hex: 0xFFFFFF),
        focus: Color(hex: 0x000000),
        progressFill: Color(hex: 0x0B1430),
        progressTrack: Color(hex: 0xFFFFFF),
        progressEdge: Color(hex: 0x000000),
        replyEdge: Color(hex: 0x000000),
        edgeWidth: 2,
        scrimOpacity: 1
    )

    /**
     * The palette for Settings › Theme, the phone's dark mode and whether the phone asks for more contrast (Increase
     * Contrast; docs/DESIGN.md › Colour): Light becomes [lightIncreased] and Dark becomes [contrast] then. Match my
     * phone follows dark mode.
     */
    @MainActor
    static func of(theme: ThemeChoice, systemDark: Bool, moreContrast: Bool) -> EpicColors {
        let wantsDark: Bool
        switch theme {
        case .system: wantsDark = systemDark
        case .light: wantsDark = false
        case .dark: wantsDark = true
        case .contrast: return contrast
        }
        if wantsDark { return moreContrast ? contrast : dark }
        return moreContrast ? lightIncreased : light
    }
}

/// The palette in use, from EpicTheme; Dark until a theme says otherwise.
nonisolated private struct EpicColorsKey: EnvironmentKey {
    static var defaultValue: EpicColors { .dark }
}

extension EnvironmentValues {
    /// The theme's colours where a view draws: `@Environment(\.epicColors) private var c`, then `c.text`.
    nonisolated var epicColors: EpicColors {
        get { self[EpicColorsKey.self] }
        set { self[EpicColorsKey.self] = newValue }
    }
}
