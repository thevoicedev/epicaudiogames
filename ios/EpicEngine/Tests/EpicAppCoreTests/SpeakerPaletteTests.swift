// SpeakerPalette.swift: ui/Theme.kt's speakerColor, by Java's String.hashCode and Math.floorMod.

import Foundation
import Testing

@testable import EpicAppCore

struct SpeakerPaletteTests {
    @Test func eachSpeakerKeepsTheirColour() {
        // fixed: four colours darkened to 4.5:1 on white, each in its old slot (Theme.kt's too).
        let table: [(String, UInt32)] = [
            ("GRIBBO", 0xC23D0A), ("PIP", 0x5F3DC4), ("ALEX", 0xA85600), ("ROBIN", 0x237A36), ("COSMO", 0xC23D0A),
            ("HOST", 0x2F72B9), ("KITCHEN", 0xC2255C), ("DON", 0x862E9C), ("", 0x2F72B9),
            // Negative hashes: floorMod, not the remainder (ADMIRAL's is -421653858).
            ("ADMIRAL", 0xA85600), ("OFFICER", 0xA85600), ("PINOCCHIO", 0xC2255C),
        ]
        for (who, hex) in table {
            #expect(SpeakerPalette.color(who) == RGBColor(hex), "\(who)")
        }
        #expect(Kt.javaHash("ADMIRAL") == -421_653_858)
    }

    @Test func theNarratorIsInInk() {
        #expect(SpeakerPalette.color("NARRATOR") == SpeakerPalette.ink)
        #expect(SpeakerPalette.ink.description == "#1F3B5C")
        #expect(SpeakerPalette.color("Narrator") == RGBColor(0xC23D0A))      // only the key, exactly
    }

    @Test func colours() {
        #expect(SpeakerPalette.colors.map(\.description) == [
            "#2F72B9", "#C23D0A", "#237A36", "#862E9C", "#C2255C", "#0B7285", "#A85600", "#5F3DC4",
        ])
        // Small text: each at least 4.5:1 on white (WCAG AA).
        for c in SpeakerPalette.colors + [SpeakerPalette.ink] {
            #expect(Self.contrastOnWhite(c) >= 4.5, "\(c)")
        }
        let c = RGBColor(0x0080FF)
        #expect(c.description == "#0080FF")
        #expect(c.red == 0)
        #expect(c.green == 128.0 / 255)
        #expect(c.blue == 1)
    }

    /// WCAG's contrast ratio of [c] on white.
    private static func contrastOnWhite(_ c: RGBColor) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
        return 1.05 / (l + 0.05)
    }
}
