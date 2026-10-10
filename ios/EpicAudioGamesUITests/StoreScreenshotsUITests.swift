// The store's screenshots (no Kotlin counterpart: tools/store_shots.py takes Android's on the emulator): the scenes of
// brand/scenes.json on the simulator, and each pack in the Shop for App Review.

import XCTest

/**
 * Plays the app to the moments the App Store shows, the same scenes as Android's (brand/scenes.json; their names and
 * captions are brand/shots.json's), and writes each screenshot, at the screen's own size, to the folder in
 * EPIC_STORE_SHOTS (TEST_RUNNER_EPIC_STORE_SHOTS for xcodebuild): build/store-shots/ios/raw/, where
 * `tools/make_art.py shots ios` frames them (docs/STORE_ART.md). They're kept in the result bundle too. Without that
 * folder the tests are skipped, so the usual test run doesn't take them.
 *
 * Two runs, one on each simulator, in English (U.S.) (`xcrun simctl spawn <udid> defaults write -g AppleLocale en_US`,
 * and AppleLanguages, then reboot it: the clock reads 9:41, not 09:41), with the status bar set first (`xcrun simctl
 * status_bar <udid> override --time 9:41 --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularMode
 * active --cellularBars 4`: no charging bolt):
 * - an iPhone 17 Pro Max (6.9", 1320x2868): the eight scenes into the folder (make_art.py frames them at 6.9" and
 *   6.3"), and each pack's section of the Shop, its price showing, as iap_<product id>.png (copied as they are to
 *   ios/fastlane/iap_review/);
 * - an iPad Pro 13-inch (M4) (2064x2752), upright: the eight scenes into the folder's ipad13/ (make_art.py's "13").
 *
 *     mkdir -p build/store-shots/ios/raw
 *     EPIC_CONTENT_DIR=build/placeholder-content TEST_RUNNER_EPIC_STORE_SHOTS=$PWD/build/store-shots/ios/raw \
 *       xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
 *       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
 *       -only-testing:EpicAudioGamesUITests/StoreScreenshotsUITests test
 *
 * then the same with `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'`. Build with the real content/
 * or with build/placeholder-content (ios/scripts/placeholder_content.py: the website's covers, placeholder audio of the
 * clips' own lengths, and content/app/ as it is; the screenshots show words, not sound). The prices are the StoreKit
 * configuration's (ios/Config/EpicAudioGames.storekit, in pounds: "Buy for £1.99").
 *
 * Each scene is a launch of its own with the Debug build's launch arguments (DebugLaunch.swift; Android's launch
 * extras have the same names): no saves or settings stored, no intro, no onboarding and no usage data, then the
 * scene's. In a game the mic counts as allowed (-EpicHear, ScriptedListener), so it shows as on a phone, and the
 * script's words are heard as a player's would be.
 */
final class StoreScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard Shots.folder != nil else {
            throw XCTSkip("store screenshots: set TEST_RUNNER_EPIC_STORE_SHOTS to the folder to write them to")
        }
    }

    /// The Games tab: its heading, the line under it, the first cards.
    @MainActor
    func test01Games() throws {
        let s = Shots.launch(self, ["-EpicTab", "games"])
        XCTAssertTrue(s.element("game-frootopia").waitForExistence(timeout: 10))
        s.idle(1.5)
        s.shot("01_games")
    }

    /// Noodle Rush, a line part said, the word being said highlighted ([story]).
    @MainActor
    func test02Story() throws {
        story("02_story")
    }

    /// Listening: the first scene skipped, the ring and the mic in the listening colour, the words showing as they're
    /// heard, the Yes and No chips.
    @MainActor
    func test03Answer() throws {
        // A typographic apostrophe: with a straight one, the launch arguments after it are lost (UserDefaults reads each
        // as a property list).
        let words = "Yes let\u{2019}s go"
        let s = Shots.launch(self, ["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicHear", words], opens: true)
        // ScriptedListener: 1.5 s of listening, then the words for 2 s before they count.
        XCTAssertTrue(s.text("\u{201C}\(words)\u{201D}").waitForExistence(timeout: 60), "no words while listening")
        XCTAssertTrue(s.app.buttons["answer-yes"].exists, "no chips")
        s.idle(0.5)
        s.shot("03_answer")
    }

    /// As 02_story, in the High contrast theme at the Larger text size.
    @MainActor
    func test04BigText() throws {
        story("04_big_text", look: ["-EpicTheme", "contrast", "-EpicTextSize", "1.3"])
    }

    /// Settings at a large text size (the phone's AccessibilityL, the app's Large): Sound and voice first, the voice
    /// speed 1.25 times.
    @MainActor
    func test05VoiceSpeed() throws {
        let s = Shots.launch(self, [
            "-EpicTab", "settings", "-EpicSpeed", "1.25", "-EpicTextSize", "1.15",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ])
        XCTAssertTrue(s.element("settings-heading").waitForExistence(timeout: 10))
        XCTAssertTrue(s.text("1.25 times").exists, "the voice speed isn't 1.25 times")
        s.idle(1.5)
        s.shot("05_voice_speed")
    }

    /// Help, "Playing with your voice", with Listen playing (the words highlighted as they're read): the topic opened
    /// from the Help tab's list, as Android's scene does (on an iPad, beside the list).
    @MainActor
    func test06Help() throws {
        let s = Shots.launch(self, ["-EpicTab", "help"])
        XCTAssertTrue(s.element("help-heading").waitForExistence(timeout: 10))
        s.idle(1.0)
        let row = s.app.buttons["help-topic-voice"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Playing with your voice: the build has no help")
        row.tap()
        XCTAssertTrue(s.element("help-page-heading").waitForExistence(timeout: 5), "the topic didn't open")
        s.idle(1.5)
        let listen = s.app.buttons["help-listen"]
        XCTAssertTrue(listen.exists, "no Listen: the build has no help clips")
        listen.tap()
        s.idle(3.5)
        XCTAssertEqual(listen.label, "Pause", "it isn't reading")
        s.shot("06_help")
    }

    /// The Shop tab: every pack by game, its price from the App Store, Restore purchases.
    @MainActor
    func test07Shop() throws {
        let s = Shots.launch(self, ["-EpicTab", "shop"])
        XCTAssertTrue(s.element("shop-heading").waitForExistence(timeout: 10))
        XCTAssertTrue(s.priced("frootopia-stories"), "no price from the App Store")
        s.idle(1.5)
        s.shot("07_shop")
    }

    /// The Games tab scrolled down to the later games (werewolves, pirates); an iPad's grid shows most of them at once.
    @MainActor
    func test08EightGames() throws {
        let s = Shots.launch(self, ["-EpicTab", "games"])
        XCTAssertTrue(s.element("game-frootopia").waitForExistence(timeout: 10))
        s.idle(1.0)
        if s.isPad {
            s.drag(from: 0.7, to: 0.4)
        } else {
            s.drag(from: 0.8, to: 0.25)
        }
        s.idle(1.5)
        s.shot("08_eight_games")
    }

    /**
     * Each pack's section of the Shop at the top of the screen, its price showing ("Buy for £1.99"), for App Review:
     * iap_<product id>.png. The iPhone's run only (one for each product is all App Review takes).
     */
    @MainActor
    func test09InAppPurchases() throws {
        // A pack whose price doesn't come fails the test, and the other packs are still taken.
        continueAfterFailure = true
        let packs = [
            ("frootopia", "frootopia-stories", "frootopia_stories"),
            ("alien-customs", "alien-customs-levels", "alien_customs_levels"),
            ("the-werewolf", "the-werewolf-stories", "the_werewolf_stories"),
        ]
        for (game, pack, product) in packs {
            let s = Shots.launch(self, ["-EpicTab", "shop"])
            if s.isPad {
                s.app.terminate()
                throw XCTSkip("the iPhone's run takes the in-app purchases' screenshots")
            }
            let heading = s.element("shop-heading")
            XCTAssertTrue(heading.waitForExistence(timeout: 10), "no Shop")
            // The game's section where the page's heading was, its pack's Buy button in view.
            s.toTop(s.element("shop-game-\(game)"), showing: s.app.buttons["buy-\(pack)"], at: heading.frame.minY)
            XCTAssertTrue(s.priced(pack), "\(product): no price from the App Store")
            s.idle(1.5)
            s.shot("iap_\(product)")
            s.app.terminate()
        }
    }

    /**
     * Noodle Rush's first scene skipped and its question answered out loud ("Yes", heard), then the next scene about
     * 8 s in, as Android's scene has it: "Steam curls out of the door…" a third said, its word being said highlighted,
     * and the scene's question not asked yet. In [look]'s theme and text size; written as [name].
     */
    @MainActor
    private func story(_ name: String, look: [String] = []) {
        let s = Shots.launch(
            self, ["-EpicOpen", "noodle-rush", "-EpicSkip", "YES", "-EpicHear", "Yes"] + look, opens: true)
        // Heard (ScriptedListener: 1.5 s of listening, then the word for 2 s): the reply shows, and the next scene starts.
        let reply = s.app.staticTexts.matching(identifier: "reply").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 60), "no answer heard")
        // About 8 s after it was heard (seeing the reply took a moment too).
        s.idle(7.5)
        XCTAssertTrue(s.spoken("Steam curls out of the door").exists, "not at the steam")
        XCTAssertFalse(s.spoken("Do you want to go inside?").exists, "the scene is over")
        XCTAssertTrue(s.text("Tap the picture to skip").exists, "the voice isn't speaking")
        s.shot(name)
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

    /**
     * The app upright, with no saves or settings stored, straight in (no intro, no onboarding, no usage data sent), and
     * [args] (DebugLaunch); then the tab bar showing, or with [opens] the game DebugLaunch opens.
     */
    static func launch(_ test: XCTestCase, _ args: [String], opens: Bool = false) -> Shots {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-EpicReset", "YES", "-EpicNoIntro", "YES", "-EpicSkipOnboarding", "YES", "-EpicAnalytics", "off",
        ] + args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let s = Shots(app: app, test: test)
        if opens {
            XCTAssertTrue(s.element("talking-circle").waitForExistence(timeout: 30), "the game didn't open")
        } else {
            XCTAssertTrue(s.tabsShow(within: 15), "no tab bar")
        }
        return s
    }

    /**
     * The tab bar's Games tab is there: by its identifier ("tab-games", if SwiftUI hands it on from the tab's label to
     * the bar's button), else by its name, in the bar (an iPhone's) or as a button (an iPad's, from iPadOS 18).
     */
    func tabsShow(within timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element("tab-games").exists || app.tabBars.buttons["Games"].exists
                || app.buttons.matching(NSPredicate(format: "label == %@", "Games")).firstMatch.exists {
                return true
            }
            idle(0.25)
        } while Date() < deadline
        return false
    }

    /// The app runs on an iPad (its window at least 600 pt both ways; this runner may be an iPhone app there, so its
    /// own device idiom doesn't say).
    var isPad: Bool {
        let size = app.windows.firstMatch.frame.size
        return min(size.width, size.height) >= 600
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

    /// [pack]'s Buy button with the App Store's price on it ("Buy for £1.99: …"; "Get" until the price comes).
    func priced(_ pack: String, timeout: TimeInterval = 20) -> Bool {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS '1.99'", "buy-\(pack)"))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    /**
     * Scrolls the page until [element]'s top is at [top] (where the page's heading started), as near as the page lets
     * it: first until [showing] can be touched, then by as much as [element] is below [top].
     */
    func toTop(_ element: XCUIElement, showing: XCUIElement, at top: CGFloat) {
        var swipes = 0
        while !(showing.exists && showing.isHittable) && swipes < 20 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(showing.exists && showing.isHittable, "\(showing) is out of view")
        XCTAssertTrue(element.exists, "no \(element)")
        let screen = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<4 where abs(element.frame.minY - top) > 4 {
            // From inside it, by as much as it's below the top (at most what the screen allows).
            let from = min(max(element.frame.minY + 40, top + 40), app.frame.maxY - 60)
            let by = max(min(element.frame.minY - top, from - 60), -(app.frame.maxY - 60 - from))
            screen.withOffset(CGVector(dx: app.frame.midX, dy: from)).press(
                forDuration: 0.05, thenDragTo: screen.withOffset(CGVector(dx: app.frame.midX, dy: from - by)),
                withVelocity: .slow, thenHoldForDuration: 0.4)
            idle(0.5)
        }
    }

    /// Drags the page up, from [from] to [to] (shares of the screen's height from its top), slowly and held at the end,
    /// so it stops there rather than flinging on (Android's scene swipes as far).
    func drag(from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    func idle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /**
     * The screen now, written to the folder as [name].png (an iPad's to the folder's ipad13/, make_art.py's 13" size)
     * and kept in the result bundle.
     */
    func shot(_ name: String) {
        let image = app.screenshot()
        let pad = isPad
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = pad ? "\(name)-ipad13" : name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        guard let root = Self.folder else { return }
        let folder = pad ? root.appendingPathComponent("ipad13", isDirectory: true) : root
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            XCTFail("couldn't write \(name).png: \(error)")
        }
    }
}
