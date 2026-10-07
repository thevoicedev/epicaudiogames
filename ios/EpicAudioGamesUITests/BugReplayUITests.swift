// Replays the confirmed bugs fixed on iOS (the bug list's B001 to B099) as a player would, and plays every game once
// more (no Kotlin counterpart).

import XCTest

/**
 * Each test names the bugs it replays. The games are played by taps and typing, or, to reach an end quickly, by the
 * Debug build's launch arguments (DebugLaunch.swift: -EpicOpen, -EpicSkip, -EpicSay). Screenshots are kept in the
 * result bundle, and also written to the folder in EPIC_SHOTS when the runner has it (TEST_RUNNER_EPIC_SHOTS).
 */
final class BugReplayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The path through Signal Decoders' chapter 1 (the bug list's B001 steps).
    private static let chapterOne = "yes|C A C|no|no|4 2 2 1 1|follow"

    /// B001 (B024, B084), B006: Signal Decoders' chapter 1 to its end. Left there, it comes back at the end with NEXT
    /// CHAPTER (also after the app starts again), and NEXT CHAPTER plays chapter 2. The closing line stays in view.
    @MainActor
    func testB001AChapterEndComesBackWithNextChapter() throws {
        let p = Phone.launch(self, open: "signal-decoders", say: Self.chapterOne)
        let end = p.endPanel(timeout: 180)
        XCTAssertTrue(end.text("CHAPTER COMPLETE!").exists)
        XCTAssertTrue(end.text("Chapter 1: The First Signal").exists)
        XCTAssertTrue(end.buttons["NEXT CHAPTER"].exists)
        let last = p.spoken("End of chapter one.")
        XCTAssertTrue(last.waitForExistence(timeout: 5), "B006: no closing line")
        XCTAssertTrue(last.isHittable, "B006: the closing line is out of view")
        XCTAssertLessThanOrEqual(last.frame.maxY, end.frame.minY + 1, "B006: the end panel covers the closing line")
        p.shot("B001-signal-decoders-chapter-end")

        end.buttons["BACK TO GAMES"].tap()
        p.note("B001 card after a chapter end: \(p.card("signal-decoders").label)")
        p.open("signal-decoders")
        let back = p.endPanel(timeout: 20)
        XCTAssertTrue(p.text("Welcome back!").exists, "B001: no Welcome back!")
        XCTAssertTrue(back.buttons["NEXT CHAPTER"].exists, "B001: NEXT CHAPTER is gone")
        XCTAssertFalse(p.spoken("Chapter one. The First Signal.").exists, "B001: chapter 1 started again")
        p.shot("B001-signal-decoders-reopened")

        // Started again, the app still has it.
        p.app.terminate()
        let again = Phone.launch(self, reset: false)
        again.open("signal-decoders")
        let kept = again.endPanel(timeout: 20)
        XCTAssertTrue(kept.buttons["NEXT CHAPTER"].exists, "B001: NEXT CHAPTER is gone after a relaunch")
        kept.buttons["NEXT CHAPTER"].tap()
        XCTAssertTrue(again.spoken("Chapter two. The Map in the Music.").waitForExistence(timeout: 30), "no chapter 2")
        XCTAssertTrue(again.text("Next chapter").exists)
        again.shot("B001-signal-decoders-chapter-two")
    }

    /**
     * Alien Customs: "I'm not sure" isn't a yes (B085), "okay" is (B093); level 1 won by its officer's questions;
     * left at its end it comes back there (B001); "no" at level 2's question leaves, keeping the level (B027, B083);
     * deported and left at the game over, it opens at level 2 again (B002, B024, B084); TRY AGAIN retries level 2
     * (B087).
     */
    @MainActor
    func testAlienCustomsKeepsItsLevel() throws {
        let p = Phone.launch(self)
        p.open("alien-customs")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I'm not sure")
        XCTAssertTrue(p.spoken("Are you ready to play Alien Customs?").waitForExistence(timeout: 20), "B085")
        XCTAssertFalse(p.spoken("there is an announcement").exists, "B085: I'm not sure is a yes")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("okay")
        XCTAssertTrue(p.spoken("there is an announcement about").waitForExistence(timeout: 20), "B093: okay isn't a yes")
        XCTAssertEqual(p.playCustoms(), .end)
        let won = p.endPanel()
        XCTAssertTrue(won.text("Level 1 cleared: Science experiment!").exists)
        XCTAssertTrue(won.buttons["NEXT CHAPTER"].exists)
        p.shot("alien-customs-level-1-cleared")
        won.buttons["BACK TO GAMES"].tap()

        p.open("alien-customs")
        let back = p.endPanel(timeout: 20)
        XCTAssertTrue(p.text("Welcome back!").exists, "B001: no Welcome back!")
        XCTAssertTrue(back.text("Level 1 cleared: Science experiment!").exists, "B001: not back at the end")
        back.buttons["NEXT CHAPTER"].tap()
        XCTAssertEqual(p.settle(), .ask)
        p.answer("no")
        XCTAssertTrue(p.text("EPIC AUDIO GAMES").waitForExistence(timeout: 20), "no doesn't leave")
        p.note("B027 card after a quit: \(p.card("alien-customs").label)")
        p.open("alien-customs")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("yes")
        XCTAssertTrue(p.secondLevelItem(), "B027/B083: a quit lost the level")
        p.shot("B027-alien-customs-level-2-after-a-quit")

        XCTAssertEqual(p.playCustoms(wrong: true), .end)
        let over = p.endPanel()
        XCTAssertTrue(over.text("GAME OVER").exists)
        XCTAssertTrue(over.text("Deported!").exists)
        p.shot("alien-customs-deported")
        over.buttons["BACK TO GAMES"].tap()
        p.open("alien-customs")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertFalse(p.text("Welcome back!").exists)
        p.answer("yes")
        XCTAssertTrue(p.secondLevelItem(), "B002/B084: the game over lost the level")

        XCTAssertEqual(p.playCustoms(wrong: true), .end)
        p.endPanel().buttons["TRY AGAIN"].tap()
        XCTAssertEqual(p.settle(), .ask)
        p.answer("yes")
        XCTAssertTrue(p.secondLevelItem(), "B087: TRY AGAIN didn't retry level 2")
    }

    /// B002 (B024, B084): Leaning Tower of Pizza to a game over ("yes" to everything: which one is random); opened
    /// again, it remembers the player, not the first-time tutorial.
    @MainActor
    func testB002LeaningTowerOfPizzaRemembersAfterItsEnd() throws {
        continueAfterFailure = true
        let p = Phone.launch(self, open: "leaning-tower-of-pizza", say: "yes*")
        let end = p.endPanel(timeout: 300)
        p.idle(1.5)
        p.shot("ltop-end")
        XCTAssertTrue(p.newestLineShows(above: end.frame.minY), "B006: the end panel covers the last line")
        p.note("LTOP end: \(p.labels("spoken").suffix(2)) / \(end.staticTexts.allElementsBoundByIndex.map(\.label))")
        end.buttons["BACK TO GAMES"].tap()
        p.open("leaning-tower-of-pizza")
        XCTAssertEqual(p.settle(), .ask)
        let known = p.spoken("Welcome back Pinocchio!").exists || p.spoken("the little wooden boy returns").exists
        XCTAssertTrue(known, "B002: the kept variables were dropped: \(p.labels("spoken"))")
        XCTAssertFalse(p.spoken("save Venice from the evil pizza robot").exists, "B002: the tutorial again")
        p.shot("B002-ltop-reopened")
    }

    /// B054 (B002), B006: The Werewolf lost by taps (yes, yes, then no to everything) and left at its end; opened
    /// again, it's another night with the next story.
    @MainActor
    func testB054TheWerewolfComesBackForAnotherNight() throws {
        continueAfterFailure = true
        let p = Phone.launch(self)
        p.open("the-werewolf")
        for answer in ["yes", "yes"] {
            XCTAssertEqual(p.settle(), .ask)
            p.tap(answer)
        }
        var wait = p.settle()
        var turns = 0
        while wait == .ask && turns < 15 {
            p.tap("no")
            wait = p.settle()
            turns += 1
        }
        XCTAssertEqual(wait, .end)
        let end = p.endPanel()
        p.idle(1.5)
        XCTAssertTrue(p.newestLineShows(above: end.frame.minY), "B006: the end panel covers the last line")
        XCTAssertTrue(end.text("The werewolves got away!").exists)
        XCTAssertTrue(end.buttons["GET 45 MORE MYSTERIES"].exists, "no GET button")
        p.shot("B074-werewolf-end-get")
        end.buttons["BACK TO GAMES"].tap()
        p.open("the-werewolf")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertTrue(p.spoken("Another night.").exists, "B054: the stories played were forgotten")
        XCTAssertFalse(p.spoken("A murder has taken place").exists, "B054: the first night again")
        XCTAssertTrue(p.spoken("The Dark Forest Law").exists, "B054: not the next story")
        p.shot("B054-werewolf-reopened")
    }

    /// B008 (as the chat design reads it), B011: The Werewolf's guess offers one chip, List villagers, which reads the
    /// villagers in the chat; the player says or types a name. The chip's reply is its label.
    @MainActor
    func testB008TheWerewolfGuessIsSaidOrTyped() throws {
        let p = Phone.launch(self, open: "the-werewolf", say: Array(repeating: "yes", count: 11).joined(separator: "|"))
        XCTAssertTrue(p.spoken("Who do you think is the werewolf?").waitForExistence(timeout: 240), "no guess")
        XCTAssertEqual(p.settle(), .ask)
        let chips = p.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'answer-'"))
        XCTAssertEqual(chips.count, 1, "the guess's chips")
        let list = p.app.buttons["answer-list villagers"]
        XCTAssertEqual(list.label, "List villagers")
        XCTAssertTrue(list.isHittable)
        p.shot("werewolf-accusation-chips")
        p.tap("list villagers")
        XCTAssertTrue(p.reply("List villagers").waitForExistence(timeout: 10), "B011: the reply isn't the chip's label")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertTrue(p.spoken("the barmaid").exists, "the villagers aren't in the chat: \(p.feed().suffix(3))")
        p.answer("the barmaid")
        XCTAssertTrue(p.spoken("You chuck the barmaid in jail!").waitForExistence(timeout: 30), "the name wasn't taken")
        XCTAssertTrue(p.reply("the barmaid").exists)
    }

    /// B093, B086: The Werewolf takes "okay" and "not now"; "go for it" isn't story 4, and "I want to play" plays the
    /// story offered (not story 2).
    @MainActor
    func testB086TheWerewolfOfferTakesWhatsSaid() throws {
        let p = Phone.launch(self)
        p.open("the-werewolf")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("okay")
        XCTAssertTrue(p.spoken("Time to choose a mystery.").waitForExistence(timeout: 20), "B093: okay isn't a yes")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("not now")
        XCTAssertTrue(p.spoken("The Dark Forest Law. A new law").waitForExistence(timeout: 20), "B093: not now isn't a no")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("go for it")
        XCTAssertTrue(p.answered("go for it", with: "The Dark Forest Law. A new law"), "go for it wasn't asked again")
        XCTAssertFalse(p.spoken("The Christmas Secret").exists, "B086: go for it is story 4")
        XCTAssertFalse(p.spoken("The Full Moon Festival").exists, "B086: go for it is a number")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I want to play")
        XCTAssertTrue(p.spoken("Want to talk to").waitForExistence(timeout: 20), "B086: I want to play isn't a yes")
        p.shot("B086-werewolf-offer")
    }

    /// B092, B086: Signal Decoders' first puzzles: "esos again" is a try (its pattern works), and "I need to listen to
    /// it again" hears the puzzle again rather than counting as a wrong guess.
    @MainActor
    func testB092SignalDecodersPuzzles() throws {
        let p = Phone.launch(self)
        p.open("signal-decoders")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("yes")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("esos again")
        XCTAssertTrue(p.spoken("Hmm. Not quite. Listen again.").waitForExistence(timeout: 20), "B092: not a try")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("C A C")
        XCTAssertTrue(p.spoken("Yes! C, A, C.").waitForExistence(timeout: 20))
        XCTAssertEqual(p.settle(), .ask)
        p.answer("no")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("no")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I need to listen to it again")
        XCTAssertTrue(p.spoken("Listen again, and count each group.").waitForExistence(timeout: 20), "B086")
        XCTAssertFalse(p.spoken("Let's count each group together.").exists, "B086: a wrong guess")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("4 2 2 1 1")
        XCTAssertTrue(p.spoken("Four. Two. Two. One. One.").waitForExistence(timeout: 20))
        p.shot("B092-signal-decoders-puzzles")
    }

    /// B085 and Noodle Rush's yes and no: unsure or negated answers are neither yes nor no; Noodle Rush takes
    /// "I'm ready".
    @MainActor
    func testB085UnsureIsNeitherYesNorNo() throws {
        let p = Phone.launch(self)
        p.open("frootopia")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I'm not sure")
        XCTAssertTrue(p.answered("I'm not sure", with: "Sorry, I didn't catch that."), "B085: I'm not sure was taken")
        XCTAssertFalse(p.spoken("Okay, so here's the thing.").exists, "B085: I'm not sure is a yes")
        for said in ["I don't know", "of course not"] {
            XCTAssertEqual(p.settle(), .ask)
            p.answer(said)
            XCTAssertTrue(p.answered(said, with: "Sorry, I didn't catch that."), "B085: \(said) was taken: \(p.feed())")
        }
        XCTAssertTrue(p.element("talking-circle").exists, "B085: a no left the game")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("yes")
        XCTAssertTrue(p.spoken("Okay, so here's the thing.").waitForExistence(timeout: 20))
        p.shot("B085-frootopia")
        p.leave()

        p.open("noodle-rush")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I'm not sure")
        XCTAssertTrue(p.spoken("Are you ready to play Noodle Rush? Say yes, or no.").waitForExistence(timeout: 20))
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I'm ready")
        XCTAssertTrue(p.spoken("Slurpy's Noodle Bar hums").waitForExistence(timeout: 20), "I'm ready isn't a yes")
        p.shot("noodle-rush-im-ready")
    }

    /// B094, B085, B011, B047: Nuclear War takes "US"; "I'm not sure" asks again and "absolutely not" is a no; a tapped
    /// country shows its label; a list read out stays in view.
    @MainActor
    func testB094NuclearWarUnderstandsUSAndNo() throws {
        let p = Phone.launch(self)
        p.open("nuclear-war")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertEqual(p.app.buttons["answer-USA"].label, "the USA")
        p.shot("nuclear-war-country-chips")
        p.answer("US")
        XCTAssertTrue(p.reached("You are now the leader of the USA."), "B094")
        var rounds = 0
        while rounds < 8 {
            XCTAssertEqual(p.settle(), .ask)
            if p.reached("Do you want to invest in nuclear tech?", wait: 1) { break }
            p.answer("no")
            rounds += 1
        }
        XCTAssertEqual(p.settle(), .ask)
        p.answer("I'm not sure")
        XCTAssertTrue(p.reached("Would you like to spend 5 million on nuclear tech?"), "B085")
        XCTAssertEqual(p.settle(), .ask)
        p.answer("absolutely not")
        XCTAssertTrue(p.reached("improve the environment by 15%"), "B085")
        XCTAssertFalse(p.spoken("You now have nuclear tech").exists, "B085: absolutely not bought nuclear tech")
        XCTAssertEqual(p.settle(), .ask)
        continueAfterFailure = true
        p.answer("no")
        XCTAssertEqual(p.settle(), .ask)
        p.idle(1.5)
        XCTAssertTrue(p.spoken("cities to defend and improve").exists, "B006/B047: the new question is out of view")
        p.shot("B047-nuclear-war-cities-keyboard-up")
        XCTAssertTrue(p.newestLineShows(), "B006/B047: the question is under the answers, keyboard up")
        p.hideKeyboard()
        p.idle(1.5)
        p.shot("B047-nuclear-war-cities")
        XCTAssertTrue(p.newestLineShows(), "B047: the question is under the answers, keyboard down")

        // A new game, by the menu: the country tapped shows its label.
        p.app.buttons["More"].tap()
        let again = p.app.buttons["Start again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        XCTAssertTrue(p.text("Starting again!").waitForExistence(timeout: 10))
        XCTAssertEqual(p.settle(), .ask)
        p.tap("USA")
        XCTAssertTrue(p.spoken("You are now the leader of the USA.").waitForExistence(timeout: 20))
        XCTAssertTrue(p.reply("the USA").exists, "B011: the reply isn't the chip's label")
        p.shot("B011-nuclear-war-reply-label")
    }

    /// B032, B011, B003, B041: a double tap answers once (its reply the chip's label); "stop" typed pauses and puts
    /// the keyboard away, which stays away after the background; a tap carries on.
    @MainActor
    func testB032ADoubleTapAnswersOnce() throws {
        let p = Phone.launch(self)
        p.open("noodle-rush")
        XCTAssertEqual(p.settle(), .ask)
        p.idle(0.6)
        p.app.buttons["answer-yes"].doubleTap()
        XCTAssertTrue(p.spoken("Slurpy's Noodle Bar hums").waitForExistence(timeout: 20))
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertFalse(p.spoken("You step inside.").exists, "B032: the double tap answered the next question")
        XCTAssertEqual(p.labels("reply"), ["Yes"], "B032/B011: the replies")
        p.shot("B032-noodle-rush-double-tap")

        // B006: the keyboard up, the question still shows.
        continueAfterFailure = true
        p.app.textFields["answer-field"].tap()
        XCTAssertTrue(p.app.keyboards.firstMatch.waitForExistence(timeout: 5))
        p.idle(1.5)
        p.shot("B006-noodle-rush-keyboard-up")
        XCTAssertTrue(p.newestLineShows(), "B006: the keyboard hides the question")

        let paused = p.element("paused")
        let keyboard = p.app.keyboards.firstMatch
        p.type("stop")
        XCTAssertTrue(paused.waitForExistence(timeout: 10), "stop doesn't pause")
        p.idle(1)
        p.shot("B003-after-a-typed-stop")
        XCTAssertFalse(keyboard.exists, "B003: the keyboard stays up over the pause after a typed stop")
        p.carryOnPaused(answering: "yes", expecting: "You step inside.")

        // Typing, then the background: the game doesn't pause (it plays on with the phone locked), and the question
        // still waits for its answer.
        XCTAssertEqual(p.settle(), .ask)
        p.app.textFields["answer-field"].tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        p.idle(2)
        p.app.activate()
        p.idle(1)
        p.shot("B003-after-the-background")
        XCTAssertFalse(paused.exists, "the background paused the game")
        XCTAssertEqual(p.settle(), .ask)
    }

    /// B021, B022, B013 (B066), B014, B043: the store sheets' heading; an error in one sheet isn't in the next; Restore
    /// purchases says how it went; the sheet from a game's menu pauses the game.
    @MainActor
    func testB013TheStoreSheets() throws {
        let p = Phone.launch(self)
        let pill = p.app.buttons["packs-frootopia"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()
        let sheet = p.element("store-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.text("MORE FROM THE KINGDOM OF FROOTOPIA").exists, "B021")
        p.idle(1)
        p.shot("B021-store-sheet-frootopia")
        // GET, or the price once the App Store says it (the sandbox has the products now): with no pack server,
        // either one says so and buys nothing.
        let buy = sheet.buttons.matching(NSPredicate(format: "label == 'GET' OR label CONTAINS '1.99'")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 10), "no GET or price")
        buy.tap()
        let noServer = "Packs can't be downloaded in this version of the app yet."
        XCTAssertTrue(sheet.text(noServer).waitForExistence(timeout: 5))
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        let werewolf = p.pill("the-werewolf")
        werewolf.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.text("MORE FROM THE WEREWOLF").exists, "B021")
        XCTAssertFalse(sheet.text(noServer).exists, "B013: the last sheet's error shows here")
        sheet.buttons["Restore purchases"].tap()
        let said = sheet.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'store-message' OR identifier == 'store-note'")).firstMatch
        continueAfterFailure = true
        // With no Apple Account on the simulator, iOS asks to sign in first: the player cancels.
        let signIn = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        let appSignIn = p.app.alerts.firstMatch
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && !said.exists && !signIn.exists && !appSignIn.exists { p.idle(0.5) }
        for alert in [signIn, appSignIn] where alert.exists {
            p.note("B014: Restore purchases asks: \(alert.label)")
            p.shot("B014-sign-in")
            alert.buttons["Cancel"].tap()
        }
        XCTAssertTrue(said.waitForExistence(timeout: 30), "B014: Restore purchases says nothing")
        p.note("B014 restore says: \(said.exists ? said.label : "nothing")")
        p.idle(1)
        p.shot("B014-restore-purchases")
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))

        // B043: from the game's menu while it talks.
        p.open("frootopia")
        p.app.buttons["More"].tap()
        let more = p.app.buttons["More stories and levels"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        p.idle(1)
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(p.element("paused").waitForExistence(timeout: 5), "B043: the game played on under the sheet")
        p.shot("B043-frootopia-paused-after-the-sheet")
    }

    /// B012 (B046), B009 (B048): the list is where it was after a game; while a game loads, the list takes no taps.
    @MainActor
    func testB012TheListKeepsItsPlace() throws {
        let p = Phone.launch(self)
        let pill = p.pill("the-werewolf")
        let card = p.element("game-the-werewolf")
        let top = card.frame.minY
        // B009: the card, then at once its packs pill (under the loading overlay by then).
        let at = pill.frame
        let screen = p.app.coordinate(withNormalizedOffset: .zero)
        screen.withOffset(CGVector(dx: at.midX, dy: at.midY - 70)).tap()      // the card's words, above its pill
        screen.withOffset(CGVector(dx: at.midX, dy: at.midY)).tap()
        XCTAssertTrue(p.element("talking-circle").waitForExistence(timeout: 30), "the game didn't open")
        XCTAssertFalse(p.element("store-sheet").waitForExistence(timeout: 3), "B009: a sheet opened over the loading")
        p.leave()
        let again = p.element("game-the-werewolf")
        XCTAssertTrue(again.waitForExistence(timeout: 5) && again.isHittable, "B012: the list went back to its top")
        p.note("B012: the card's top was at \(top), is at \(again.frame.minY)")
        p.shot("B012-home-after-the-werewolf")
    }

    /// B063, B075, B020: by voice (a script heard in place of the mic): listening, the mic says "Stop listening" and
    /// the picture "Talk"; the text box stops the listening, and the question isn't asked again while typing; after a
    /// typed answer the mic waits.
    @MainActor
    func testB063TypingStopsTheMic() throws {
        let p = Phone.launch(self, hearing: "yes")
        p.open("noodle-rush")
        XCTAssertTrue(p.spoken("Noodle Rush!").waitForExistence(timeout: 40))
        p.skip()
        XCTAssertTrue(p.text("Listening…").waitForExistence(timeout: 10))
        let mic = p.app.buttons["mic"]
        XCTAssertEqual(mic.label, "Stop listening", "B075")
        XCTAssertEqual(p.element("talking-circle").label, "Stop listening", "B020: a tap on it stops listening")
        XCTAssertTrue(p.spoken("Slurpy's Noodle Bar hums").waitForExistence(timeout: 30), "yes wasn't heard")
        XCTAssertEqual(p.element("talking-circle").label, "Skip", "B020")
        p.skip()
        XCTAssertTrue(p.text("Listening…").waitForExistence(timeout: 10))
        p.shot("B075-listening")

        p.app.textFields["answer-field"].tap()
        XCTAssertTrue(p.text("Your turn! Tap the mic to talk").waitForExistence(timeout: 5), "B063: still listening")
        p.idle(8)
        XCTAssertFalse(p.element("paused").exists, "B063: paused while typing")
        XCTAssertEqual(p.count("Do you want to go inside?"), 1, "B063: asked again while typing")
        p.app.textFields["answer-field"].typeText("yes\n")
        XCTAssertTrue(p.spoken("You step inside.").waitForExistence(timeout: 20))
        p.skip()
        XCTAssertTrue(p.text("Your turn! Tap the mic to talk").waitForExistence(timeout: 10))
        p.idle(3)
        XCTAssertFalse(p.text("Listening…").exists, "B063: the mic opened by itself while typing")
        p.shot("B063-typing")
    }

    /**
     * B015 (B042, B080): the mic refused as a game opens; the mic button still works, and leads to a "The microphone
     * is off" alert with Settings. Speech recognition may or may not have been asked before (simctl can't reset it;
     * `simctl privacy reset all` can): either way the button must do something.
     */
    @MainActor
    func testB015TheMicOffLeadsToSettings() throws {
        let dialogs = SystemDialogs()
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        dialogs.choice = "Don’t Allow"
        let p = Phone.launch(self, app: app, mic: true)
        p.open("noodle-rush")
        dialogs.answerShowing()
        XCTAssertTrue(dialogs.asked.contains { $0.contains("Microphone") }, "the mic wasn't asked for: \(dialogs.asked)")
        p.note("B015 dialogs: \(dialogs.asked)")
        XCTAssertTrue(p.spoken("Noodle Rush!").waitForExistence(timeout: 40))
        p.skip()
        XCTAssertTrue(p.yourTurn.waitForExistence(timeout: 10))
        let mic = p.app.buttons["mic"]
        XCTAssertTrue(mic.isEnabled, "B015: the mic button is off")
        XCTAssertEqual(mic.label, "Talk (the microphone is off)", "B075")
        mic.tap()
        dialogs.answerShowing(timeout: 3)
        let alert = p.app.alerts["The microphone is off"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "B015: tapping the mic does nothing (dialogs: \(dialogs.asked))")
        XCTAssertTrue(alert.buttons["Settings"].exists)
        p.shot("B015-microphone-is-off")
        alert.buttons["Not now"].tap()
        p.leave()
        // B080: no dialog again for the next game.
        dialogs.asked = []
        p.open("frootopia")
        dialogs.answerShowing(timeout: 5)
        XCTAssertEqual(dialogs.asked, [], "B080: asked again")
    }

    /// B076, B082: with the largest text, the end panel scrolls to its last button; a long title takes two lines.
    @MainActor
    func testB076PanelsScrollWithTheLargestText() throws {
        let p = Phone.launch(self, open: "signal-decoders", say: Self.chapterOne,
                             extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let end = p.endPanel(timeout: 180)
        p.shot("B076-end-panel-largest-text")
        let back = end.buttons["BACK TO GAMES"]
        XCTAssertTrue(back.exists)
        var swipes = 0
        while !back.isHittable && swipes < 6 {
            end.swipeUp(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(back.isHittable, "B076: BACK TO GAMES can't be reached")
        p.shot("B076-end-panel-scrolled")
        back.tap()
        p.open("frootopia")
        let title = p.app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'kingdom of frootopia'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        p.idle(1)
        p.shot("B082-header-largest-text")
        XCTAssertTrue(p.app.textFields["answer-field"].exists)
    }

    /// Frootopia's first story by yes alone, to its end, which its pack goes on from: GET (dark text, B074), the
    /// store sheet from it, and opened again without the pack, story 1 from its start.
    @MainActor
    func testFrootopiaToTheEndOfItsFirstStory() throws {
        let p = Phone.launch(self, open: "frootopia", say: "yes*")
        continueAfterFailure = true
        let end = p.endPanel(timeout: 600)
        p.idle(1.5)
        XCTAssertTrue(p.newestLineShows(above: end.frame.minY), "B006: the end panel covers the last line")
        XCTAssertTrue(end.text("CHAPTER COMPLETE!").exists)
        XCTAssertFalse(end.buttons["NEXT CHAPTER"].exists, "a next chapter with no pack")
        let get = end.buttons["GET STORIES 2 TO 5"]
        XCTAssertTrue(get.exists, "no GET button")
        p.shot("B074-frootopia-end-get")
        get.tap()
        let sheet = p.element("store-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertFalse(p.element("paused").exists, "paused at an end")
        p.endPanel().buttons["BACK TO GAMES"].tap()
        p.open("frootopia")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertTrue(p.spoken("Cosmo! Cosmo, wake up!").exists, "not story 1's start")
        p.shot("frootopia-reopened-without-its-pack")
    }

    /// Every game: a chip, a typed answer, skipping, leaving (CONTINUE, CARRY ON), and coming back ("Welcome back!").
    @MainActor
    func testEveryGamePlaysLeavesAndComesBack() throws {
        let p = Phone.launch(self)
        let games = [
            "frootopia", "noodle-rush", "signal-decoders", "pirate-quest", "leaning-tower-of-pizza", "alien-customs",
            "the-werewolf", "nuclear-war",
        ]
        for game in games {
            p.open(game)
            XCTAssertTrue(p.text("Tap the picture to skip").waitForExistence(timeout: 20), "\(game) isn't speaking")
            XCTAssertEqual(p.settle(), .ask, "\(game) asks nothing")
            let button = p.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'answer-'")).firstMatch
            XCTAssertTrue(button.exists, "\(game) has no chips")
            XCTAssertTrue(button.isHittable, "\(game)'s chips are out of view")
            let label = button.label
            p.idle(0.6)
            button.tap()
            XCTAssertTrue(p.waitForReply { $0.caseInsensitiveCompare(label) == .orderedSame }, "\(game): no \(label) reply")
            XCTAssertEqual(p.settle(), .ask, "\(game) after \(label)")
            p.answer("yes")
            XCTAssertTrue(p.waitForReply { $0 == "yes" }, "\(game): no typed reply")
            let after = p.settle()
            XCTAssertNotNil(after, "\(game) after yes")
            p.shot("every-game-\(game)")
            p.leave()
            let card = p.card(game)
            if after == .ask {
                XCTAssertTrue(card.says("CONTINUE"), "\(game) isn't carried on: \(card.label)")
                XCTAssertTrue(card.says("CARRY ON"), "\(game) isn't carried on: \(card.label)")
                p.open(game)
                XCTAssertTrue(p.text("Welcome back!").waitForExistence(timeout: 15), "\(game): no Welcome back!")
                XCTAssertFalse(p.app.alerts.firstMatch.exists, "\(game) went wrong")
                p.leave()
            }
        }
        XCTAssertFalse(p.app.alerts.firstMatch.exists)
    }

    /**
     * B036: a Nuclear War save whose state can't be read starts a new game (keeping the settings that can be read),
     * with no "Welcome back!". The broken save is put in the app's container first, so this runs only when asked
     * (TEST_RUNNER_EPIC_B036=1).
     */
    @MainActor
    func testB036AnUnreadableNuclearWarSaveStartsAfresh() throws {
        guard ProcessInfo.processInfo.environment["EPIC_B036"] == "1" else {
            throw XCTSkip("needs a broken nuclear-war save in the app's container (EPIC_B036)")
        }
        let p = Phone.launch(self, reset: false)
        p.note("B036 card: \(p.card("nuclear-war").label)")
        p.open("nuclear-war")
        XCTAssertEqual(p.settle(), .ask)
        XCTAssertFalse(p.app.alerts.firstMatch.exists, "B036: went wrong")
        XCTAssertFalse(p.text("Welcome back!").exists, "B036: the broken save was picked up")
        XCTAssertTrue(p.spoken("Welcome back to nuclear war.").exists, "B036: the readable settings were lost")
        XCTAssertTrue(p.app.buttons["answer-France"].waitForExistence(timeout: 10))
        p.shot("B036-nuclear-war-fresh")
    }
}

/// The app as the tests play it.
@MainActor
private struct Phone {
    let app: XCUIApplication
    let test: XCTestCase

    enum Wait: Equatable {
        case ask, end, paused
    }

    /**
     * The app, every save cleared unless [reset] is false, with no mic (taps and typing), or hearing [hearing]
     * (ScriptedListener), or [mic] the phone's recogniser. [open]: that game opened at once, its voice skipped and
     * its questions answered with [say] (DebugLaunch).
     */
    static func launch(
        _ test: XCTestCase, app: XCUIApplication = XCUIApplication(), reset: Bool = true, hearing: String? = nil,
        mic: Bool = false, open: String? = nil, say: String? = nil, extra: [String] = []
    ) -> Phone {
        // No pack server, whatever the build has: buying says so and buys nothing (L6).
        var args = (reset ? ["-EpicReset", "YES"] : []) + ["-EpicPacksURL", ""]
        if let hearing {
            args += ["-EpicHear", hearing]
        } else if !mic {
            args += ["-EpicMic", "off"]
        }
        if let open {
            args += ["-EpicOpen", open, "-EpicSkip", "YES"]
            if let say { args += ["-EpicSay", say] }
        }
        app.launchArguments = args + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let phone = Phone(app: app, test: test)
        if let open {
            XCTAssertTrue(phone.element("talking-circle").waitForExistence(timeout: 30), "\(open) didn't open")
        } else {
            XCTAssertTrue(phone.text("EPIC AUDIO GAMES").waitForExistence(timeout: 15))
        }
        return phone
    }

    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func text(_ label: String) -> XCUIElement { app.text(label) }

    /// The feed's game line with [part] in it.
    func spoken(_ part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'spoken' AND label CONTAINS %@", part)).firstMatch
    }

    /// How many game lines have [part] in them.
    func count(_ part: String) -> Int {
        labels("spoken").filter { $0.contains(part) }.count
    }

    /// The feed on the screen now, in order: "> " before a reply, a game line as it is.
    func feed() -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var feed: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if element.identifier == "reply" { feed.append("> " + Self.said(element.label)) }
            if element.identifier == "spoken" { feed.append(element.label) }
            element.children.forEach(walk)
        }
        walk(root)
        return feed
    }

    /// The latest reply is [said], and a game line after it has [part] in it, within a while.
    func answered(_ said: String, with part: String, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let feed = feed()
            if let at = feed.lastIndex(where: { $0.hasPrefix("> ") }), feed[at] == "> " + said,
               feed[(at + 1)...].contains(where: { $0.contains(part) }) {
                return true
            }
            idle(0.3)
        } while Date() < deadline
        return false
    }

    /// A reply in the feed showing [text] (VoiceOver reads it "You said: …").
    func reply(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'reply' AND label == %@", "You said: " + text))
            .firstMatch
    }

    /// What a reply shows, from what VoiceOver reads ("You said: yes").
    static func said(_ label: String) -> String {
        label.hasPrefix("You said: ") ? String(label.dropFirst("You said: ".count)) : label
    }

    func waitForReply(timeout: TimeInterval = 15, _ matches: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if labels("reply").contains(where: matches) { return true }
            idle(0.3)
        } while Date() < deadline
        return false
    }

    /// The status under the picture while the game waits for an answer.
    var yourTurn: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your turn!'")).firstMatch
    }

    /**
     * A game line with [part] in it shows, within [wait] seconds; failing that, the transcript is dragged to its end
     * by hand (it doesn't always get there by itself, B006) and looked at again.
     */
    func reached(_ part: String, wait: TimeInterval = 8) -> Bool {
        if spoken(part).waitForExistence(timeout: wait) { return true }
        if app.keyboards.firstMatch.exists {
            hideKeyboard()
            if spoken(part).waitForExistence(timeout: 1) {
                note("'\(part)' was there, below the transcript's view while the keyboard was up")
                return true
            }
        }
        let circle = element("talking-circle").frame
        let bottom = app.textFields["answer-field"].frame.minY - 30
        let top = circle.maxY + 50
        guard bottom - top > 20 else { return false }
        let screen = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<3 {
            screen.withOffset(CGVector(dx: circle.midX, dy: bottom))
                .press(forDuration: 0.05, thenDragTo: screen.withOffset(CGVector(dx: circle.midX, dy: top)))
        }
        let found = spoken(part).waitForExistence(timeout: 3)
        if found { note("'\(part)' was there, below the transcript's view") }
        return found
    }

    /**
     * The newest game line's foot shows, and under it the chips (if the question has them), above the bar to answer
     * (or [top], the end panel's), not under it or the keyboard.
     */
    func newestLineShows(above top: CGFloat? = nil) -> Bool {
        let lines = app.staticTexts.matching(identifier: "spoken")
        let n = lines.count
        guard n > 0 else { return false }
        let last = lines.element(boundBy: n - 1).frame
        let bar = top ?? app.textFields["answer-field"].frame.minY - 10
        let chips = element("chips")
        let chipsFrame = chips.exists ? chips.frame : nil
        note("newest line \(last), chips \(chipsFrame.map { "\($0)" } ?? "none"), the bar from \(bar)")
        if let chipsFrame, chipsFrame.maxY > bar + 3 { return false }
        return last.maxY <= (chipsFrame?.minY ?? bar) + 3 && last.height > 0
    }

    /// The labels of the elements with [id], in order, from one snapshot (the feed changes as it's read); a reply's
    /// is what it shows.
    func labels(_ id: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var labels: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if element.identifier == id { labels.append(id == "reply" ? Self.said(element.label) : element.label) }
            element.children.forEach(walk)
        }
        walk(root)
        return labels
    }

    /// A game's card on the list, scrolled to (up or down: the list keeps its place).
    @discardableResult
    func card(_ game: String) -> XCUIElement {
        let card = element("game-\(game)")
        XCTAssertTrue(text("EPIC AUDIO GAMES").waitForExistence(timeout: 15), "not on the list")
        var swipes = 0
        var up = true
        while !(card.exists && card.isHittable) && swipes < 30 {
            if card.exists {
                up = card.frame.midY > app.frame.midY
            } else if swipes == 10 {
                up = false
            }
            if up { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            swipes += 1
        }
        XCTAssertTrue(card.isHittable, "no \(game) card")
        return card
    }

    /// A game card's packs pill, scrolled up into view (it's at the card's foot).
    func pill(_ game: String) -> XCUIElement {
        card(game)
        let pill = app.buttons["packs-\(game)"]
        var nudges = 0
        while !(pill.exists && pill.isHittable) && nudges < 5 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            nudges += 1
        }
        XCTAssertTrue(pill.exists && pill.isHittable, "no packs pill on \(game)")
        return pill
    }

    func open(_ game: String) {
        card(game).tap()
        XCTAssertTrue(element("talking-circle").waitForExistence(timeout: 30), "\(game) didn't open")
    }

    /// The header's back arrow, to the list.
    func leave() {
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(text("EPIC AUDIO GAMES").waitForExistence(timeout: 15), "not back on the list")
    }

    func skip() {
        let circle = element("talking-circle")
        if circle.exists { circle.tap() }
    }

    /// Skips the voice until the game waits: for an answer, at an end, or paused (nil: none of them in time).
    @discardableResult
    func settle(_ timeout: TimeInterval = 60) -> Wait? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element("end-panel").exists { return .end }
            if element("paused").exists { return .paused }
            if text("Tap the picture to skip").exists {
                skip()
                idle(0.3)
                continue
            }
            if yourTurn.exists { return .ask }
            idle(0.25)
        }
        return nil
    }

    func endPanel(timeout: TimeInterval = 30) -> XCUIElement {
        let end = element("end-panel")
        XCTAssertTrue(end.waitForExistence(timeout: timeout), "no end panel")
        return end
    }

    /// Taps the answer chip sending [value], once the question is old enough for a tap to count (B032).
    func tap(_ value: String) {
        let chip = app.buttons["answer-\(value)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "no \(value) chip")
        idle(0.6)
        chip.tap()
        _ = yourTurn.waitForNonExistence(timeout: 5)
    }

    /// Types [text] and sends it; the keyboard stays up.
    func type(_ text: String) {
        let field = app.textFields["answer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text + "\n")
    }

    /// Types an answer, then waits for the game to take it (the question's status goes).
    func answer(_ text: String) {
        type(text)
        _ = yourTurn.waitForNonExistence(timeout: 5)
    }

    /// Drags the transcript down into the keyboard, which puts it away.
    func hideKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        // From the top of the transcript, just under the picture and its status.
        let circle = element("talking-circle").frame
        let screen = app.coordinate(withNormalizedOffset: .zero)
        let from = screen.withOffset(CGVector(dx: circle.midX, dy: circle.maxY + 60))
        let to = keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "the keyboard can't be put away")
    }

    /**
     * Paused: with the keyboard still up, types [answer], which must carry on (B003: not play under the pause), and
     * [expecting] follows; with it gone, taps the pause, and the question is asked again.
     */
    func carryOnPaused(answering answer: String, expecting line: String?) {
        let paused = element("paused")
        if app.keyboards.firstMatch.exists {
            app.textFields["answer-field"].typeText(answer + "\n")
            XCTAssertTrue(paused.waitForNonExistence(timeout: 5), "B003: an answer typed while paused plays under it")
            if let line { XCTAssertTrue(spoken(line).waitForExistence(timeout: 20), "no '\(line)'") }
            note("B003: typed '\(answer)' while paused; paused now: \(paused.exists)")
        } else {
            paused.tap()
            XCTAssertTrue(paused.waitForNonExistence(timeout: 5))
            XCTAssertEqual(settle(), .ask, "carrying on doesn't ask again")
        }
    }

    func idle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // ----- Alien Customs -----

    /// Each officer question of levels 1 and 2 (games/alien-customs/map.json, <item>_q0 to _q3), and its right answer.
    static let officer: [String: String] = [
        "Are you aware that on Jupiter, magnifying glasses are classified as weapons of mass observation?": "no",
        "Is this magnifying glass strong enough to read fine print?": "yes",
        "Do you promise not to use this to start fires on Jupiter?": "yes",
        "Have you ever used this magnifying glass to spy on insects?": "no",
        "Rubber gloves! Are these for cleaning purposes?": "yes",
        "Are these gloves latex free?": "yes",
        "Do these gloves fit you properly?": "yes",
        "Have you ever worn these gloves to commit a crime?": "no",
        "Is this bear registered?": "no",
        "Does this teddy bear have a name?": "yes",
        "Is this teddy bear soft?": "yes",
        "Do you sleep with this teddy bear?": "yes",
        "A passport! Have you ever visited Mars?": "no",
        "Is this passport less than 5 Jupiter years old?": "yes",
        "Do you have more than 3 stamps from other planets?": "no",
        "Is your passport photo a good likeness of you?": "yes",
        "Will you contribute to the power grid?": "yes",
        "Is your laptop fully charged right now?": "yes",
        "Do you promise to brush your teeth at least twice a day while using this laptop?": "yes",
        "Is there anything hidden inside this laptop?": "no",
        "A toothbrush! Is this a manual toothbrush?": "yes",
        "Do you brush more than twice a day?": "yes",
        "Are the bristles on this toothbrush still firm?": "yes",
        "Will you commit to brushing at public power stations?": "yes",
    ]

    /// The right answer to the latest officer question in [lines].
    static func officerAnswer(_ lines: [String]) -> String? {
        for line in lines.reversed() {
            let found = officer.compactMap { q, a in line.range(of: q).map { ($0.lowerBound, a) } }
            if let last = found.max(by: { $0.0 < $1.0 }) { return last.1 }
        }
        return nil
    }

    /**
     * Plays Alien Customs from where it waits until an end: "play" at each announcement, "yes" at the level's question,
     * and each officer question its right answer, or [wrong] the other one. Typed (the keyboard stays up).
     */
    func playCustoms(wrong: Bool = false) -> Wait? {
        for _ in 0..<80 {
            guard let wait = settle() else { return nil }
            if wait != .ask { return wait }
            let lines = labels("spoken")
            if app.buttons["answer-play"].exists {
                answer("play")
            } else if let right = Self.officerAnswer(lines) {
                answer(wrong ? (right == "yes" ? "no" : "yes") : right)
            } else if lines.last?.contains("ready to play") == true {
                answer("yes")
            } else {
                XCTFail("an unknown question: \(lines.last ?? "none")")
                return nil
            }
        }
        return nil
    }

    /// Level 2's first item is announced (not level 1's).
    func secondLevelItem() -> Bool {
        let second = ["announcement about passports", "announcement about laptops", "announcement about toothbrushes"]
        let first = ["announcement about magnifying", "announcement about rubber", "announcement about teddy"]
        let deadline = Date().addingTimeInterval(30)
        repeat {
            let lines = labels("spoken")
            if lines.contains(where: { l in first.contains { l.contains($0) } }) { return false }
            if lines.contains(where: { l in second.contains { l.contains($0) } }) { return true }
            idle(0.3)
        } while Date() < deadline
        return false
    }

    // ----- Records -----

    func shot(_ name: String) {
        let image = app.screenshot()
        let shot = XCTAttachment(screenshot: image)
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
        if let dir = ProcessInfo.processInfo.environment["EPIC_SHOTS"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// A line for the report, in the log and the result bundle.
    func note(_ text: String) {
        print("REPLAY NOTE: \(text)")
        let note = XCTAttachment(string: text)
        note.name = "note"
        note.lifetime = .keepAlways
        test.add(note)
    }
}

/// The system's permission dialogs, answered with [choice]; [asked] has the dialogs answered.
@MainActor
private final class SystemDialogs {
    var choice = "Allow"
    var asked: [String] = []

    /// Answers the dialog showing, or the next one within [timeout].
    func answerShowing(timeout: TimeInterval = 15) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        let button = alert.buttons[choice]
        guard button.exists else { return }
        asked.append(alert.label)
        button.tap()
        _ = alert.waitForNonExistence(timeout: 5)
    }
}

@MainActor
private extension XCUIElement {
    /// The text showing [label].
    func text(_ label: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A game card says [words] (a pill: PLAY, CONTINUE, CARRY ON), within a few seconds.
    func says(_ words: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if label.components(separatedBy: ", ").contains(words) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }
}
