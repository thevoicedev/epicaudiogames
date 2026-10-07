// Plays the app as a player would, by the answer chips and typing (no Kotlin counterpart; GameScreen.kt and
// HomeScreen.kt's behaviour).

import XCTest

/**
 * Plays Noodle Rush to an ending and back to the list, answers Nuclear War's first questions, opens every game, and
 * shows a game's packs, with the bundled content's audio playing (the placeholder clips in a build without the real
 * content). The screenshots are kept in the result bundle (`xcrun xcresulttool export attachments`).
 */
final class PlaythroughUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The Best Friend ending, which every random turn on the way leads to: yes, yes, "wait" (typed), yes four
    /// times, no, then yes four times. Then the list (PLAY, not CONTINUE, after an end), a fresh game, a place
    /// kept (CONTINUE, "Welcome back!"), and a pause.
    @MainActor
    func testNoodleRushToAnEndingAndBack() throws {
        let app = Player.launch()
        app.shot("home", in: self)
        app.open("noodle-rush")
        app.waitForLine("Noodle Rush!", timeout: 40)
        app.answer("yes", expecting: "Slurpy's Noodle Bar hums")
        // Its first line runs for 4 s from 0.25 s: part of it is said, the rest paler.
        app.shot("noodle-rush-speaking", in: self)
        XCTAssertTrue(app.text("Tap the picture to skip").exists)
        app.skip()
        XCTAssertTrue(app.text("Your turn!").waitForExistence(timeout: 10))
        XCTAssertTrue(app.spoken("Do you want to go inside?").exists, "a skip shows the rest of the turn's lines")
        app.shot("noodle-rush-answers", in: self)

        // The question's options are chips at the transcript's end, in view, their labels as written.
        let yes = app.buttons["answer-yes"]
        XCTAssertEqual(yes.label, "Yes")
        XCTAssertTrue(yes.isHittable, "the chips are out of view")
        XCTAssertTrue(app.element("chips").exists)
        app.answer("yes", expecting: "You step inside.")
        XCTAssertTrue(app.reply("Yes").exists, "a chip's reply is its label")
        app.type("wait", expecting: "Patience!")
        XCTAssertTrue(app.reply("wait").exists, "the typed answer shows as it was typed")
        // The keyboard stays up after sending, as Android's does; dragging the transcript down into it puts it away
        // (Android's Back).
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard went away after sending")
        app.dragIntoKeyboard(from: app.spoken("Patience!"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard can't be put away")
        app.answer("yes", expecting: ["Just then, the little old lady", "Suddenly, a pigeon"])
        app.answer("yes", expecting: ["You dive into action!", "You leap into the air"])
        app.answer("yes", expecting: "At last, the counter!")
        app.answer("yes", expecting: "Back on the sidewalk.")
        app.answer("no", expecting: "You whip out your kazoo")
        app.answer("yes", expecting: "Eight dogs.")
        app.answer("yes", expecting: "You hold on tight!")
        app.answer("yes", expecting: "You yell at the top of your lungs.")
        app.answer("yes", expecting: "You scoop him up")
        app.skip()

        let end = app.element("end-panel")
        XCTAssertTrue(end.waitForExistence(timeout: 10), "no end panel")
        XCTAssertTrue(end.text("THE END").exists)
        XCTAssertTrue(end.text("Best Friend Ending").exists)
        XCTAssertTrue(end.buttons["PLAY AGAIN"].exists)
        XCTAssertFalse(app.buttons["answer-yes"].exists, "chips at an end")
        app.shot("noodle-rush-end", in: self)

        // Back on the list, a game at its end isn't carried on (Library.kt's inProgress).
        end.buttons["BACK TO GAMES"].tap()
        let card = app.card("noodle-rush")
        XCTAssertTrue(card.says("PLAY"))
        XCTAssertFalse(card.says("CONTINUE"))

        // Opening it again starts again: an ending isn't picked up (its keep variables would be kept, B002)...
        app.open("noodle-rush")
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 15))
        XCTAssertFalse(app.text("Welcome back!").exists)
        app.skip()
        app.waitForLine("Are you ready to play?")
        XCTAssertTrue(app.text("Your turn!").waitForExistence(timeout: 10))
        // ...and leaving keeps the place, the question waiting.
        app.buttons["Back"].tap()
        let again = app.card("noodle-rush")
        XCTAssertTrue(again.says("CONTINUE"))
        XCTAssertTrue(again.says("CARRY ON"))
        app.shot("home-continue", in: self)

        app.open("noodle-rush")
        XCTAssertTrue(app.text("Welcome back!").waitForExistence(timeout: 15))
        // Leaving the app pauses the game until a tap.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let paused = app.element("paused")
        XCTAssertTrue(paused.waitForExistence(timeout: 10), "no pause after the background")
        // The pause is VoiceOver's only place (it's modal): its carry on, and its back arrow.
        XCTAssertTrue(app.buttons["Carry on"].exists)
        app.shot("noodle-rush-paused", in: self)
        paused.tap()
        XCTAssertTrue(paused.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 10), "carrying on asks again")
        // So does "stop", typed.
        app.type("stop")
        XCTAssertTrue(paused.waitForExistence(timeout: 10), "no pause after stop")
        // fixed (B003): the keyboard stayed up over the pause after a typed stop.
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard stays up over the pause")
        paused.tap()
        XCTAssertTrue(paused.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.reply("stop").exists, "stop pauses: it isn't an answer")
        XCTAssertTrue(app.buttons["answer-yes"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.card("noodle-rush").says("CONTINUE"))
    }

    /// Playing by voice (the answers heard from a script, -EpicHear, in place of the mic): the game listens by itself
    /// after each question; a silence asks again; words show as they come and are answered; speech it couldn't make
    /// out is "…" and the question's else; a second silence pauses; "stop" pauses; the mic stops and starts
    /// listening; and while paused, the back arrow still leaves (Android's system Back).
    @MainActor
    func testNoodleRushByVoice() throws {
        let app = Player.launch(hearing: "~|yes|?|~|stop")
        app.open("noodle-rush")
        app.waitForLine("Noodle Rush!", timeout: 40)
        app.skip()
        // Listening by itself, then nobody speaks: the question again.
        XCTAssertTrue(app.text("Listening…").waitForExistence(timeout: 10), "it doesn't listen after a question")
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 10), "a silence doesn't ask again")
        XCTAssertFalse(app.staticTexts.matching(identifier: "reply").firstMatch.exists)
        app.skip()
        // "yes": the words as they come, then the answer.
        XCTAssertTrue(app.text("“yes”").waitForExistence(timeout: 10), "no words while listening")
        app.shot("noodle-rush-listening", in: self)
        XCTAssertTrue(app.spoken("Slurpy's Noodle Bar hums").waitForExistence(timeout: 40))
        XCTAssertTrue(app.reply("yes").exists)
        app.skip()
        // Speech it couldn't make out: "…", and the question's else.
        XCTAssertTrue(app.reply("…").waitForExistence(timeout: 10), "no … for speech it couldn't make out")
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 10))
        app.skip()
        // Then a silence: the second running, so the game waits for a tap.
        let paused = app.element("paused")
        XCTAssertTrue(paused.waitForExistence(timeout: 10), "no pause after a second silence")
        paused.tap()
        XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 10), "carrying on asks again")
        app.skip()
        // "stop", said: a pause, not an answer.
        XCTAssertTrue(paused.waitForExistence(timeout: 10), "saying stop doesn't pause")
        XCTAssertFalse(app.reply("stop").exists)
        paused.tap()
        app.skip()
        // The mic button stops listening, and starts it again.
        XCTAssertTrue(app.text("Listening…").waitForExistence(timeout: 10))
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.isEnabled)
        mic.tap()
        XCTAssertTrue(app.text("Your turn! Tap the mic to talk").waitForExistence(timeout: 5))
        mic.tap()
        XCTAssertTrue(app.text("Listening…").waitForExistence(timeout: 5))
        // Paused, the back arrow leaves the game.
        app.type("stop")
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        // The pause's own back arrow, where the header's is (the header's, under the dimming, takes no taps).
        let backs = app.buttons.matching(NSPredicate(format: "label == 'Back'"))
        backs.element(boundBy: backs.count - 1).tap()
        XCTAssertTrue(app.card("noodle-rush").says("CONTINUE"))
    }

    /// GameScreen.kt's permission request: as a game opens, the mic is asked for (and on iOS speech recognition
    /// too). Refused, the mic button says the mic is off, with the way to Settings, and answers are typed or tapped;
    /// allowed, the mic button works.
    @MainActor
    func testTheMicIsAskedForAsAGameOpens() throws {
        // The dialogs are answered as the test says (XCTest's own handler would allow them).
        let dialogs = Dialogs()
        let monitor = addUIInterruptionMonitor(withDescription: "permissions") { alert in dialogs.answer(alert) }
        defer { removeUIInterruptionMonitor(monitor) }

        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        dialogs.choice = "Don’t Allow"
        Player.launch(app, hearing: nil, mic: true)
        app.open("noodle-rush")
        dialogs.answerShowing()
        XCTAssertTrue(dialogs.asked.contains { $0.contains("Microphone") }, "the mic wasn't asked for: \(dialogs.asked)")
        app.waitForLine("Noodle Rush!", timeout: 40)
        app.skip()
        XCTAssertTrue(app.text("Your turn!").waitForExistence(timeout: 10))
        // fixed (B015): the mic button was off, and nothing said why or how to turn the mic on.
        let mic = app.buttons["mic"]
        XCTAssertTrue(mic.isEnabled)
        XCTAssertEqual(mic.label, "Talk (the microphone is off)")
        mic.tap()
        let off = app.alerts["The microphone is off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5), "the refused mic says nothing")
        XCTAssertTrue(off.buttons["Settings"].exists)
        app.shot("noodle-rush-mic-refused", in: self)
        off.buttons["Not now"].tap()
        app.buttons["Back"].tap()

        app.resetAuthorizationStatus(for: .microphone)
        dialogs.choice = "Allow"
        dialogs.asked = []
        Player.launch(app, hearing: nil, mic: true)
        app.open("noodle-rush")
        dialogs.answerShowing()
        dialogs.answerShowing(timeout: 5)          // speech recognition, unless it was allowed before
        XCTAssertTrue(dialogs.asked.contains { $0.contains("Microphone") }, "the mic wasn't asked for: \(dialogs.asked)")
        XCTAssertTrue(app.buttons["mic"].waitForEnabled(timeout: 10), "the mic is off once allowed: \(dialogs.asked)")
        app.waitForLine("Noodle Rush!", timeout: 40)
        app.skip()
        // The simulator may have no mic to listen with (the mic then shows as not working): either way the game
        // has tried to listen by itself.
        let listening = app.text("Listening…")
        let noMic = app.text("Your turn!")
        XCTAssertTrue(listening.waitForExistence(timeout: 10) || noMic.exists, "the game didn't try to listen")
        app.shot("noodle-rush-mic-allowed", in: self)
        app.buttons["Back"].tap()
    }

    /// The country, then the meetings: a chip sends its value, and the reply shows its label ("the USA" sends "USA").
    @MainActor
    func testNuclearWarByButtons() throws {
        let app = Player.launch()
        app.open("nuclear-war")
        app.waitForLine("Welcome to the nuclear war game.", timeout: 40)
        let countries = ["France", "USA", "UK", "China", "Russia"]
        for value in countries {
            XCTAssertTrue(app.buttons["answer-\(value)"].waitForExistence(timeout: 10), "no \(value) chip")
        }
        XCTAssertEqual(app.buttons["answer-USA"].label, "the USA")
        app.shot("nuclear-war-buttons", in: self)

        app.answer("USA", expecting: "You are now the leader of the USA.")
        // fixed (B011): the reply showed the value ("USA"), not what the player tapped.
        XCTAssertTrue(app.reply("the USA").exists, "a chip's reply is its label")
        XCTAssertFalse(app.reply("USA").exists)
        app.skip()
        // Who comes first to meet is random.
        var question = app.lastQuestion(after: "")
        XCTAssertTrue(question.localizedCaseInsensitiveContains("like to meet"), "no meeting asked: \(question)")
        for _ in 0..<3 {
            app.answer("yes", expecting: "the representative")
            app.skip()
            let next = app.lastQuestion(after: question)
            XCTAssertNotEqual(next, question)
            question = next
        }
        XCTAssertTrue(app.reply("Yes").exists)
        app.shot("nuclear-war-meetings", in: self)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.card("nuclear-war").says("CONTINUE"))

        // The menu's "Start again": a new game, its settings kept (Don welcomes the player back).
        app.open("nuclear-war")
        XCTAssertTrue(app.text("Welcome back!").waitForExistence(timeout: 15))
        app.buttons["More"].tap()
        let again = app.buttons["Start again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More stories and levels"].exists, "Nuclear War has no packs")
        again.tap()
        XCTAssertTrue(app.text("Starting again!").waitForExistence(timeout: 10))
        XCTAssertFalse(app.text("Welcome back!").exists, "starting again empties the feed")
        app.waitForLine("Welcome back to nuclear war.", timeout: 40)
        XCTAssertTrue(app.buttons["answer-France"].waitForExistence(timeout: 10))
    }

    /// Every game opens, plays its first turn with its lines, and goes back to the list.
    @MainActor
    func testEveryGameOpens() throws {
        let app = Player.launch()
        let games = [
            "frootopia", "noodle-rush", "signal-decoders", "pirate-quest", "leaning-tower-of-pizza", "alien-customs",
            "the-werewolf", "nuclear-war",
        ]
        for game in games {
            app.open(game)
            XCTAssertTrue(app.text("Tap the picture to skip").waitForExistence(timeout: 15), "\(game) isn't speaking")
            app.skip()
            XCTAssertTrue(
                app.staticTexts.matching(identifier: "spoken").firstMatch.waitForExistence(timeout: 10),
                "\(game) shows no lines")
            XCTAssertTrue(app.text("Your turn!").waitForExistence(timeout: 10), "\(game) asks nothing")
            XCTAssertFalse(app.alerts.firstMatch.exists, "\(game) went wrong")
            app.buttons["Back"].tap()
        }
        XCTAssertTrue(app.text("EPIC AUDIO GAMES").waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// A game's packs, from its pill on the list.
    @MainActor
    func testTheStoreSheet() throws {
        let app = Player.launch()
        let pill = app.buttons["packs-frootopia"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        XCTAssertEqual(pill.label, "+ STORIES 2 TO 5")
        pill.tap()
        let sheet = app.element("store-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no store sheet")
        // fixed (B021): it said "MORE THE KINGDOM OF FROOTOPIA".
        XCTAssertTrue(sheet.text("MORE FROM THE KINGDOM OF FROOTOPIA").exists)
        XCTAssertTrue(sheet.text("Stories 2 to 5").exists)
        // The buy button: GET until the price is known (a spinner while it's asked for, L6), then the price.
        let buy = sheet.buttons.matching(NSPredicate(format: "label == 'GET' OR label CONTAINS '1.99'")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "no GET or price")
        sleep(1)    // the sheet's rise
        app.shot("store-sheet", in: self)
        // This build has no pack server: buying says so, and nothing is bought (L6).
        buy.tap()
        XCTAssertTrue(sheet.text("Packs can't be downloaded in this version of the app yet.").waitForExistence(timeout: 5))
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        // And from a game's menu.
        app.open("frootopia")
        app.buttons["More"].tap()
        let more = app.buttons["More stories and levels"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no store sheet from the menu")
        XCTAssertTrue(sheet.text("MORE FROM THE KINGDOM OF FROOTOPIA").exists)
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.element("talking-circle").exists, "the game is still open")
    }
}

/// The app, as the tests play it.
@MainActor
private enum Player {
    /// The app with no saves, so no game is carried on, and no mic (a phone with no recogniser: no permission is
    /// asked), or [hearing] (the answers it hears, ScriptedListener).
    static func launch(hearing: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        launch(app, hearing: hearing, mic: false)
        return app
    }

    /// [mic]: the device's recogniser, asking for permission as on a phone.
    static func launch(_ app: XCUIApplication, hearing: String?, mic: Bool) {
        app.launchArguments = ["-EpicReset", "YES"]
        if let hearing {
            app.launchArguments += ["-EpicHear", hearing]
        } else if !mic {
            app.launchArguments += ["-EpicMic", "off"]
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.text("EPIC AUDIO GAMES").waitForExistence(timeout: 15))
    }

}

/// The system's permission dialogs, answered with [choice]; [asked] has the dialogs answered.
@MainActor
private final class Dialogs {
    var choice = "Allow"
    var asked: [String] = []

    func answer(_ alert: XCUIElement) -> Bool {
        let button = alert.buttons[choice]
        guard button.exists else { return false }
        asked.append(alert.label)
        button.tap()
        return true
    }

    /// Answers the dialog showing, or the next one within [timeout].
    func answerShowing(timeout: TimeInterval = 15) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout), answer(alert) else { return }
        _ = alert.waitForNonExistence(timeout: 5)
    }
}

@MainActor
private extension XCUIElement {
    /// The text showing [label] (a status, a heading, a pill).
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Enabled within [timeout].
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if exists && isEnabled { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// A game card (one button) says [words] (a pill: PLAY, CONTINUE, CARRY ON), within a few seconds.
    func says(_ words: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if label.components(separatedBy: ", ").contains(words) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }
}

@MainActor
private extension XCUIApplication {
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// A game's card on the list, scrolled to.
    func card(_ game: String) -> XCUIElement {
        let card = element("game-\(game)")
        XCTAssertTrue(text("EPIC AUDIO GAMES").waitForExistence(timeout: 10), "not on the list")
        var swipes = 0
        while !(card.exists && card.isHittable) && swipes < 25 {
            swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(card.isHittable, "no \(game) card")
        return card
    }

    func open(_ game: String) {
        card(game).tap()
        XCTAssertTrue(element("talking-circle").waitForExistence(timeout: 20), "\(game) didn't open")
    }

    /// The feed's game line that has [text] in it.
    func spoken(_ text: String) -> XCUIElement {
        spoken(any: [text])
    }

    func spoken(any texts: [String]) -> XCUIElement {
        let each = texts.map { NSPredicate(format: "identifier == 'spoken' AND label CONTAINS %@", $0) }
        return staticTexts.matching(NSCompoundPredicate(orPredicateWithSubpredicates: each)).firstMatch
    }

    /// The player's answer in the feed, as it shows (VoiceOver reads it "You said: …").
    func reply(_ text: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "identifier == 'reply' AND label == %@", "You said: " + text))
            .firstMatch
    }

    func waitForLine(_ text: String, timeout: TimeInterval = 30) {
        XCTAssertTrue(spoken(text).waitForExistence(timeout: timeout), "no line '\(text)'")
    }

    /// Taps the answer chip sending [value], then waits for the next turn's line.
    func answer(_ value: String, expecting lines: [String]) {
        let chip = buttons["answer-\(value)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "no \(value) chip")
        Thread.sleep(forTimeInterval: 0.6)      // a tap at once is a double tap's second (B032)
        chip.tap()
        XCTAssertTrue(spoken(any: lines).waitForExistence(timeout: 40), "no \(lines) after \(value)")
    }

    func answer(_ value: String, expecting line: String) {
        answer(value, expecting: [line])
    }

    /// Types [text] and sends it with the keyboard's Send.
    func type(_ text: String, expecting line: String? = nil) {
        let field = textFields["answer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text + "\n")
        if let line {
            XCTAssertTrue(spoken(line).waitForExistence(timeout: 40), "no '\(line)' after typing \(text)")
        }
    }

    /// Drags the transcript, at [line], down into the keyboard.
    func dragIntoKeyboard(from line: XCUIElement) {
        let keyboard = keyboards.firstMatch
        let from = line.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.1, thenDragTo: to)
    }

    /// Taps the picture: it skips the voice while the game speaks.
    func skip() {
        let circle = element("talking-circle")
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        circle.tap()
    }

    /// The last question line in the feed, once it isn't [previous].
    func lastQuestion(after previous: String) -> String {
        var last = previous
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let question = spokenLabels().last {
                $0.localizedCaseInsensitiveContains("like to meet") || $0.contains("Round 1")
            }
            last = question ?? previous
            if last != previous { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return last
    }

    /// The feed's game lines on the screen now, in order. Read from one snapshot: the feed changes as it's read, and
    /// an element resolved one at a time can be gone by the time its label is asked for.
    func spokenLabels() -> [String] {
        guard let root = try? snapshot() else { return [] }
        var labels: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if element.identifier == "spoken" { labels.append(element.label) }
            element.children.forEach(walk)
        }
        walk(root)
        return labels
    }

    /// A screenshot, kept in the result bundle, and written to the folder in EPIC_SHOTS when the runner has it
    /// (TEST_RUNNER_EPIC_SHOTS).
    func shot(_ name: String, in test: XCTestCase) {
        let image = screenshot()
        let shot = XCTAttachment(screenshot: image)
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
        if let dir = ProcessInfo.processInfo.environment["EPIC_SHOTS"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
