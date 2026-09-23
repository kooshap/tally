import XCTest

/// §8: the one UI test — the monthly "update all" run, which is the flow the
/// whole app exists to make quick.
final class UpdateAllFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingReset"]
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

        amountField.tap()
        amountField.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        amountField.typeText("4500")

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
