import XCTest

/// Captures the App Store screenshots, in English and German, as attachments
/// on the test result. `Screenshots/capture` runs it and exports them.
///
/// Skipped unless `TALLY_SCREENSHOTS` is set, so the everyday test run doesn't
/// pay for it. It checks only enough to know each screen shows what it should.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    /// What the test taps by name, in each language. Account names come from
    /// `ScreenshotPortfolio`; the rest from the String Catalog. Tabs and
    /// segments are tapped by position instead.
    private struct Language {
        let code: String
        let locale: String
        let updateAll: String
        let cancel: String
        let aboutTally: String
        let firstAccount: String
        let usBrokerage: String
    }

    private static let english = Language(
        code: "en", locale: "en_US", updateAll: "Update all balances", cancel: "Cancel", aboutTally: "About Tally",
        firstAccount: "Current account", usBrokerage: "US brokerage")

    private static let german = Language(
        code: "de", locale: "de_DE", updateAll: "Alle Kontostände aktualisieren", cancel: "Abbrechen",
        aboutTally: "Über Tally",
        firstAccount: "Girokonto", usBrokerage: "US-Depot")

    private var app: XCUIApplication!

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TALLY_SCREENSHOTS"] != nil,
            "Screenshots are taken only by Screenshots/capture")
        continueAfterFailure = false
    }

    func testEnglish() {
        capture(in: Self.english)
    }

    func testGerman() {
        capture(in: Self.german)
    }

    private func capture(in language: Language) {
        app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingReset", "-uiTestingScreenshotPortfolio",
            "-AppleLanguages", "(\(language.code))", "-AppleLocale", language.locale,
        ]
        app.launch()
        let tabs = app.tabBars.firstMatch
        // Chart mode (Total, By type, Per account), then range (6M, 1Y, All).
        let modes = app.segmentedControls.element(boundBy: 0).buttons
        let ranges = app.segmentedControls.element(boundBy: 1).buttons

        // 1. The whole history as one line.
        let allTime = ranges.element(boundBy: 2)
        XCTAssertTrue(allTime.waitForExistence(timeout: 10))
        allTime.tap()
        snap("01-net-worth", language)

        // 2. Every account, with the foreign ones converted underneath.
        tabs.buttons.element(boundBy: 1).tap()
        let updateAll = app.buttons[language.updateAll]
        XCTAssertTrue(updateAll.waitForExistence(timeout: 5))
        snap("02-accounts", language)

        // 3. The monthly update, a couple of accounts in.
        updateAll.tap()
        let next = app.buttons["updateAll.nextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        XCTAssertTrue(app.textFields["updateAll.amountField"].waitForExistence(timeout: 5))
        snap("03-update-all", language)
        app.buttons[language.cancel].tap()
        XCTAssertTrue(updateAll.waitForExistence(timeout: 5))

        // 4. What the total is made of. The range stays on All from step 1.
        tabs.buttons.element(boundBy: 0).tap()
        let byType = modes.element(boundBy: 1)
        XCTAssertTrue(byType.waitForExistence(timeout: 5))
        byType.tap()
        snap("04-by-type", language)

        // 5. One foreign account, in its own currency.
        modes.element(boundBy: 2).tap()
        let accountMenu = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", language.firstAccount))
            .firstMatch
        XCTAssertTrue(accountMenu.waitForExistence(timeout: 5))
        accountMenu.tap()
        let usBrokerage = app.buttons[language.usBrokerage]
        XCTAssertTrue(usBrokerage.waitForExistence(timeout: 5))
        usBrokerage.tap()
        snap("05-per-account", language)

        // 6. The privacy statement.
        tabs.buttons.element(boundBy: 2).tap()
        let about = app.buttons[language.aboutTally]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 5))
        snap("06-privacy", language)
    }

    /// Lets transitions and chart animations finish, then keeps the whole
    /// screen, status bar included.
    private func snap(_ name: String, _ language: Language) {
        _ = XCTWaiter.wait(for: [expectation(description: "settle")], timeout: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(language.code)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
