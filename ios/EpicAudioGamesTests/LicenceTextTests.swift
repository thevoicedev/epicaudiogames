// LicenceTextTest.kt: Settings › Licences shows the font's licence whole, as headings and paragraphs that reflow.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * Settings › Licences shows the font's licence as headings and paragraphs that reflow at any text size, and the licence
 * asks for itself in full in every copy: every word of the shipped file is shown, in order
 * (content/app/licences/OFL-AtkinsonHyperlegibleNext.txt, which the app bundles as it is). Android: LicenceTextTest.kt.
 */
@MainActor
struct LicenceTextTests {
    /// The repo's copy (the tests run on the Mac, which has the repo; AppModelTests reads its packs the same way).
    private static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("content/app/licences/OFL-AtkinsonHyperlegibleNext.txt")

    private func text() throws -> String { try String(contentsOf: Self.file, encoding: .utf8) }

    @Test func theLicencesSectionsAreHeadings() throws {
        let blocks = licenceBlocks(try text())
        #expect(blocks.filter(\.heading).map(\.text) == [
            "SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007",
            "PREAMBLE", "DEFINITIONS", "PERMISSION & CONDITIONS", "TERMINATION", "DISCLAIMER",
        ])
    }

    @Test func everyWordIsShownInItsOrder() throws {
        let text = try text()
        // The rules of dashes are the only thing left out (a dash or two within a line stays).
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !($0.count >= 3 && $0.allSatisfy { $0 == "-" }) }
        let shown = licenceBlocks(text).flatMap { $0.text.split(separator: " ").map(String.init) }
        #expect(shown == words)
    }

    @Test func paragraphsAreJoinedLinesThatReflow() throws {
        let blocks = licenceBlocks(try text())
        #expect(blocks.first?.text.hasPrefix("Copyright 2020-2024 The Atkinson Hyperlegible Next Project Authors") == true)
        for block in blocks {
            #expect(!block.text.contains("\n") && !block.text.contains("  "), "\(block.text)")
        }
        // The conditions stay a paragraph each.
        #expect(blocks.contains { !$0.heading && $0.text.hasPrefix("1) Neither the Font Software nor") })
        #expect(blocks.contains { !$0.heading && $0.text.hasPrefix("5) The Font Software, modified or unmodified") })
    }

    @Test func aHeadingStartsWithAWordInCapitalsAndDoesntEndASentence() {
        #expect(licenceBlocks("TITLE\nline one\n  line two  \n\n-----\nTHE END OF IT.\n\nPlain words\n") == [
            LicenceBlock(text: "TITLE", heading: true),
            LicenceBlock(text: "line one line two", heading: false),
            LicenceBlock(text: "THE END OF IT.", heading: false),
            LicenceBlock(text: "Plain words", heading: false),
        ])
        // A file with Windows line ends reads the same.
        #expect(licenceBlocks("TITLE\r\nline one\r\n\r\nPlain words\r\n") == [
            LicenceBlock(text: "TITLE", heading: true),
            LicenceBlock(text: "line one", heading: false),
            LicenceBlock(text: "Plain words", heading: false),
        ])
    }
}
