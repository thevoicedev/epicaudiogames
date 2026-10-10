// The tab shell as a player meets it: Android's MainTabsTest.kt, StoreSheetTest.kt and SettingsScreenTest.kt (Compose
// tests there) as UI tests here.

import XCTest

/**
 * The tabs (docs/DESIGN.md › Structure, › Tab bar, › Shop, › Settings): four tabs, each saying whether it's selected,
 * each screen's level-1 heading, the Shop's packs and its messages, Settings' sections and controls setting what they
 * say, Licences and back, and a keyboard: ⌘ with a tab's number, and in a game Escape and Space. On an iPhone the bar
 * is at the bottom; on an iPad from iPadOS 18, at the top. The app starts with no saves and no settings stored
 * (-EpicReset), no mic, and no pack server (buying says so, and buys nothing).
 */
final class TabsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheFourTabsSayWhichIsSelected() throws {
        let app = Tabs.launch()
        for (key, title) in Tabs.all {
            let tab = app.tab(key, title)
            XCTAssertTrue(tab.exists, "no \(title) tab")
            XCTAssertEqual(tab.label, title)
        }
        XCTAssertTrue(app.tab("games", "Games").isSelected)
        app.tab("shop", "Shop").tap()
        XCTAssertTrue(app.element("shop-heading").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab("shop", "Shop").isSelected)
        XCTAssertFalse(app.tab("games", "Games").isSelected)
        // Each tab's screen starts with its level-1 heading, named as the tab is.
        for (key, title) in Tabs.all {
            app.tab(key, title).tap()
            let heading = app.element("\(key)-heading")
            XCTAssertTrue(heading.waitForExistence(timeout: 5), "no \(title) heading")
            XCTAssertEqual(heading.label, title)
            XCTAssertTrue(app.tab(key, title).isSelected, "\(title) isn't selected")
        }
        app.shot("tabs-settings", in: self)
    }

    /// Every game with packs, its packs on the store sheet's rows; buying (with no pack server here) says why not, and
    /// that goes once the Shop is left.
    @MainActor
    func testTheShop() throws {
        let app = Tabs.launch()
        app.tab("shop", "Shop").tap()
        XCTAssertTrue(app.element("shop-heading").waitForExistence(timeout: 5))
        XCTAssertTrue(app.text("One-time purchases. No ads and no subscriptions. Packs download once, then play offline.")
            .exists)
        let section = app.element("shop-game-frootopia")
        XCTAssertTrue(section.waitForExistence(timeout: 5), "no Frootopia in the Shop")
        XCTAssertTrue(section.text("The Kingdom of Frootopia").exists)
        let buy = app.buttons["buy-frootopia-stories"]
        XCTAssertTrue(app.scrolledTo(buy), "no buy button")
        // Get until the price is known, then "Buy for" the price; either way VoiceOver hears the game and the pack.
        XCTAssertTrue(buy.label.hasPrefix("Get") || buy.label.hasPrefix("Buy for"), buy.label)
        XCTAssertTrue(buy.label.contains("The Kingdom of Frootopia, Stories 2 to 5"), buy.label)
        XCTAssertTrue(app.text("15 MB download").exists || app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH ' MB download'")).firstMatch.exists)
        app.shot("shop", in: self)
        buy.tap()
        let message = app.element("store-message")
        XCTAssertTrue(message.waitForExistence(timeout: 5), "buying said nothing")
        XCTAssertEqual(message.label, "Packs can't be downloaded in this version of the app yet.")
        XCTAssertTrue(app.scrolledTo(app.buttons["restore"]))
        XCTAssertEqual(app.buttons["restore"].label, "Restore purchases")
        XCTAssertTrue(app.text("Payments are handled by the App Store.").exists)
        // Leaving the Shop, what the store said there goes.
        app.tab("games", "Games").tap()
        app.tab("shop", "Shop").tap()
        XCTAssertTrue(app.element("shop-heading").waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("store-message").exists, "the message stayed")
    }

    /// Settings: every section, and each kind of control setting what it says (the settings stored are forgotten at
    /// the next launch, -EpicReset).
    @MainActor
    func testSettingsSetWhatTheySay() throws {
        let app = Tabs.launch()
        app.tab("settings", "Settings").tap()
        XCTAssertTrue(app.element("settings-heading").waitForExistence(timeout: 5))
        for section in ["Sound and voice", "Microphone", "Appearance", "Transcript", "Privacy", "Help and about"] {
            XCTAssertTrue(app.text(section).exists, "no \(section) section")
        }
        // The voice speed: a step faster, its value in words.
        XCTAssertTrue(app.text("Normal speed").exists)
        let faster = app.buttons["Faster"]
        XCTAssertTrue(app.scrolledTo(faster))
        faster.tap()
        XCTAssertTrue(app.text("1.25 times").waitForExistence(timeout: 5))
        // A switch: the whole row, on, then off.
        let intro = app.switches["setting-introSound"]
        XCTAssertTrue(app.scrolledTo(intro), "no intro sound switch")
        XCTAssertEqual(intro.value as? String, "1")
        intro.tap()
        XCTAssertEqual(intro.value as? String, "0")
        // A choice among its group's.
        let never = app.buttons["setting-micAuto-never"]
        XCTAssertTrue(app.scrolledTo(never))
        XCTAssertFalse(never.isSelected)
        never.tap()
        XCTAssertTrue(never.isSelected)
        XCTAssertFalse(app.buttons["setting-micAuto-notWithScreenReader"].isSelected)
        // The microphone: its state, and one way to turn it on when it's off.
        let mic = app.element("setting-mic")
        XCTAssertTrue(app.scrolledTo(mic))
        if mic.label == "The microphone is off" {
            XCTAssertTrue(app.buttons["setting-micAllow"].exists != app.buttons["setting-micSettings"].exists)
        } else {
            XCTAssertEqual(mic.label, "The microphone is allowed")
        }
        // A theme, which the app takes at once: High contrast, then back to the phone's.
        let contrast = app.buttons["setting-theme-contrast"]
        XCTAssertTrue(app.scrolledTo(contrast))
        contrast.tap()
        XCTAssertTrue(contrast.isSelected)
        app.shot("settings-contrast", in: self)
        app.buttons["setting-theme-system"].tap()
        XCTAssertTrue(app.buttons["setting-theme-system"].isSelected)
        // Privacy: what's shared, and deleting asks first.
        let share = app.switches["setting-analytics"]
        XCTAssertTrue(app.scrolledTo(share))
        XCTAssertEqual(share.value as? String, "1")
        let delete = app.buttons["setting-deleteUsageData"]
        XCTAssertTrue(app.scrolledTo(delete))
        delete.tap()
        let alert = app.alerts["Delete your usage data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        let result = app.element("setting-deleteUsageData-result")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "deleting said nothing")
        XCTAssertTrue(result.label.contains("hasn't sent any usage data"), result.label)
        XCTAssertTrue(app.scrolledTo(app.element("setting-version")))
        XCTAssertTrue(app.element("setting-version").label.hasPrefix("Version "))
    }

    /// Settings › Licences: the font's licence, whole, and back to Settings.
    @MainActor
    func testLicencesAndBack() throws {
        let app = Tabs.launch()
        app.tab("settings", "Settings").tap()
        let licences = app.buttons["setting-licences"]
        XCTAssertTrue(app.scrolledTo(licences))
        licences.tap()
        XCTAssertTrue(app.element("licences-heading").waitForExistence(timeout: 5))
        XCTAssertTrue(app.text("Atkinson Hyperlegible Next").exists)
        // The licence from the app's content; a build with none links to it.
        XCTAssertTrue(app.text("PREAMBLE").waitForExistence(timeout: 5)
            || app.buttons["The SIL Open Font License, on its website"].exists)
        app.shot("licences", in: self)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.element("settings-heading").waitForExistence(timeout: 5) || licences.waitForExistence(timeout: 5))
        XCTAssertFalse(app.element("licences-heading").exists)
    }

    /// Settings › How to play goes to the Help tab, on playing with your voice.
    @MainActor
    func testHowToPlayGoesToHelp() throws {
        let app = Tabs.launch()
        app.tab("settings", "Settings").tap()
        let howTo = app.buttons["setting-howToPlay"]
        XCTAssertTrue(app.scrolledTo(howTo))
        howTo.tap()
        let heading = app.element("help-page-heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Playing with your voice")
        XCTAssertTrue(app.tab("help", "Help").isSelected)
    }

    /**
     * A keyboard (docs/DESIGN.md › Tablets… › Keyboard): ⌘ with a tab's number picks it; in a game, Escape pauses and
     * carries on, and Space is the one button. Skipped where XCTest can't press keys.
     */
    @MainActor
    func testTheKeyboard() throws {
        let app = Tabs.launch()
        try app.press("2", command: true)
        XCTAssertTrue(app.element("shop-heading").waitForExistence(timeout: 5), "⌘2 isn't the Shop")
        try app.press("4", command: true)
        XCTAssertTrue(app.element("settings-heading").waitForExistence(timeout: 5), "⌘4 isn't Settings")
        try app.press("3", command: true)
        XCTAssertTrue(app.element("help-heading").waitForExistence(timeout: 5), "⌘3 isn't Help")
        try app.press("1", command: true)
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5), "⌘1 isn't Games")
        // A game: Space skips its voice, Escape pauses, and Space carries on.
        let card = app.element("game-noodle-rush")
        XCTAssertTrue(app.scrolledTo(card))
        card.tap()
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 20), "Noodle Rush isn't speaking")
        try app.press(" ")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your turn!'")).firstMatch
            .waitForExistence(timeout: 10), "Space didn't skip")
        try app.press("\u{1b}")
        XCTAssertTrue(app.element("paused").waitForExistence(timeout: 5), "Escape didn't pause")
        try app.press(" ")
        XCTAssertTrue(app.element("paused").waitForNonExistence(timeout: 5), "Space didn't carry on")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 10))
    }
}

/// The app as these tests launch it, and its tabs.
@MainActor
private enum Tabs {
    /// The tabs' keys and names, in the bar's order.
    static let all = [("games", "Games"), ("shop", "Shop"), ("help", "Help"), ("settings", "Settings")]

    static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Straight to Games: no intro, no onboarding, no usage data sent from a test (DebugLaunch).
        app.launchArguments = [
            "-EpicReset", "YES", "-EpicMic", "off", "-EpicPacksURL", "", "-EpicNoIntro", "YES", "-EpicSkipOnboarding",
            "YES", "-EpicAnalytics", "off",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 15))
        return app
    }
}

@MainActor
private extension XCUIElement {
    /// The text showing [label] (a heading, a line).
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}

@MainActor
private extension XCUIApplication {
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /**
     * A tab in the tab bar: by its identifier ("tab-shop", which SwiftUI may or may not hand on from the tab's label to
     * the bar's button), else by its name, in the bar (an iPhone's, or an iPad's before iPadOS 18) or as a button (an
     * iPad's tab bar from iPadOS 18).
     */
    func tab(_ key: String, _ title: String) -> XCUIElement {
        let byId = element("tab-\(key)")
        if byId.exists { return byId }
        let inBar = tabBars.buttons[title]
        if inBar.exists { return inBar }
        return buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// [element] scrolled into view in the screen showing (a few swipes at most), and there.
    func scrolledTo(_ element: XCUIElement) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /**
     * [key] pressed on a hardware keyboard (with ⌘ if [command]): XCUIElement's typeKey(_:modifierFlags:), looked up
     * as the app runs, so these tests build whichever XCTest the Mac has; skipped where it can't press keys.
     */
    func press(_ key: String, command: Bool = false) throws {
        let selector = NSSelectorFromString("typeKey:modifierFlags:")
        guard responds(to: selector) else { throw XCTSkip("XCTest can't press keys here") }
        typealias TypeKey = @convention(c) (AnyObject, Selector, NSString, UInt) -> Void
        let typeKey = unsafeBitCast(method(for: selector), to: TypeKey.self)
        // XCUIKeyModifierFlags: Command is 1 << 4.
        typeKey(self, selector, key as NSString, command ? 1 << 4 : 0)
    }

    func shot(_ name: String, in test: XCTestCase) {
        let shot = XCTAttachment(screenshot: screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}
