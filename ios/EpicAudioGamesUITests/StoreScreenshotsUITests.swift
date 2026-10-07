// The store's screenshots (no Kotlin counterpart): six moments of the app for the App Store, and each pack's store
// sheet for App Review.

import XCTest

/**
 * Plays the app to the moments the App Store shows, and writes each screenshot, at the screen's own size, to the
 * folder in EPIC_STORE_SHOTS (TEST_RUNNER_EPIC_STORE_SHOTS for xcodebuild); they're kept in the result bundle too.
 * Without that folder the tests are skipped, so the usual test run doesn't take them.
 *
 * The App Store's 6.9" screenshots are 1320x2868: run on an iPhone 17 Pro Max in English (U.S.) (`xcrun simctl spawn
 * <udid> defaults write -g AppleLocale en_US`, and AppleLanguages, then reboot it: the clock reads 9:41, not 09:41),
 * with the status bar set first (`xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging
 * --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4`: no charging bolt). Build with the real
 * content/ or with build/placeholder-content (ios/scripts/placeholder_content.py: the website's covers, placeholder
 * audio; the screenshots show words, not sound):
 *
 *     EPIC_CONTENT_DIR=build/placeholder-content TEST_RUNNER_EPIC_STORE_SHOTS=$PWD/build/store-shots xcodebuild \
 *       -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
 *       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
 *       -only-testing:EpicAudioGamesUITests/StoreScreenshotsUITests test
 *
 * The games are driven by the Debug build's launch arguments (DebugLaunch.swift). The mic counts as allowed
 * (-EpicHear, ScriptedListener), so it shows as it does on a phone: blue, green while listening. Its script's "~" is
 * used up by the first question (answered at once by -EpicSay), so after that the game listens and hears nothing
 * until a chip is tapped.
 */
final class StoreScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard Shots.folder != nil else {
            throw XCTSkip("store screenshots: set TEST_RUNNER_EPIC_STORE_SHOTS to the folder to write them to")
        }
    }

    /// The game list, with the covers.
    @MainActor
    func test01Home() throws {
        let s = Shots.launch(self, ["-EpicHear", "~"])
        XCTAssertTrue(s.element("game-frootopia").waitForExistence(timeout: 10))
        XCTAssertTrue(s.app.buttons["packs-frootopia"].exists)
        s.idle(1.5)
        s.shot("01_home")
    }

    /// Noodle Rush speaking: a line part said (the rest paler), the question's chips under it.
    @MainActor
    func test02NoodleRushSpeaking() throws {
        let s = Shots.launch(
            self, ["-EpicHear", "~", "-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicSay", "Yes"],
            opens: true)
        XCTAssertTrue(s.spoken("Do you want to go inside?").waitForExistence(timeout: 60), "not at the door")
        XCTAssertTrue(s.text("Listening…").waitForExistence(timeout: 15), "not listening")
        s.tap("yes")
        // "You step inside. ..." runs 11 s from 2.1 s into its turn: about half of it said.
        XCTAssertTrue(s.spoken("You step inside.").waitForExistence(timeout: 20), "not inside")
        s.idle(4.6)
        XCTAssertTrue(s.text("Tap the picture to skip").exists, "the line is over")
        XCTAssertTrue(s.app.buttons["answer-yes"].exists, "no chips")
        s.shot("02_noodle_rush")
    }

    /// Nuclear War's first question: the five countries as chips, the mic ready.
    @MainActor
    func test06NuclearWarCountries() throws {
        let s = Shots.launch(self, ["-EpicHear", "~", "-EpicOpen", "nuclear-war"], opens: true)
        XCTAssertTrue(s.app.buttons["answer-France"].waitForExistence(timeout: 30), "no country chips")
        // Typing keeps the game from listening by itself when the question comes (the shot is of it waiting).
        let field = s.app.textFields["answer-field"]
        field.tap()
        XCTAssertTrue(s.app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(s.settle(), true)
        s.hideKeyboard()
        XCTAssertTrue(s.text("Your turn! Tap the mic to talk").waitForExistence(timeout: 10), "not waiting")
        // The drag that put the keyboard away scrolled the transcript back: to its end again, the chips.
        s.toFeedEnd()
        for value in ["France", "USA", "UK", "China", "Russia"] {
            XCTAssertTrue(s.app.buttons["answer-\(value)"].isHittable, "the \(value) chip is out of view")
        }
        s.shot("06_nuclear_war")
    }

    /// The Werewolf, three villagers in: the fourth speaking, the transcript long.
    @MainActor
    func test03WerewolfStory() throws {
        let s = Shots.launch(
            self,
            ["-EpicHear", "~", "-EpicOpen", "the-werewolf", "-EpicSkip", "YES", "-EpicSay", "Yes|Yes|Yes|Next|Next"],
            opens: true)
        // "Listen to", "Meet" or "It's" Villager 3 of 8.
        XCTAssertTrue(s.spoken("Villager 3 of 8.").waitForExistence(timeout: 90), "not at villager 3")
        XCTAssertTrue(s.text("Listening…").waitForExistence(timeout: 15), "not listening")
        let before = s.labels("spoken").count
        s.tap("next")
        // "Listen to Villager 4 of 8.", their name, then what they say: a few seconds into it.
        let deadline = Date().addingTimeInterval(30)
        while s.labels("spoken").count < before + 3 && Date() < deadline { s.idle(0.25) }
        XCTAssertGreaterThanOrEqual(s.labels("spoken").count, before + 3, "the fourth villager says nothing")
        s.idle(3.0)
        XCTAssertTrue(s.text("Tap the picture to skip").exists, "the villager is done")
        s.shot("03_the_werewolf")
    }

    /// Signal Decoders' first chapter, done: CHAPTER COMPLETE! and NEXT CHAPTER.
    @MainActor
    func test05SignalDecodersChapterComplete() throws {
        let s = Shots.launch(
            self,
            ["-EpicHear", "~", "-EpicOpen", "signal-decoders", "-EpicSkip", "YES", "-EpicSay",
             "Yes|C A C|No|No|4 2 2 1 1|Follow"],
            opens: true)
        let end = s.element("end-panel")
        XCTAssertTrue(end.waitForExistence(timeout: 180), "no end panel")
        XCTAssertTrue(end.staticTexts["CHAPTER COMPLETE!"].exists)
        XCTAssertTrue(end.buttons["NEXT CHAPTER"].exists)
        XCTAssertTrue(s.spoken("End of chapter one.").waitForExistence(timeout: 5))
        s.idle(2)
        s.shot("05_signal_decoders")
    }

    /// Frootopia listening: the ring and the mic green, the words showing as they're heard.
    @MainActor
    func test04FrootopiaListening() throws {
        // A typographic apostrophe: with a straight one, the launch arguments after it are lost (UserDefaults reads
        // each as a property list).
        let words = "Yes let\u{2019}s go say hi"
        // The first two questions answered by -EpicSay (each using up a "~"), the third heard.
        let s = Shots.launch(
            self,
            ["-EpicHear", "~|~|\(words)", "-EpicOpen", "frootopia", "-EpicSkip", "YES", "-EpicSay", "Yes|Yes"],
            opens: true)
        XCTAssertTrue(s.spoken("Want to go say hi?").waitForExistence(timeout: 60), "not at Gribbo")
        // ScriptedListener: 1.5 s of listening, then the words for 2 s before they're answered.
        let heard = s.app.staticTexts.matching(NSPredicate(format: "label == %@", "“\(words)”")).firstMatch
        XCTAssertTrue(heard.waitForExistence(timeout: 15), "no words while listening")
        s.shot("04_listening")
    }

    /// Each pack's store sheet, for App Review (named by its product id).
    @MainActor
    func test07PackSheets() throws {
        let packs = [
            ("frootopia", "frootopia_stories"), ("alien-customs", "alien_customs_levels"),
            ("the-werewolf", "the_werewolf_stories"),
        ]
        for (game, product) in packs {
            let s = Shots.launch(self, ["-EpicMic", "off"])
            // The game's card at the top of the list (Frootopia's is), its pill tapped: the sheet rises under its
            // cover and title.
            if game != "frootopia" { s.toTop(s.element("game-\(game)")) }
            s.app.buttons["packs-\(game)"].tap()
            let sheet = s.element("store-sheet")
            XCTAssertTrue(sheet.waitForExistence(timeout: 15), "no store sheet for \(game)")
            // The price, once the App Store says it (GET until then).
            let price = sheet.buttons.matching(NSPredicate(format: "label CONTAINS '$'")).firstMatch
            if !price.waitForExistence(timeout: 20) { s.note("\(product): no price, GET shows") }
            s.idle(1.5)
            s.shot("iap_\(product)")
            s.app.terminate()
        }
    }
}

/// The app, as the screenshots play it.
@MainActor
private struct Shots {
    let app: XCUIApplication
    let test: XCTestCase

    /// Where the screenshots go (EPIC_STORE_SHOTS), if anywhere.
    nonisolated static var folder: URL? {
        guard let dir = ProcessInfo.processInfo.environment["EPIC_STORE_SHOTS"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir, isDirectory: true)
    }

    /// The app with no saves, and [args] (DebugLaunch); [opens]: a game opens at once.
    static func launch(_ test: XCTestCase, _ args: [String], opens: Bool = false) -> Shots {
        let app = XCUIApplication()
        app.launchArguments = ["-EpicReset", "YES"] + args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let s = Shots(app: app, test: test)
        if opens {
            XCTAssertTrue(s.element("talking-circle").waitForExistence(timeout: 30), "the game didn't open")
        } else {
            XCTAssertTrue(s.text("EPIC AUDIO GAMES").waitForExistence(timeout: 15))
        }
        return s
    }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The feed's game line with [part] in it.
    func spoken(_ part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'spoken' AND label CONTAINS %@", part)).firstMatch
    }

    /// The labels of the elements with [id], in order, from one snapshot (the feed changes as it's read).
    func labels(_ id: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var labels: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if element.identifier == id { labels.append(element.label) }
            element.children.forEach(walk)
        }
        walk(root)
        return labels
    }

    /// Taps the chip sending [value], once the question is old enough for a tap to count (B032).
    func tap(_ value: String) {
        let chip = app.buttons["answer-\(value)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "no \(value) chip")
        idle(0.8)
        chip.tap()
    }

    /// Skips the voice until the game waits for an answer (true), or ends or pauses (false).
    func settle(_ timeout: TimeInterval = 60) -> Bool? {
        let circle = element("talking-circle")
        let yourTurn = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your turn!'")).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element("end-panel").exists || element("paused").exists { return false }
            if text("Tap the picture to skip").exists {
                circle.tap()
                idle(0.3)
                continue
            }
            if yourTurn.exists { return true }
            idle(0.25)
        }
        return nil
    }

    /// Scrolls the transcript to its end.
    func toFeedEnd() {
        let feed = app.scrollViews["feed"]
        XCTAssertTrue(feed.exists)
        for _ in 0..<3 { feed.swipeUp(velocity: .fast) }
        idle(1.5)
    }

    /// Scrolls the game list until [card] is just under the header.
    func toTop(_ card: XCUIElement) {
        var swipes = 0
        while !(card.exists && card.isHittable) && swipes < 20 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(card.isHittable, "no card \(card)")
        let header = text("EPIC AUDIO GAMES").frame.maxY + 24
        let screen = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<4 where abs(card.frame.minY - header) > 4 {
            // From inside the card, by as much as it's below the header (at most what the screen allows).
            let from = min(max(card.frame.minY + 40, header + 40), app.frame.maxY - 60)
            let by = max(min(card.frame.minY - header, from - 60), -(app.frame.maxY - 60 - from))
            screen.withOffset(CGVector(dx: app.frame.midX, dy: from)).press(
                forDuration: 0.05, thenDragTo: screen.withOffset(CGVector(dx: app.frame.midX, dy: from - by)),
                withVelocity: .slow, thenHoldForDuration: 0.4)
            idle(0.5)
        }
    }

    /// Drags the transcript down into the keyboard, which puts it away.
    func hideKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let circle = element("talking-circle").frame
        let screen = app.coordinate(withNormalizedOffset: .zero)
        let from = screen.withOffset(CGVector(dx: circle.midX, dy: circle.maxY + 60))
        let to = keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "the keyboard can't be put away")
    }

    func idle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The screen now, written to the folder as [name].png and kept in the result bundle.
    func shot(_ name: String) {
        let image = app.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        guard let folder = Self.folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            XCTFail("couldn't write \(name).png: \(error)")
        }
    }

    /// A line for the log and the result bundle.
    func note(_ text: String) {
        print("STORE SHOTS: \(text)")
        let note = XCTAttachment(string: text)
        note.name = "note"
        note.lifetime = .keepAlways
        test.add(note)
    }
}
