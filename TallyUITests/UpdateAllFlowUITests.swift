import XCTest

/// §8: the one UI test — the monthly "update all" run, which is the flow the
/// whole app exists to make quick.
@MainActor
final class UpdateAllFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A fixed locale, so the amounts asserted below read the same on any
        // simulator.
        app.launchArguments = ["-uiTestingReset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testSteppingThroughEveryAccountAndSavingUnderOneDate() {
        app.tabBars.buttons["Accounts"].tap()

        let updateAll = app.buttons["Update all balances"]
        XCTAssertTrue(updateAll.waitForExistence(timeout: 5))
        updateAll.tap()

        // Account 1 of 2 — pre-filled with the seeded balance, then edited.
        let amountField = app.textFields["updateAll.amountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        XCTAssertEqual(amountField.value as? String, "4000")

        // Clear by deleting rather than through the edit menu, which doesn't
        // reliably appear on a long press. Tapping the trailing edge puts the
        // cursor after the pre-filled text.
        amountField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let prefilled = amountField.value as? String ?? ""
        amountField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prefilled.count))
        amountField.typeText("4500")
        XCTAssertEqual(amountField.value as? String, "4500")

        app.buttons["updateAll.nextButton"].tap()

        // Account 2 of 2 — left as it was.
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        app.buttons["updateAll.nextButton"].tap()

        let save = app.buttons["updateAll.saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Back on the list, the edited figure is the account's current balance.
        XCTAssertTrue(app.staticTexts["Current account"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '4,500'")).firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    func testSkippingAnAccountLeavesItOutOfTheRun() {
        app.tabBars.buttons["Accounts"].tap()
        app.buttons["Update all balances"].tap()

        XCTAssertTrue(app.buttons["updateAll.skipButton"].waitForExistence(timeout: 5))
        app.buttons["updateAll.skipButton"].tap()
        app.buttons["updateAll.nextButton"].tap()

        XCTAssertTrue(app.staticTexts["Skipped"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current account"].exists)
    }
}
