// HelpHighlight.swift: the word marked as a help page is read aloud.

import Foundation
import Testing

@testable import EpicAppCore

/**
 * The word marked as a help page is read aloud ([HelpHighlight]): from the line's word times where it has them, else
 * spread evenly over the line, as the game's transcript is; on a page, the paragraph its clip reads, with nothing for
 * an earcon's clip. Android's HelpHighlightTest.kt.
 */
struct HelpHighlightTests {
    private static let said = "Say \u{201C}repeat\u{201D} to hear it again."
    /// Its six words start 0, 0.4, 1.2, 1.4, 1.9 and 2.1 seconds into the line, which starts 0.5 s into its clip.
    private static let timed = Line(at: 0.5, len: 2.6, who: "HOST", text: said, words: [0, 0.4, 1.2, 1.4, 1.9, 2.1])
    private static let untimed = Line(at: 0, len: 2, who: "HOST", text: "Email us at james@hugo.fm.")

    @Test func withWordTimesItsTheWordThatHasBegun() throws {
        #expect(try word(Self.timed, 0.5) == "Say")
        #expect(try word(Self.timed, 0.89) == "Say")
        #expect(try word(Self.timed, 0.9) == "\u{201C}repeat\u{201D}")
        #expect(try word(Self.timed, 1.75) == "to")
        #expect(try word(Self.timed, 2.75) == "again.")
        // Past the line's end: still its last word.
        #expect(try word(Self.timed, 9) == "again.")
        // Everything up to the end of the word being said counts as said.
        let at = try #require(HelpHighlight.at([Self.timed], seconds: 0.95))
        #expect(at.line == 0)
        #expect(at.chars == "Say \u{201C}repeat\u{201D}".utf16.count)
    }

    @Test func withoutWordTimesTheLinesTimeIsSpreadOverItsCharacters() throws {
        // As the game's transcript: half the time, half the characters.
        let length = Self.untimed.text.utf16.count
        let half = try #require(HelpHighlight.at([Self.untimed], seconds: 1))
        #expect(half.line == 0)
        #expect(half.chars == length / 2)
        let start = try #require(HelpHighlight.at([Self.untimed], seconds: 0))
        #expect(start.chars == 0)
        let after = try #require(HelpHighlight.at([Self.untimed], seconds: 5))
        #expect(after.chars == length)
    }

    @Test func beforeTheFirstLineNothingIsMarked() {
        #expect(HelpHighlight.at([Self.timed], seconds: 0.2) == nil)
        #expect(HelpHighlight.at([], seconds: 1) == nil)
    }

    @Test func aClipOfTwoLinesIsOneParagraph() throws {
        let first = Line(at: 0, len: 1, who: "HOST", text: "One two.")
        let second = Line(at: 1, len: 1, who: "HOST", text: "Three four.", words: [0, 0.5])
        let page = helpPage(["One two. Three four."], [0], [play(first, second)])
        let at = try #require(HelpHighlight.at([first, second], seconds: 1.1))
        #expect(at.line == 1)
        #expect(at.chars == "Three".utf16.count)
        let h = try #require(HelpHighlight.of(page, clip: 0, seconds: 1.6))
        #expect(h.paragraph == 0)
        #expect(Transcript.currentWord(page.text[0], saidChars: h.chars).word == "four.")
    }

    @Test func onAPageItsTheParagraphTheClipReads() throws {
        // Paragraph 0, an earcon (no paragraph), then paragraph 1.
        let page = helpPage(
            ["When it opens, you hear this:", Self.said],
            [0, -1, 1],
            [
                play(Line(at: 0, len: 2, who: "HOST", text: "When it opens, you hear this:")),
                .pause(0.2),
                .play(Clip(path: "earcons/listen-start-demo", dur: 0.145, lines: [], sfx: true)),
                .pause(0.6),
                play(Self.timed),
            ])
        let opening = try #require(HelpHighlight.of(page, clip: 0, seconds: 1))
        #expect(opening.paragraph == 0)
        // The earcon has no words: nothing new to mark.
        #expect(HelpHighlight.of(page, clip: 1, seconds: 0.1) == nil)
        let h = try #require(HelpHighlight.of(page, clip: 2, seconds: 1.75))
        #expect(h.paragraph == 1)
        #expect(Transcript.currentWord(Self.said, saidChars: h.chars).word == "to")
        // A clip the page doesn't have.
        #expect(HelpHighlight.of(page, clip: 7, seconds: 0) == nil)
    }

    @Test func theRealWelcomeIsMarkedWordByWord() throws {
        let data = try Data(contentsOf: AppTestRepo.appContent().appendingPathComponent("app.json"))
        let welcome = try #require(try AppManifest.parse(data).welcome)
        let lines = try #require(welcome.clipLines.first)
        #expect(lines.count == 1)
        let first = try #require(lines.first)
        let times = try #require(first.words)
        let words = first.text.split(separator: " ").map(String.init)
        // Just after each word starts, that word is the one marked, and the marks only go forward.
        var last = -1
        for (k, start) in times.enumerated() {
            // (A word said too quickly to be marked on its own is passed over.)
            if k + 1 < times.count && times[k + 1] <= start + 0.01 { continue }
            let h = try #require(HelpHighlight.of(welcome, clip: 0, seconds: first.at + start + 0.01))
            #expect(h.paragraph == welcome.clipParagraph[0])
            #expect(Transcript.currentWord(welcome.text[h.paragraph], saidChars: h.chars).word == words[k])
            #expect(h.chars > last)
            last = h.chars
        }
    }

    private func word(_ line: Line, _ seconds: Double) throws -> String {
        let at = try #require(HelpHighlight.at([line], seconds: seconds))
        #expect(at.line == 0)
        return Transcript.currentWord(line.text, saidChars: at.chars).word
    }

    private func play(_ lines: Line...) -> Step {
        .play(Clip(path: "tts/clip", dur: lines.reduce(0) { $0 + $1.len }, lines: lines))
    }

    private func helpPage(_ text: [String], _ clipParagraph: [Int], _ steps: [Step]) -> HelpPage {
        HelpPage(
            id: "test", title: "Test", summary: "", text: text, clipParagraph: clipParagraph, steps: steps, links: [])
    }
}
