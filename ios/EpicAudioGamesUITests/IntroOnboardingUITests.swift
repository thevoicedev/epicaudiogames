// The way in as a player meets it: Android's IntroScreenTest.kt and OnboardingTest.kt (Compose tests there) as UI
// tests here.

import XCTest

/**
 * The intro and onboarding (docs/DESIGN.md › Intro, › Onboarding): the intro one element, "Epic Audio Games", that a
 * tap skips and that ends by itself, and none with Play the intro sound off; onboarding's pages in order, each with its
 * step in words in its heading, Back, Next, Skip and Start playing; VoiceOver's page only with it on (-EpicVoiceOver
 * YES stands in, as a UI test can't turn VoiceOver on); usage data said plainly with its button; the microphone asked
 * for (or Not now) before iOS asks; the comfort page's choices taking effect; and onboarding shown again from Settings
 * and Help. The app starts with no saves and no settings stored (-EpicReset), no mic, no pack server, and no usage data
 * sent (-EpicAnalytics off, which leaves Share usage data as it is: on).
 */
final class IntroOnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // ----- The intro -----

    /// One element, "Epic Audio Games" (the wordmark isn't read again on its own); a tap skips it, to Games.
    @MainActor
    func testTheIntroIsOneElementThatATapSkips() throws {
        let app = Start.launch(intro: true, extra: ["-EpicHoldIntro", "YES"])
        let intro = app.element("intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 15), "no intro")
        XCTAssertEqual(intro.label, "Epic Audio Games")
        XCTAssertFalse(app.text("Epic Audio Games").exists, "the wordmark is read on its own")
        XCTAssertFalse(app.element("games-heading").exists, "Games under the intro")
        app.shot("intro", in: self)
        intro.tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5), "a tap didn't skip it")
        XCTAssertFalse(intro.exists)
    }

    /// Left alone, it ends by itself (a moment after its sound, or after 2.5 s without one), and Games shows. (XCTest
    /// may only hand the app over once the intro is nearly done, so its start isn't waited for.)
    @MainActor
    func testTheIntroEndsByItself() throws {
        let app = Start.launch(intro: true)
        let intro = app.element("intro")
        XCTAssertTrue(intro.exists || app.element("games-heading").exists, "neither the intro nor Games")
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 10), "the intro didn't end")
        XCTAssertFalse(intro.exists)
    }

    /// Settings › Play the intro sound off: no intro screen at all.
    @MainActor
    func testThereIsNoIntroWithItsSoundOff() throws {
        let app = Start.launch(extra: ["-settings.introSound", "NO"], noIntro: false)
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 15))
        XCTAssertFalse(app.element("intro").exists, "an intro with its sound off")
    }

    // ----- Onboarding -----

    /// Four pages in order without VoiceOver, each heading its step and title; the last has Start playing (no Next, no
    /// Skip), which goes to Games; once finished, the next launch goes straight to Games.
    @MainActor
    func testOnboardingsPagesInOrderThenGames() throws {
        let app = Start.launch(onboarding: true)
        expectPage(app, "onboarding-welcome", "Step 1 of 4", "Welcome")
        XCTAssertFalse(app.buttons["onboarding-back"].exists, "Back on the first page")
        next(app)
        expectPage(app, "onboarding-mic", "Step 2 of 4", "Answer out loud")
        next(app)
        expectPage(app, "onboarding-comfort", "Step 3 of 4", "Make it comfortable")
        next(app)
        expectPage(app, "onboarding-ready", "Step 4 of 4", "You're ready")
        XCTAssertFalse(app.buttons["onboarding-next"].exists)
        XCTAssertFalse(app.buttons["onboarding-skip"].exists)
        app.shot("onboarding-ready", in: self)
        let back = app.buttons["onboarding-back"]
        XCTAssertEqual(back.label, "Back")
        back.tap()
        expectPage(app, "onboarding-comfort", "Step 3 of 4", "Make it comfortable")
        next(app)
        let start = app.buttons["onboarding-start"]
        XCTAssertEqual(start.label, "Start playing")
        start.tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5), "Start playing isn't Games")
        XCTAssertFalse(app.element("onboarding-heading").exists)
        // Finished: launched again with its settings kept (no -EpicReset), no onboarding.
        app.terminate()
        app.launchArguments = ["-EpicMic", "off", "-EpicPacksURL", "", "-EpicNoIntro", "YES", "-EpicAnalytics", "off"]
        app.launch()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 15), "onboarding again")
        XCTAssertFalse(app.element("onboarding-welcome").exists)
    }

    /// The welcome is read aloud by itself, once, without VoiceOver: its Listen is Pause while it reads, and leaving
    /// the page stops it (a build without the clip has no Listen).
    @MainActor
    func testTheWelcomeIsReadByItselfOnce() throws {
        let app = Start.launch(onboarding: true)
        expectPage(app, "onboarding-welcome", "Step 1 of 4", "Welcome")
        let listen = app.buttons["onboarding-listen"]
        guard listen.exists else { throw XCTSkip("this build has no welcome clip") }
        XCTAssertEqual(listen.label, "Pause")
        XCTAssertEqual(listen.value as? String, "Playing")
        next(app)
        app.buttons["onboarding-back"].tap()
        expectPage(app, "onboarding-welcome", "Step 1 of 4", "Welcome")
        XCTAssertEqual(app.buttons["onboarding-listen"].label, "Listen", "read by itself again")
    }

    /// With VoiceOver on (-EpicVoiceOver YES), five pages: its own, with the Help topic's words; and the welcome waits
    /// for Listen.
    @MainActor
    func testWithVoiceOverItsOwnPage() throws {
        let app = Start.launch(onboarding: true, extra: ["-EpicVoiceOver", "YES"])
        expectPage(app, "onboarding-welcome", "Step 1 of 5", "Welcome")
        let listen = app.buttons["onboarding-listen"]
        if listen.exists { XCTAssertEqual(listen.label, "Listen", "read by itself over VoiceOver") }
        next(app)
        next(app)
        next(app)
        expectPage(app, "onboarding-screen-reader", "Step 4 of 5", "Playing with VoiceOver")
        let words = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "With VoiceOver on, the microphone doesn")).firstMatch
        XCTAssertTrue(words.exists, "not the topic's words")
        app.shot("onboarding-voiceover", in: self)
        next(app)
        expectPage(app, "onboarding-ready", "Step 5 of 5", "You're ready")
    }

    /// Usage data said plainly on the welcome, with its one button: on, as it is unless turned off (-EpicAnalytics off
    /// only keeps a test's from being sent); Turn off, then Turn on, each saying what it is. OnboardingTest.kt's.
    @MainActor
    func testUsageDataTurnsOffAndOn() throws {
        let app = Start.launch(onboarding: true)
        let said = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "We collect usage data under a random ID")).firstMatch
        XCTAssertTrue(app.scrolledTo(said), "the line about usage data")
        let turnOff = app.buttons["analytics-off"]
        XCTAssertTrue(app.scrolledTo(turnOff), "no Turn off")
        XCTAssertEqual(turnOff.label, "Turn off usage data")
        turnOff.tap()
        let off = app.element("analytics-is-off")
        XCTAssertTrue(off.waitForExistence(timeout: 5), "it didn't turn off")
        XCTAssertTrue(off.label.hasPrefix("Usage data is off."), off.label)
        let turnOn = app.buttons["analytics-on"]
        XCTAssertEqual(turnOn.label, "Turn on usage data")
        turnOn.tap()
        XCTAssertTrue(said.waitForExistence(timeout: 5), "it didn't turn on again")
        XCTAssertTrue(app.buttons["analytics-off"].waitForExistence(timeout: 5))
    }

    /// Answer out loud, with the mic not yet asked for: Not now leaves it for later, as the page says.
    @MainActor
    func testNotNowLeavesTheMicForLater() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        Start.launch(app, onboarding: true)
        next(app)
        expectPage(app, "onboarding-mic", "Step 2 of 4", "Answer out loud")
        let allow = app.buttons["onboarding-mic-allow"]
        XCTAssertTrue(app.scrolledTo(allow), "no Allow microphone")
        XCTAssertEqual(allow.label, "Allow microphone")
        let notNow = app.buttons["onboarding-mic-not-now"]
        XCTAssertTrue(app.scrolledTo(notNow))
        notNow.tap()
        let result = app.element("onboarding-mic-result")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Not now said nothing")
        XCTAssertTrue(result.label.hasPrefix("No problem"), result.label)
        XCTAssertFalse(app.buttons["onboarding-mic-allow"].exists)
    }

    /// Allow microphone: iOS asks (the mic, and speech recognition unless it was answered before), and the page says
    /// what's allowed now.
    @MainActor
    func testAllowMicrophoneAsksAndSaysWhatsAllowed() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        Start.launch(app, onboarding: true)
        next(app)
        let allow = app.buttons["onboarding-mic-allow"]
        XCTAssertTrue(app.scrolledTo(allow))
        allow.tap()
        let asked = Start.allowSystemDialogs()
        XCTAssertTrue(asked.contains { $0.contains("Microphone") }, "the mic wasn't asked for: \(asked)")
        let result = app.element("onboarding-mic-result")
        XCTAssertTrue(result.waitForExistence(timeout: 10), "nothing said")
        // Both allowed: on. Speech recognition refused on this simulator before (simctl can't reset it): No problem.
        XCTAssertTrue(result.label == "The microphone is on." || result.label.hasPrefix("No problem"), result.label)
        app.shot("onboarding-mic-answered", in: self)
    }

    /// Make it comfortable: High contrast and Larger take effect as they're picked, and Settings has them too.
    @MainActor
    func testTheComfortPagesChoicesTakeEffect() throws {
        let app = Start.launch(onboarding: true)
        next(app)
        next(app)
        expectPage(app, "onboarding-comfort", "Step 3 of 4", "Make it comfortable")
        let contrast = app.buttons["setting-theme-contrast"]
        XCTAssertTrue(app.scrolledTo(contrast))
        contrast.tap()
        XCTAssertTrue(contrast.isSelected)
        let larger = app.buttons["setting-textScale-1.3"]
        XCTAssertTrue(app.scrolledTo(larger))
        larger.tap()
        XCTAssertTrue(larger.isSelected)
        app.shot("onboarding-comfort-contrast-larger", in: self)
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5))
        app.tab("settings", "Settings").tap()
        let theme = app.buttons["setting-theme-contrast"]
        XCTAssertTrue(app.scrolledTo(theme))
        XCTAssertTrue(theme.isSelected, "Settings has another theme")
    }

    /// Skip, on the first run: Games.
    @MainActor
    func testSkipGoesToGames() throws {
        let app = Start.launch(onboarding: true)
        let skip = app.buttons["onboarding-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        XCTAssertEqual(skip.label, "Skip")
        skip.tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5))
    }

    /// Settings › Show the welcome again: onboarding from its first page; skipped, back to Settings.
    @MainActor
    func testShownAgainFromSettingsSkipGoesBack() throws {
        let app = Start.launch()
        app.tab("settings", "Settings").tap()
        let welcome = app.buttons["setting-welcome"]
        XCTAssertTrue(app.scrolledTo(welcome))
        welcome.tap()
        expectPage(app, "onboarding-welcome", "Step 1 of 4", "Welcome")
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.element("settings-heading").waitForExistence(timeout: 5), "not back in Settings")
        XCTAssertTrue(app.tab("settings", "Settings").isSelected)
    }

    /// Help › Show the welcome again: through to Start playing, which goes to Games.
    @MainActor
    func testShownAgainFromHelpStartPlayingGoesToGames() throws {
        let app = Start.launch()
        app.tab("help", "Help").tap()
        let welcome = app.buttons["help-welcome"]
        XCTAssertTrue(app.scrolledTo(welcome))
        welcome.tap()
        expectPage(app, "onboarding-welcome", "Step 1 of 4", "Welcome")
        next(app)
        next(app)
        next(app)
        app.buttons["onboarding-start"].tap()
        XCTAssertTrue(app.element("games-heading").waitForExistence(timeout: 5), "Start playing isn't Games")
        XCTAssertTrue(app.tab("games", "Games").isSelected)
    }

    // ----- Steps -----

    /// The page [id] shows, its heading one element with its step and title ("Step 2 of 4, Answer out loud").
    @MainActor
    private func expectPage(_ app: XCUIApplication, _ id: String, _ step: String, _ title: String) {
        XCTAssertTrue(app.element(id).waitForExistence(timeout: 15), "no \(id)")
        let heading = app.element("onboarding-heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "no heading on \(id)")
        XCTAssertEqual(heading.label, "\(step), \(title)")
    }

    @MainActor
    private func next(_ app: XCUIApplication) {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "no Next")
        XCTAssertEqual(next.label, "Next")
        next.tap()
    }
}

/// The app as these tests launch it.
@MainActor
private enum Start {
    /**
     * A new app, with no saves and no settings stored, no mic, no pack server and no usage data sent: the intro only if
     * [intro] (-EpicIntro YES: whatever the settings), else none ([noIntro]: -EpicNoIntro YES, unless a test wants the
     * settings to decide); onboarding only if [onboarding] (-EpicOnboarding YES), else skipped; and [extra] arguments.
     */
    @discardableResult
    static func launch(
        _ app: XCUIApplication = XCUIApplication(), intro: Bool = false, onboarding: Bool = false,
        extra: [String] = [], noIntro: Bool = true
    ) -> XCUIApplication {
        var args = ["-EpicReset", "YES", "-EpicMic", "off", "-EpicPacksURL", "", "-EpicAnalytics", "off"]
        if intro {
            args += ["-EpicIntro", "YES"]
        } else if noIntro {
            args += ["-EpicNoIntro", "YES"]
        }
        args += onboarding ? ["-EpicOnboarding", "YES"] : ["-EpicSkipOnboarding", "YES"]
        app.launchArguments = args + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    /// The system's permission dialogs (the mic's, then speech recognition's if it's asked), allowed; their names.
    static func allowSystemDialogs() -> [String] {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var asked: [String] = []
        for timeout in [10.0, 5.0] {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: timeout) else { break }
            asked.append(alert.label)
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
            } else {
                alert.buttons["OK"].tap()
            }
            _ = alert.waitForNonExistence(timeout: 5)
        }
        return asked
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

    /// A tab in the tab bar: by its identifier, else by its name (TabsUITests' tab(_:_:)).
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

    func shot(_ name: String, in test: XCTestCase) {
        let shot = XCTAttachment(screenshot: screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }
}
