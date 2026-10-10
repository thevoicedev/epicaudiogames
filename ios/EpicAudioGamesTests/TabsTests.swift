// TabsTest.kt: the tab shell's pure parts: the tabs, their names in the usage data, the window's layouts, and
// Settings' choices in words (and Delete my usage data's).

import Foundation
import SwiftUI
import Testing
@testable import EpicAudioGames

/**
 * The tab shell's pure parts (docs/DESIGN.md › Structure, › Tablets…): the tabs' order, their ⌘ numbers, and the names
 * the usage data gives them and the Shop's sources (web/analytics/events.json, which the server checks every event
 * against), the window's width classes and when the game takes two panes or the Games tab two columns, and Settings'
 * choices in words. Android: TabsTest.kt.
 */
@MainActor
struct TabsTests {
    @Test func theTabsAreGamesShopHelpAndSettingsInThatOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Games", "Shop", "Help", "Settings"])
        #expect(AppTab.allCases.map(\.symbol) == ["headphones", "bag", "questionmark.circle", "gearshape"])
        // ⌘ and the tab's number.
        #expect(AppTab.allCases.map(\.number) == [1, 2, 3, 4])
    }

    @Test func theTabsAndShopSourcesAreNamedAsTheUsageDataAllows() throws {
        #expect(AppTab.allCases.map(\.key) == (try allowed("tab_view", "tab")))
        #expect(ShopSource.allCases.map(\.key) == (try allowed("shop_view", "source")))
    }

    /// Compact under 600 pt (or whenever iOS says the width is compact), medium to 839, expanded from 840.
    @Test func theWindowsWidthClass() {
        #expect(WidthClass.of(sizeClass: .compact, width: 390) == .compact)
        #expect(WidthClass.of(sizeClass: .regular, width: 599) == .compact)
        #expect(WidthClass.of(sizeClass: .regular, width: 600) == .medium)
        #expect(WidthClass.of(sizeClass: .regular, width: 834) == .medium)        // an 11-inch iPad upright
        #expect(WidthClass.of(sizeClass: .regular, width: 840) == .expanded)
        #expect(WidthClass.of(sizeClass: .regular, width: 1032) == .expanded)     // a 13-inch iPad upright
        // A wide window iOS calls compact (Split View on a smaller iPad) is laid out as one.
        #expect(WidthClass.of(sizeClass: .compact, width: 700) == .compact)
        #expect(WidthClass.of(sizeClass: nil, width: 900) == .expanded)
    }

    @Test func theGameTakesTwoPanesOnAWideWindow() {
        #expect(twoPanes(.expanded, landscape: true))
        #expect(twoPanes(.expanded, landscape: false))
        #expect(twoPanes(.medium, landscape: true))
        #expect(!twoPanes(.medium, landscape: false))
        #expect(!twoPanes(.compact, landscape: true))
        #expect(!twoPanes(.compact, landscape: false))
        // From the window: an 11-inch iPad on its side has two, upright one; a phone, one.
        #expect(EpicWindow.of(sizeClass: .regular, size: CGSize(width: 1194, height: 834)).gameHasTwoPanes)
        #expect(!EpicWindow.of(sizeClass: .regular, size: CGSize(width: 834, height: 1194)).gameHasTwoPanes)
        #expect(EpicWindow.of(sizeClass: .regular, size: CGSize(width: 1032, height: 1376)).gameHasTwoPanes)
        #expect(!EpicWindow.of(sizeClass: .compact, size: CGSize(width: 402, height: 874)).gameHasTwoPanes)
        #expect(EpicWindow().widthClass == .compact)
    }

    @Test func settingsChoicesInWords() {
        #expect(AppSettings.musicVolumes.map(volumeWords) == ["Off", "25%", "50%", "75%", "100%"])
        #expect(AppSettings.textScales.map(textSizeWords) == ["Standard", "Large", "Larger"])
        #expect(AnswerTime.allCases.map(\.duration.components.seconds) == [6, 10, 15])
    }

    /// Settings › Privacy › Delete my usage data says how it went (TabsTest.kt's).
    @Test func deleteMyUsageDataSaysHowItWent() {
        #expect(deletionWords(.deleted, sharing: true).words == "Your usage data is deleted.")
        #expect(deletionWords(.deleted, sharing: true).kind == .success)
        #expect(deletionWords(.failed, sharing: true).kind == .error)
        // Nothing to find: none sent under the ID; or, turned off, the ID forgotten (and what was sent goes in time).
        let none = deletionWords(.nothingSent, sharing: true).words
        let off = deletionWords(.nothingSent, sharing: false).words
        #expect(none.contains("hasn't sent any usage data"), "\(none)")
        #expect(off.contains("forgot its random ID when usage data was turned off"), "\(off)")
        #expect(off.contains("13 months"), "\(off)")
    }

    /// An event's property's allowed values, from the whitelist: `"tab_view": { "tab": "enum:games,shop,…" }`.
    private func allowed(_ event: String, _ property: String) throws -> [String] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("web/analytics/events.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let events = try #require(json?["events"] as? [String: Any], "no events in events.json")
        let props = try #require(events[event] as? [String: Any], "\(event) isn't in events.json")
        let type = try #require(props[property] as? String, "\(event).\(property) isn't in events.json")
        #expect(type.hasPrefix("enum:"))
        return type.dropFirst("enum:".count).split(separator: ",").map(String.init)
    }
}
