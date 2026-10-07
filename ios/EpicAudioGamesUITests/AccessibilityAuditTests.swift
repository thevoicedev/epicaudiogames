// Xcode's accessibility audit on the app's main screens (no Kotlin counterpart; the plan's Phase 8).

import XCTest

/**
 * performAccessibilityAudit() on the game list, a game asking a question (its chips showing), an end panel and the
 * store sheet. What the audit flags and the app means is let through below, each with its reason (docs/IOS_PARITY.md
 * lists them too).
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

    // ----- The app and the audit -----

    /// The app with no saves and no mic (taps and typing), and [extra] launch arguments (DebugLaunch).
    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-EpicReset", "YES", "-EpicMic", "off"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.staticTexts["EPIC AUDIO GAMES"].waitForExistence(timeout: 15)
            || app.descendants(matching: .any)["talking-circle"].waitForExistence(timeout: 15))
        return app
    }

    /// The audit, every issue but those [Exceptions] lets through; a screenshot is kept either way (and written to
    /// the folder in EPIC_SHOTS when the runner has it).
    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String) throws {
        let image = app.screenshot()
        let shot = XCTAttachment(screenshot: image)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["EPIC_SHOTS"] {
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("audit-\(name).png"))
        }
        var allowed: [String] = []
        let feed = app.scrollViews["feed"]
        let feedFrame = feed.exists ? feed.frame : nil
        let sheet = app.descendants(matching: .any)["store-sheet"]
        let sheetFrame = sheet.exists ? sheet.frame : nil
        try app.performAccessibilityAudit { issue in
            let e = issue.element
            print("AUDIT ISSUE \(name): \(issue.auditType.rawValue) \(issue.compactDescription) | "
                + "\(issue.detailedDescription) | "
                + "\(e.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)" } ?? "-")")
            guard let why = Exceptions.allows(issue, feed: feedFrame, sheet: sheetFrame) else { return false }
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
    /// [feed]: where the transcript shows on the screen, if a game is open; [sheet]: the store sheet, if it's up.
    static func allows(_ issue: XCUIAccessibilityAuditIssue, feed: CGRect?, sheet: CGRect?) -> String? {
        let frame = issue.element?.frame
        switch issue.auditType {
        case .contrast:
            // The transcript's lines scrolled out of its view: the audit measures what's drawn over them there (the
            // picture, the backdrop), not their ink on white.
            if let feed, let frame, !feed.insetBy(dx: -1, dy: -1).contains(frame) {
                return "a transcript line scrolled out of view"
            }
            // The outlined titles (gold letters ringed in ink): the audit reads the gold alone.
            if issue.element?.label.hasPrefix("MORE FROM ") == true { return "an outlined title" }
        case .dynamicType:
            // The header and the talking circle's status stop growing at the second accessibility size (Phase 8), as
            // do the end panel's and the store sheet's big outlined titles (a long word has no room to break).
            if let feed, let frame, frame.maxY <= feed.minY + 1 { return "capped at accessibility2" }
            let label = issue.element?.label ?? ""
            if ["CHAPTER COMPLETE!", "GAME OVER", "THE END"].contains(label) || label.hasPrefix("MORE FROM ") {
                return "capped at accessibility2"
            }
        case .textClipped:
            // The text box is one line: what's typed scrolls sideways in it (it grows with the text size).
            if issue.element?.identifier == "answer-field" { return "a one-line text box" }
            // The sheet is as tall as what's in it, up to the screen's height: with the largest text its rows go past
            // its foot, and it scrolls to them (seen at AccessibilityXXXL).
            if let sheet, let frame, frame.minY >= sheet.minY { return "the store sheet scrolls" }
        case .elementDetection:
            // The list's text showing around the sheet (iOS 26 floats it): VoiceOver rightly stays in the sheet.
            if sheet != nil && issue.element == nil { return "the list around the sheet" }
        default:
            break
        }
        return nil
    }
}
