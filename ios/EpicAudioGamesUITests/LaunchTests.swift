// Launches the app and finds the game list (no Kotlin counterpart).

import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTheGames() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let game = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Noodle Rush")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 15), "no Noodle Rush on the game list")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Game list"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
