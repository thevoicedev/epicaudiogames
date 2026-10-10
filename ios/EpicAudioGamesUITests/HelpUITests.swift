// Help as a player meets it: Android's HelpScreenTest.kt (a Compose test there) as UI tests here.

import XCTest

/**
 * Help (docs/DESIGN.md › Help): this app's topics from the build's own content/app/app.json, in order (iOS's own:
 * "Using VoiceOver", not TalkBack); a topic's page with its heading, Listen (Pause and "Playing" while it reads), its
 * words and its links; back to the list; Settings › How to play; and the help sheet a game opens from its menu and from
 * the pause, the game waiting for it paused. On a phone a topic's page is pushed over the list; on an iPad they're side
 * by side, the topic showing selected. The app starts with no saves and no settings stored, no mic, straight to Games.
 */
final class HelpUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// iOS's topics in the manifest's order, each a row with its title; then Show the welcome again, and our address.
    @MainActor
    func testTheListHasThisAppsTopicsInOrder() throws {
        let app = Help.launch(["-EpicTab", "help"])
        XCTAssertTrue(app.element("help-heading").waitForExistence(timeout: 15))
        XCTAssertEqual(app.element("help-heading").label, "Help")
        guard app.buttons["help-topic-getting-started"].exists else {
            // A build without content/app/ (placeholder content has it): the website's help.
            XCTAssertTrue(app.buttons["help-support"].exists)
            throw XCTSkip("this build has no help topics")
        }
        // In the manifest's order, iOS's own (one list, all of it there to read).
        XCTAssertEqual(app.identifiers(starting: "help-topic-"), Help.topics.map { "help-topic-\($0.0)" })
        for (id, title) in Help.topics {
            let row = app.buttons["help-topic-\(id)"]
            XCTAssertTrue(app.scrolledTo(row), "no \(id) row")
            XCTAssertTrue(row.label.hasPrefix(title), "\(id): \(row.label)")
        }
        let talkBack = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Using TalkBack")).firstMatch
        XCTAssertFalse(talkBack.exists, "Android's topic")
        app.shot("help", in: self)
        let welcome = app.buttons["help-welcome"]
        XCTAssertTrue(app.scrolledTo(welcome))
        XCTAssertEqual(welcome.label, "Show the welcome again")
        let email = app.buttons["help-email"]
        XCTAssertTrue(app.scrolledTo(email))
        XCTAssertEqual(email.label, "Email james@hugo.fm")
    }

    /// A topic's page: its heading, Listen, its words and its links; Back (a phone's) or Escape returns to the list.
    @MainActor
    func testATopicHasItsHeadingListenWordsAndLinks() throws {
        let app = Help.launch(["-EpicTab", "help"])
        XCTAssertTrue(app.element("help-heading").waitForExistence(timeout: 15))
        let row = app.buttons["help-topic-contact"]
        let there = app.scrolledTo(row)
        try XCTSkipUnless(there, "this build has no help topics")
        row.tap()
        let heading = app.element("help-page-heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Contact and privacy")
        XCTAssertTrue(app.text("Email us at james@hugo.fm.").exists)
        let link = app.element("help-link-0")
        XCTAssertTrue(app.scrolledTo(link))
        XCTAssertEqual(link.label, "Email james@hugo.fm")
        app.shot("help-contact", in: self)
        if app.isPad {
            // Side by side: the list stays, the topic showing selected.
            XCTAssertTrue(app.buttons["help-topic-contact"].isSelected)
            XCTAssertFalse(app.buttons["help-topic-voice"].isSelected)
        } else {
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.element("help-heading").waitForExistence(timeout: 5), "not back on the list")
            XCTAssertFalse(app.element("help-page-heading").exists)
        }
    }

    /// Listen reads the page: Pause, "Playing", while it does; Pause stops it, and it's Listen again.
    @MainActor
    func testListenReadsThePageAndPauseStopsIt() throws {
        let app = Help.launch(["-EpicHelp", "voice"])
        let heading = app.element("help-page-heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 15), "-EpicHelp voice didn't open it")
        XCTAssertEqual(heading.label, "Playing with your voice")
        let listen = app.buttons["help-listen"]
        guard listen.exists else { throw XCTSkip("this build has no help clips") }
        XCTAssertEqual(listen.label, "Listen")
        listen.tap()
        XCTAssertEqual(listen.label, "Pause")
        XCTAssertEqual(listen.value as? String, "Playing")
        sleep(2)
        app.shot("help-listening", in: self)
        listen.tap()
        XCTAssertEqual(listen.label, "Listen")
    }

    /// A game's How to play, from its menu: the help sheet on playing with your voice, over the game, paused; All help
    /// topics, another topic, then Close: the game still paused. The pause's How to play opens it again.
    @MainActor
    func testHowToPlayInAGameIsASheetOverItPaused() throws {
        let app = Help.launch(["-EpicOpen", "noodle-rush"])
        XCTAssertTrue(app.element("talking-circle").waitForExistence(timeout: 30), "the game didn't open")
        app.buttons["More"].tap()
        let howTo = app.buttons["How to play"]
        XCTAssertTrue(howTo.waitForExistence(timeout: 5))
        howTo.tap()
        let sheet = app.element("help-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no help sheet")
        let heading = app.element("help-page-heading")
        if heading.waitForExistence(timeout: 5) {
            XCTAssertEqual(heading.label, "Playing with your voice")
            app.shot("help-sheet", in: self)
            app.buttons["help-all-topics"].tap()
            XCTAssertTrue(app.element("help-heading").waitForExistence(timeout: 5), "no list in the sheet")
            XCTAssertFalse(app.buttons["help-welcome"].exists, "the welcome in the sheet")
            let typing = app.buttons["help-topic-typing"]
            XCTAssertTrue(app.scrolledTo(typing))
            typing.tap()
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            XCTAssertEqual(heading.label, "Typing and choosing answers")
        }
        app.buttons["help-close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "the sheet didn't close")
        // The game waits, paused (only the pause is found: it's modal), and its How to play opens the sheet again.
        let paused = app.element("paused")
        XCTAssertTrue(paused.waitForExistence(timeout: 5), "the game isn't paused")
        app.buttons["paused-help"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no help sheet from the pause")
        app.buttons["help-close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        app.buttons["paused-carry-on"].tap()
        XCTAssertTrue(app.element("talking-circle").waitForExistence(timeout: 5), "the game is still open")
    }
}

/// The app as these tests launch it, and the topics they expect.
@MainActor
private enum Help {
    /// iOS's topics, in content/app/app.json's order, by id and title.
    static let topics = [
        ("getting-started", "Getting started"), ("voice", "Playing with your voice"),
        ("screen-reader", "Using VoiceOver"), ("typing", "Typing and choosing answers"),
        ("pausing", "Pausing, repeating and leaving"), ("packs", "Packs and purchases"),
        ("headphones", "Headphones and the lock screen"), ("watch", "Using a watch"),
        ("display", "Text size and colours"), ("contact", "Contact and privacy"),
    ]

    /// No saves or settings stored, no mic, no pack server, straight in (no intro, no onboarding, no usage data
    /// sent), and [extra] arguments (DebugLaunch).
    static func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-EpicReset", "YES", "-EpicMic", "off", "-EpicPacksURL", "", "-EpicNoIntro", "YES", "-EpicSkipOnboarding",
            "YES", "-EpicAnalytics", "off",
        ] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }
}

@MainActor
private extension XCUIApplication {
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The text showing [label].
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The identifiers starting with [prefix], in the order of the screen's elements, from one snapshot.
    func identifiers(starting prefix: String) -> [String] {
        guard let root = try? snapshot() else { return [] }
        var found: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if element.identifier.hasPrefix(prefix) { found.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(root)
        return found
    }

    /// The app's window is an iPad's (at least 600 pt both ways): Help's list and page side by side.
    var isPad: Bool {
        let size = windows.firstMatch.frame.size
        return min(size.width, size.height) >= 600
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

    func shot(_ name: String, in test: XCTestCase) {
        let shot = XCTAttachment(screenshot: screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}
