// Xcode's accessibility audit on the app's main screens (no Kotlin counterpart; the plan's Phase 8).

import XCTest

/**
 * performAccessibilityAudit() on the game list, a game asking a question (its chips showing), an end panel and the
 * store sheet, in the default theme; the game list and a game in each theme; a game at the largest text size, in its
 * compact layout; and the tabs' screens: the Shop, Settings (its top and further down), Licences and Help. Then, in
 * each of docs/DESIGN.md's looks ([looks]: Dark, Light, High contrast, Light with the phone's Increase Contrast, and
 * the largest text size): the intro, each onboarding page (VoiceOver's among them), Help's list and a topic, Settings,
 * the Shop, and a game listening, its help sheet and its pause. What the audit flags and the app means is let through
 * below, each with its reason (docs/IOS_PARITY.md lists them too). Nothing of the app's own stops growing with the
 * text any more, so the only Dynamic Type issue let through is the system's tab bar's (it has the Large Content Viewer
 * instead).
 *
 * On an iPad too (docs/DESIGN.md › Tablets…), the destination given to xcodebuild deciding which, e.g.
 * `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'`: there the Games tab has two columns, and two
 * tests run that a phone skips (the game in two panes, on its side; the Games grid on its side). An iPad's screenshots
 * are named with "-ipad".
 */
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTheGameList() throws {
        let app = launch()
        try audit(app, "home")
    }

    /// Settings › Theme (launch arguments, AppSettings): Light, Dark and High contrast.
    @MainActor
    func testTheGameListInEachTheme() throws {
        for theme in ["light", "dark", "contrast"] {
            let app = launch(["-settings.theme", theme])
            try audit(app, "home-\(theme)")
            app.terminate()
        }
    }

    /// Noodle Rush asking, in each theme: the transcript's bubbles, the chips, the circle and the answer bar.
    @MainActor
    func testAGameInEachTheme() throws {
        for theme in ["light", "dark", "contrast"] {
            let app = launch([
                "-settings.theme", theme, "-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay", "yes",
            ])
            XCTAssertTrue(app.buttons["answer-yes"].waitForExistence(timeout: 40), "no chips (\(theme))")
            sleep(1)
            try audit(app, "game-asking-\(theme)")
            app.terminate()
        }
    }

    /// The largest accessibility text size: the compact game layout (the title in the transcript, the circle 88 pt, the
    /// answer bar in two rows).
    @MainActor
    func testAGameAtTheLargestTextSize() throws {
        let app = launch([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay", "yes",
        ])
        XCTAssertTrue(app.buttons["answer-yes"].waitForExistence(timeout: 40), "no chips")
        sleep(1)
        try audit(app, "game-asking-axxxl")
    }

    /// Noodle Rush's second question, its chips (Yes, No) at the transcript's end.
    @MainActor
    func testAGameAsking() throws {
        let app = launch(["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay", "yes"])
        XCTAssertTrue(app.buttons["answer-yes"].waitForExistence(timeout: 40), "no chips")
        XCTAssertTrue(app.staticTexts["Your turn!"].waitForExistence(timeout: 20))
        sleep(1)
        try audit(app, "game-asking")
    }

    /// Noodle Rush's Best Friend ending.
    @MainActor
    func testAnEndPanel() throws {
        let app = launch(["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay",
                          "yes|yes|wait|yes|yes|yes|yes|no|yes|yes|yes|yes"])
        let end = app.descendants(matching: .any).matching(identifier: "end-panel").firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 120), "no end panel")
        sleep(1)
        try audit(app, "end-panel")
    }

    @MainActor
    func testTheStoreSheet() throws {
        let app = launch(["-EpicStore", "frootopia"])
        let sheet = app.descendants(matching: .any).matching(identifier: "store-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "no store sheet")
        sleep(1)
        try audit(app, "store-sheet")
    }

    // ----- The tabs -----

    /// The Shop: every game's packs, with a message (buying with no pack server says why not).
    @MainActor
    func testTheShop() throws {
        let app = launch(["-EpicPacksURL", ""])
        open(app, "shop", "Shop")
        try audit(app, "shop")
        let buy = app.buttons["buy-frootopia-stories"]
        XCTAssertTrue(scrolled(app, to: buy), "no buy button")
        buy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["store-message"].waitForExistence(timeout: 5))
        sleep(1)
        try audit(app, "shop-message")
    }

    /// Settings, its top and further down (the choices, the swatches, the text preview, the privacy and about rows),
    /// in the default theme and in each of the looks.
    @MainActor
    func testSettings() throws {
        let variants = [("settings", [String]())] + Self.looks.map { ("settings-\($0.name)", $0.args) }
        for (name, extra) in variants {
            let app = launch(extra)
            open(app, "settings", "Settings")
            try audit(app, name)
            for part in 1...3 {
                app.swipeUp(velocity: .slow)
                app.swipeUp(velocity: .slow)
                sleep(1)
                try audit(app, "\(name)-\(part)")
            }
            app.terminate()
        }
    }

    /// Settings › Licences: the font's licence.
    @MainActor
    func testLicences() throws {
        let app = launch()
        open(app, "settings", "Settings")
        let licences = app.buttons["setting-licences"]
        XCTAssertTrue(scrolled(app, to: licences))
        licences.tap()
        XCTAssertTrue(app.descendants(matching: .any)["licences-heading"].waitForExistence(timeout: 5))
        sleep(1)
        try audit(app, "licences")
    }

    @MainActor
    func testHelp() throws {
        let app = launch()
        open(app, "help", "Help")
        try audit(app, "help")
    }

    // ----- docs/DESIGN.md's looks -----

    /**
     * The looks the new screens are audited in: Dark, Light and High contrast (-EpicTheme), Light with the phone's
     * Increase Contrast (-EpicContrast increased: Light + increased contrast's palette), and the largest text size.
     */
    private static let looks: [(name: String, args: [String])] = [
        ("dark", ["-EpicTheme", "dark"]),
        ("light", ["-EpicTheme", "light"]),
        ("contrast", ["-EpicTheme", "contrast"]),
        ("light-increased", ["-EpicTheme", "light", "-EpicContrast", "increased"]),
        ("axxxl", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ]

    /// The intro, held on screen (-EpicHoldIntro): one element over the navy, its wordmark at each text size.
    @MainActor
    func testTheIntroInEachLook() throws {
        for look in Self.looks {
            let app = launch(look.args + ["-EpicIntro", "YES", "-EpicHoldIntro", "YES"], until: "intro")
            sleep(1)
            try audit(app, "intro-\(look.name)")
            app.terminate()
        }
    }

    /// Each onboarding page, VoiceOver's among them (-EpicVoiceOver YES, which also keeps the welcome from being read
    /// by itself).
    @MainActor
    func testEachOnboardingPageInEachLook() throws {
        for look in Self.looks {
            let app = launch(
                look.args + ["-EpicOnboarding", "YES", "-EpicVoiceOver", "YES"], until: "onboarding-welcome")
            for page in ["welcome", "mic", "comfort", "screen-reader", "ready"] {
                let shown = app.descendants(matching: .any)["onboarding-\(page)"]
                XCTAssertTrue(shown.waitForExistence(timeout: 5), "no \(page) page (\(look.name))")
                sleep(1)
                try audit(app, "onboarding-\(page)-\(look.name)")
                let next = app.buttons["onboarding-next"]
                if next.exists { next.tap() }
            }
            app.terminate()
        }
    }

    /// Help: the list, and a topic's page (Playing with your voice: its Listen and paragraphs).
    @MainActor
    func testHelpInEachLook() throws {
        for look in Self.looks {
            let app = launch(look.args + ["-EpicTab", "help"], until: "help-heading")
            sleep(1)
            try audit(app, "help-\(look.name)")
            let topic = app.buttons["help-topic-voice"]
            XCTAssertTrue(scrolled(app, to: topic), "no Playing with your voice (\(look.name))")
            topic.tap()
            XCTAssertTrue(app.descendants(matching: .any)["help-page-heading"].waitForExistence(timeout: 5))
            sleep(1)
            try audit(app, "help-topic-\(look.name)")
            app.terminate()
        }
    }

    /// The Shop's top: its heading, what buying is like, and the first games' packs.
    @MainActor
    func testTheShopInEachLook() throws {
        for look in Self.looks {
            let app = launch(look.args + ["-EpicTab", "shop", "-EpicPacksURL", ""], until: "shop-heading")
            sleep(1)
            try audit(app, "shop-\(look.name)")
            app.terminate()
        }
    }

    /**
     * Noodle Rush listening (its second question: the first answered by -EpicSay, the script then heard to its end, so
     * it listens on), then its help sheet from the menu, then the pause that leaves: the game's three overlays.
     */
    @MainActor
    func testAGameListeningItsHelpSheetAndPausedInEachLook() throws {
        for look in Self.looks {
            let app = launch(
                look.args + ["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicHear", "~", "-EpicSay", "yes"])
            let reply = app.staticTexts.matching(identifier: "reply").firstMatch
            XCTAssertTrue(reply.waitForExistence(timeout: 60), "no answer (\(look.name))")
            XCTAssertTrue(app.staticTexts["Listening…"].waitForExistence(timeout: 30), "not listening (\(look.name))")
            sleep(1)
            try audit(app, "game-listening-\(look.name)")
            app.buttons["More"].tap()
            let howTo = app.buttons["How to play"]
            XCTAssertTrue(howTo.waitForExistence(timeout: 5), "no How to play (\(look.name))")
            howTo.tap()
            XCTAssertTrue(app.descendants(matching: .any)["help-sheet"].waitForExistence(timeout: 10))
            sleep(1)
            try audit(app, "help-sheet-\(look.name)")
            app.buttons["help-close"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["paused"].waitForExistence(timeout: 10), "not paused")
            sleep(1)
            try audit(app, "game-paused-\(look.name)")
            app.terminate()
        }
    }

    // ----- An iPad's layouts (skipped on a phone) -----

    /// The Games tab on an iPad on its side: two columns of cards.
    @MainActor
    func testTheGameListAsAGridOnAnIPad() throws {
        let app = launch()
        try XCTSkipUnless(isPad(app), "a phone has one column")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        try audit(app, "home-grid")
    }

    /// A game on an iPad on its side: two panes, the transcript beside the circle and the answers.
    @MainActor
    func testAGameInTwoPanesOnAnIPad() throws {
        let app = launch(["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay", "yes"])
        try XCTSkipUnless(isPad(app), "a phone has one pane")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["answer-yes"].waitForExistence(timeout: 40), "no chips")
        sleep(2)
        try audit(app, "game-two-panes")
    }

    // ----- The app and the audit -----

    /// The tab [key] ([title]) picked, its heading showing.
    @MainActor
    private func open(_ app: XCUIApplication, _ key: String, _ title: String) {
        let byId = app.descendants(matching: .any)["tab-\(key)"]
        let tab = byId.exists ? byId
            : app.tabBars.buttons[title].exists ? app.tabBars.buttons[title]
            : app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["\(key)-heading"].waitForExistence(timeout: 10), "no \(title)")
        sleep(1)
    }

    /// [element] scrolled into view (a few swipes at most), and there.
    @MainActor
    private func scrolled(_ app: XCUIApplication, to element: XCUIElement) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// The app runs on an iPad (its window at least 600 pt both ways; this runner may be an iPhone app there, so its
    /// own device idiom doesn't say).
    @MainActor
    private func isPad(_ app: XCUIApplication) -> Bool {
        let size = app.windows.firstMatch.frame.size
        return min(size.width, size.height) >= 600
    }

    /**
     * The app with no saves and no mic (taps and typing), straight to Games (no intro, no onboarding, and no usage data
     * sent from a test), and [extra] launch arguments (DebugLaunch, which can bring the intro or onboarding back); then
     * [until] (an identifier) showing, or Games or a game.
     */
    @MainActor
    private func launch(_ extra: [String] = [], until: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-EpicReset", "YES", "-EpicMic", "off", "-EpicNoIntro", "YES", "-EpicSkipOnboarding", "YES",
            "-EpicAnalytics", "off",
        ] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        if let until {
            XCTAssertTrue(app.descendants(matching: .any)[until].waitForExistence(timeout: 15), "no \(until)")
        } else {
            XCTAssertTrue(app.descendants(matching: .any)["games-heading"].waitForExistence(timeout: 15)
                || app.descendants(matching: .any)["talking-circle"].waitForExistence(timeout: 15))
        }
        return app
    }

    /// The audit, every issue but those [Exceptions] lets through; a screenshot is kept either way (and written to
    /// the folder in EPIC_SHOTS when the runner has it).
    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String) throws {
        let name = isPad(app) ? "\(name)-ipad" : name
        let image = app.screenshot()
        let shot = XCTAttachment(screenshot: image)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["EPIC_SHOTS"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("audit-\(name).png"))
        }
        var allowed: [String] = []
        // The sheet that's up, if one is: the store sheet, or a game's help sheet.
        let store = app.descendants(matching: .any)["store-sheet"]
        let help = app.descendants(matching: .any)["help-sheet"]
        let sheetFrame = store.exists ? store.frame : help.exists ? help.frame : nil
        // The transcript, unless a sheet is over it (then the words checked are the sheet's own).
        let feed = app.scrollViews["feed"]
        let feedFrame = sheetFrame == nil && feed.exists ? feed.frame : nil
        let bar = app.tabBars.firstMatch
        let barFrame = bar.exists ? bar.frame : nil
        try app.performAccessibilityAudit { issue in
            let e = issue.element
            print("AUDIT ISSUE \(name): \(issue.auditType.rawValue) \(issue.compactDescription) | "
                + "\(issue.detailedDescription) | "
                + "\(e.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)" } ?? "-")")
            guard let why = Exceptions.allows(issue, feed: feedFrame, sheet: sheetFrame, bar: barFrame) else {
                return false
            }
            allowed.append("\(issue.auditType): \(issue.element?.label ?? "-") (\(why))")
            return true
        }
        if !allowed.isEmpty {
            let note = XCTAttachment(string: allowed.joined(separator: "\n"))
            note.name = "\(name): let through"
            note.lifetime = .keepAlways
            add(note)
            print("AUDIT \(name) let through:\n" + allowed.joined(separator: "\n"))
        }
    }
}

/// What the audit flags that the app means, and why.
@MainActor
private enum Exceptions {
    /// The tabs' names in the tab bar.
    private static let tabs: Set<String> = ["Games", "Shop", "Help", "Settings"]

    /// [feed]: where the transcript shows on the screen, if a game is open; [sheet]: the store sheet or the help sheet,
    /// if one is up; [bar]: the tab bar, if the tabs show.
    static func allows(_ issue: XCUIAccessibilityAuditIssue, feed: CGRect?, sheet: CGRect?, bar: CGRect?) -> String? {
        let frame = issue.element?.frame
        // Words (a transcript line, a note), not a control: the buttons around the transcript (the header's, the
        // circle, the answers, beside it on an iPad) are checked wherever they are.
        let line = issue.element?.elementType == .staticText
        // One of the tab bar's own tabs.
        let tab = issue.element?.elementType == .button && tabs.contains(issue.element?.label ?? "")
        // A tab's content scrolled under the tab bar (a list or a page goes on behind it): the audit measures the bar
        // drawn over it there, and it can't be touched until it's scrolled out from under it. Not with the store sheet
        // up: the bar is behind the sheet then, and the sheet's own rows over it are checked.
        let underBar = sheet == nil && !tab && issue.element?.elementType != .tabBar
            && bar.map { bar in frame.map { $0.intersects(bar) } ?? false } ?? false
        switch issue.auditType {
        case .contrast:
            // The transcript's lines scrolled out of its view: the audit measures what's drawn over them there (the
            // circle, the header), not their words on their bubble.
            if line, let feed, let frame, !feed.insetBy(dx: -1, dy: -1).contains(frame) {
                return "a transcript line scrolled out of view"
            }
            // The system's tab bar draws the tabs not picked in its own grey (docs/DESIGN.md › Tab bar: iOS uses the
            // system's): which tab is picked is also its filled symbol, and VoiceOver says "Selected".
            if tab { return "a tab in the system's tab bar" }
            if underBar { return "scrolled under the tab bar" }
        case .textClipped:
            // The text box is one line: what's typed scrolls sideways in it (it grows with the text size).
            if issue.element?.identifier == "answer-field" { return "a one-line text box" }
            // A transcript line partly scrolled out of its view (the largest text): it scrolls into view whole.
            if line, let feed, let frame, !feed.insetBy(dx: -1, dy: -1).contains(frame) {
                return "a transcript line partly scrolled out of view"
            }
            // The store sheet is as tall as what's in it, up to the screen's height, and the help sheet the screen's:
            // with the largest text their rows go past the foot, and they scroll to them (seen at AccessibilityXXXL).
            if let sheet, let frame, frame.minY >= sheet.minY { return "the sheet scrolls" }
            if underBar { return "scrolled under the tab bar" }
        case .hitRegion:
            if underBar { return "scrolled under the tab bar" }
        case .dynamicType:
            // The system's tab bar keeps its labels' size, and shows a tab's name large on a long press instead (the
            // Large Content Viewer, docs/DESIGN.md › Tab bar).
            if tab { return "a tab in the system's tab bar" }
        case .elementDetection:
            // What's under the sheet showing around it (iOS 26 floats it): VoiceOver rightly stays in the sheet.
            if sheet != nil && issue.element == nil { return "what's around the sheet" }
        default:
            break
        }
        return nil
    }
}
