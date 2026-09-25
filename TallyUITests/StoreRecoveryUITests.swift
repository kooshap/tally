import XCTest

/// A store that won't open used to stop the app at launch. This launches the
/// real app against one and checks it stays up and says what happened.
@MainActor
final class StoreRecoveryUITests: XCTestCase {
    func testAStoreThatWontOpenShowsTheRecoveryScreenInsteadOfCrashing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingReset", "-uiTestingUnopenableStore", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Tally can't open your data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Technical details"].exists)

        app.buttons["Try again"].tap()

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.staticTexts["Tally can't open your data"].waitForExistence(timeout: 5))
    }
}
