// ui/theme/Type.kt, ui/Components.kt's speedWords, HomeScreen.kt's sentences and GameScreen.kt's transcriptText (its
// HighlightTest.kt): the type styles, the words the components make, and the transcript's highlight.

import SwiftUI
import Testing
import UIKit
@testable import EpicAudioGames

@MainActor
struct DesignTests {
    // ----- Type (docs/DESIGN.md › Type) -----

    /// At the standard text size each style is its base size, and none is under 16 pt.
    @Test func atTheStandardSizeEachStyleIsItsBaseSize() {
        let type = EpicType()
        let sizes: [EpicTextStyle: CGFloat] = [
            .display: 34, .title: 30, .headline: 22, .itemTitle: 20, .transcript: 20, .body: 18, .label: 18,
            .speaker: 16, .secondary: 16,
        ]
        for style in EpicTextStyle.allCases {
            #expect(abs(type.pointSize(style) - (sizes[style] ?? 0)) < 0.001, "\(style)")
            #expect(style.size >= 16, "\(style)")
        }
    }

    /// Settings › Text size multiplies the base sizes; Dynamic Type grows them on top, never stopping.
    @Test func theAppsTextSizeAndDynamicTypeBothApply() {
        #expect(abs(EpicType(scale: 1.3).pointSize(.body) - 18 * 1.3) < 0.001)
        #expect(abs(EpicType(scale: 1.15).pointSize(.title) - 30 * 1.15) < 0.001)
        let large = EpicType(dynamicTypeSize: .accessibility3).pointSize(.body)
        #expect(large > 18 * 1.5)
        #expect(EpicType(dynamicTypeSize: .accessibility5).pointSize(.body) > large)
        #expect(EpicType(scale: 1.3, dynamicTypeSize: .accessibility3).pointSize(.body) > large)
        #expect(EpicType(dynamicTypeSize: .xSmall).pointSize(.body) < 18)
        // The compact game layout comes at the accessibility sizes.
        #expect(EpicType(dynamicTypeSize: .accessibility1).isAccessibilitySize)
        #expect(!EpicType(dynamicTypeSize: .xxxLarge).isAccessibilitySize)
    }

    /// Bold Text draws Atkinson one weight heavier (Regular as Bold, Bold as ExtraBold); the phone's font SwiftUI
    /// makes bolder itself.
    @Test func boldTextDrawsEachWeightOneHeavier() {
        let bold = EpicType(boldText: true)
        #expect(bold.weight(.body) == .bold)
        #expect(bold.weight(.transcript) == .bold)
        #expect(bold.weight(.label) == .extraBold)
        #expect(bold.weight(.display) == .extraBold)
        #expect(EpicType().weight(.body) == .regular)
        #expect(EpicType().weight(.label) == .bold)
        #expect(EpicType(atkinson: false, boldText: true).weight(.body) == .regular)
        #expect(EpicWeight.regular.face == Atkinson.regular)
        #expect(EpicWeight.bold.face == Atkinson.bold)
        #expect(EpicWeight.extraBold.face == Atkinson.extraBold)
    }

    /// Line heights as DESIGN.md gives them: Atkinson's own line is 1.3 times its size, so the transcript's 1.5 adds
    /// 0.2 of it between lines, and a title's 1.25 adds nothing.
    @Test func lineHeightsAreTheDesignsMultiples() {
        let type = EpicType()
        #expect(abs(type.lineSpacing(.transcript) - 20 * 0.2) < 0.5)
        #expect(abs(type.lineSpacing(.body) - 18 * 0.15) < 0.5)
        #expect(type.lineSpacing(.title) == 0)
        #expect(type.lineSpacing(.headline) < 0.5)
        for style in EpicTextStyle.allCases {
            #expect(type.lineSpacing(style) >= 0, "\(style)")
            #expect(EpicType(atkinson: false).lineSpacing(style) >= 0, "\(style)")
        }
    }

    // ----- Words -----

    @Test func voiceSpeedsInWords() {
        #expect(speedWords(1) == "Normal speed")
        #expect(speedWords(0.75) == "0.75 times")
        #expect(speedWords(1.25) == "1.25 times")
        #expect(speedWords(1.5) == "1.5 times")
        #expect(speedWords(2) == "2 times")
    }

    /// A game card is read as sentences: each part gets a full stop unless it ends a sentence already.
    @Test func aCardIsReadAsSentences() {
        #expect(sentences("The Werewolf", "In progress", "Who is it?", " 5 stories free ", "Carry on")
            == "The Werewolf. In progress. Who is it? 5 stories free. Carry on.")
        #expect(sentences("Noodle Rush", nil, "Talk your way to ramen.", "", "Play")
            == "Noodle Rush. Talk your way to ramen. Play.")
        #expect(sentences("Wait…", "Go!") == "Wait… Go!")
    }

    // ----- The transcript's highlight (HighlightTest.kt) -----

    private typealias Foreground = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    private typealias Background = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    private let line = "Hello there, friend"

    /// The words of [text]'s runs whose colour is set (or, [marked], whose background is), in order.
    private func coloured(_ text: AttributedString) -> [String] { words(text) { $0.attributes[Foreground.self] != nil } }

    private func marked(_ text: AttributedString) -> [String] { words(text) { $0.attributes[Background.self] != nil } }

    private func words(_ text: AttributedString, where test: (AttributedString.Runs.Run) -> Bool) -> [String] {
        text.runs.filter(test).map { String(text[$0.range].characters) }
    }

    @Test func aLineNotBeingSpokenIsDrawnAsItIs() {
        let text = transcriptText(line, saidChars: nil, highlight: true, wholeLine: false, colors: .dark)
        #expect(String(text.characters) == line)
        #expect(coloured(text).isEmpty)
        #expect(marked(text).isEmpty)
    }

    @Test func onlyTheCurrentWordIsHighlightedInInverseColours() {
        let c = EpicColors.light
        let text = transcriptText(line, saidChars: 8, highlight: true, wholeLine: true, colors: c)
        #expect(String(text.characters) == line)
        #expect(marked(text) == ["there,"])
        #expect(coloured(text) == ["there,"])
        let word = text.runs.first { $0.attributes[Background.self] != nil }
        #expect(word?.attributes[Background.self] == c.highlightBg)
        #expect(word?.attributes[Foreground.self] == c.highlightText)
    }

    @Test func withoutTheWholeLineTheWordsToComeAreHiddenButKeepTheirPlace() {
        let text = transcriptText(line, saidChars: 8, highlight: true, wholeLine: false, colors: .dark)
        // Every character is still there, so the bubble doesn't change size as the words appear.
        #expect(String(text.characters) == line)
        let hidden = text.runs.filter { $0.attributes[Foreground.self] == Color.clear }
        #expect(hidden.map { String(text[$0.range].characters) } == [" friend"])
    }

    @Test func withTheHighlightOffTheWordsAreAllTheSame() {
        let plain = transcriptText(line, saidChars: 8, highlight: false, wholeLine: true, colors: .dark)
        #expect(coloured(plain).isEmpty)
        #expect(marked(plain).isEmpty)
        // The whole line off still hides what's to come, with no word marked.
        let hiding = transcriptText(line, saidChars: 8, highlight: false, wholeLine: false, colors: .dark)
        #expect(marked(hiding).isEmpty)
        #expect(coloured(hiding) == [" friend"])
    }
}
