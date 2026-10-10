// ui/theme/ContrastTest.kt: docs/DESIGN.md's colour tokens and their contrast, checked from the tokens themselves.

import SwiftUI
import Testing
import UIKit
@testable import EpicAudioGames

/**
 * docs/DESIGN.md › Colour, checked from the tokens themselves (UI/Design/Tokens.swift): every pair in its contrast
 * table meets its minimum (7:1 for text, 3:1 for the rest) in every palette, at the ratio the table gives, and no
 * colour is see-through (text never takes an opacity). The contrast is WCAG 2.x's, from relative luminance. Android:
 * ContrastTest.kt, with the same pairs and ratios.
 */
@MainActor
struct ThemeContrastTests {
    private let palettes: [(name: String, colors: EpicColors)] = [
        ("dark", .dark), ("light", .light), ("contrast", .contrast), ("lightIncreased", .lightIncreased),
    ]

    /// A pair from DESIGN.md's table: what's drawn on what, its minimum, and its ratio in each palette (in order).
    private struct Pair {
        let name: String
        let minimum: Double
        let front: KeyPath<EpicColors, Color>
        let back: KeyPath<EpicColors, Color>
        let ratios: [Double]

        init(
            _ name: String, _ minimum: Double, _ front: KeyPath<EpicColors, Color>, _ back: KeyPath<EpicColors, Color>,
            _ ratios: Double...
        ) {
            self.name = name
            self.minimum = minimum
            self.front = front
            self.back = back
            self.ratios = ratios
        }
    }

    private let pairs: [Pair] = [
        Pair("text / background", 7, \.text, \.background, 17.10, 16.65, 21.00, 21.00),
        Pair("text / surface", 7, \.text, \.surface, 13.32, 18.15, 21.00, 21.00),
        Pair("text / surfaceRaised", 7, \.text, \.surfaceRaised, 12.26, 18.15, 21.00, 21.00),
        Pair("text / replySurface", 7, \.text, \.replySurface, 13.59, 16.31, 21.00, 18.87),
        Pair("textMuted / background", 7, \.textMuted, \.background, 12.07, 8.64, 21.00, 21.00),
        Pair("textMuted / surface", 7, \.textMuted, \.surface, 9.39, 9.42, 21.00, 21.00),
        Pair("textMuted / surfaceRaised", 7, \.textMuted, \.surfaceRaised, 8.65, 9.42, 21.00, 21.00),
        Pair("textMuted / replySurface", 7, \.textMuted, \.replySurface, 9.59, 8.47, 21.00, 18.87),
        Pair("heading / background", 7, \.heading, \.background, 12.86, 12.96, 19.56, 18.15),
        Pair("heading / surfaceRaised", 7, \.heading, \.surfaceRaised, 9.22, 14.13, 19.56, 18.15),
        Pair("onPrimary / primary", 7, \.onPrimary, \.primary, 13.01, 14.13, 19.56, 18.15),
        Pair("highlightText / highlightBg", 7, \.highlightText, \.highlightBg, 12.86, 14.13, 19.56, 18.15),
        Pair("success / surface", 7, \.success, \.surface, 9.28, 8.08, 16.63, 9.96),
        Pair("error / surface", 7, \.error, \.surface, 8.32, 7.75, 10.64, 10.01),
        Pair("error / surfaceRaised", 7, \.error, \.surfaceRaised, 7.66, 7.75, 10.64, 10.01),
        Pair("outline / background", 3, \.outline, \.background, 6.71, 4.12, 21.00, 21.00),
        Pair("outline / surface", 3, \.outline, \.surface, 5.23, 4.49, 21.00, 21.00),
        Pair("accent / surface", 3, \.accent, \.surface, 10.02, 5.54, 19.56, 18.15),
        Pair("ringSpeaking / background", 3, \.ringSpeaking, \.background, 12.86, 5.08, 19.56, 18.15),
        Pair("ringListening / background", 3, \.ringListening, \.background, 11.91, 7.41, 16.63, 9.96),
        Pair("ringIdle / background", 3, \.ringIdle, \.background, 6.71, 4.12, 21.00, 21.00),
        Pair("highlightBg / surface", 3, \.highlightBg, \.surface, 10.02, 14.13, 19.56, 18.15),
        Pair("progressFill / progressTrack", 3, \.progressFill, \.progressTrack, 5.94, 9.10, 19.56, 18.15),
    ]

    @Test func everyPairMeetsItsMinimumInEveryPalette() {
        var failures: [String] = []
        for pair in pairs {
            for (name, colors) in palettes {
                let ratio = contrast(colors[keyPath: pair.front], colors[keyPath: pair.back])
                if ratio < pair.minimum {
                    failures.append("\(pair.name) in \(name): \(String(format: "%.2f", ratio)), under \(pair.minimum)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test func eachPairHasTheRatioDesignMdGives() {
        for pair in pairs {
            #expect(pair.ratios.count == palettes.count, "\(pair.name)")
            for (i, (name, colors)) in palettes.enumerated() where i < pair.ratios.count {
                let ratio = contrast(colors[keyPath: pair.front], colors[keyPath: pair.back])
                #expect(abs(ratio - pair.ratios[i]) <= 0.005, "\(pair.name) in \(name): \(ratio)")
            }
        }
    }

    @Test func noColourIsSeeThrough() {
        // Text above all: a fainter word is a harder one to read (the old "words still to come" were ink at 35%,
        // 1.96:1). The scrim is made from the background, not a token (theScrimHidesWhatsUnderIt).
        for (name, c) in palettes {
            var tokens: [(String, Color)] = [
                ("text", c.text), ("textMuted", c.textMuted), ("heading", c.heading), ("onPrimary", c.onPrimary),
                ("highlightText", c.highlightText), ("success", c.success), ("error", c.error), ("primary", c.primary),
                ("background", c.background), ("surface", c.surface), ("surfaceRaised", c.surfaceRaised),
                ("replySurface", c.replySurface), ("accent", c.accent), ("outline", c.outline),
                ("outlineSubtle", c.outlineSubtle), ("ringSpeaking", c.ringSpeaking),
                ("ringListening", c.ringListening), ("ringIdle", c.ringIdle), ("highlightBg", c.highlightBg), ("focus", c.focus),
                ("progressFill", c.progressFill), ("progressTrack", c.progressTrack), ("replyEdge", c.replyEdge),
            ]
            if let edge = c.progressEdge { tokens.append(("progressEdge", edge)) }
            for (token, colour) in tokens {
                #expect(rgba(colour).a == 1, "\(token) in \(name)")
            }
        }
    }

    /// docs/DESIGN.md › Colour: the Paused and loading scrim is always opaque, as words showing through behind the
    /// buttons are hard to read with low vision.
    @Test func theScrimHidesWhatsUnderIt() {
        for (name, c) in palettes {
            #expect(rgba(c.scrim).a == 1, "scrim in \(name)")
        }
        // Its colour is the background's.
        #expect(abs(rgba(EpicColors.dark.scrim).r - rgba(EpicColors.dark.background).r) < 0.001)
    }

    @Test func thePaletteFollowsTheThemeDarkModeAndContrast() {
        func of(_ theme: ThemeChoice, dark: Bool, more: Bool) -> EpicColors {
            EpicColors.of(theme: theme, systemDark: dark, moreContrast: more)
        }
        // Match my phone: light or dark as the phone is, each with its stronger version when it asks for contrast.
        #expect(of(.system, dark: false, more: false) == .light)
        #expect(of(.system, dark: true, more: false) == .dark)
        #expect(of(.system, dark: false, more: true) == .lightIncreased)
        #expect(of(.system, dark: true, more: true) == .contrast)
        for dark in [false, true] {
            #expect(of(.light, dark: dark, more: false) == .light)
            #expect(of(.light, dark: dark, more: true) == .lightIncreased)
            #expect(of(.dark, dark: dark, more: false) == .dark)
            #expect(of(.dark, dark: dark, more: true) == .contrast)
            for more in [false, true] {
                #expect(of(.contrast, dark: dark, more: more) == .contrast)
            }
        }
        // Dark palettes get the light status bar icons; edges are 2 pt where they're all a bubble has.
        #expect(EpicColors.dark.isDark && EpicColors.contrast.isDark)
        #expect(!EpicColors.light.isDark && !EpicColors.lightIncreased.isDark)
        #expect(EpicColors.contrast.edgeWidth == 2 && EpicColors.lightIncreased.edgeWidth == 2)
        #expect(EpicColors.dark.edgeWidth == 1 && EpicColors.light.edgeWidth == 1)
    }

    // ----- WCAG 2.x -----

    /// [color]'s sRGB components, 0 to 1.
    private func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        let ok = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(ok, "not an RGB colour: \(color)")
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// (lighter + 0.05) / (darker + 0.05), from relative luminance.
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func luminance(_ color: Color) -> Double {
        func linear(_ s: Double) -> Double {
            s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let c = rgba(color)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
}
