import XCTest

@testable import Tally

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "tally.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testSetupIsIncompleteUntilACurrencyIsChosen() {
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedSetup)
    }

    /// §3: chosen once at first launch, and remembered from then on.
    func testCompletingSetupKeepsTheChosenCurrencyAcrossLaunches() {
        AppSettings(defaults: defaults).completeSetup(baseCurrency: "CHF")

        let nextLaunch = AppSettings(defaults: defaults)

        XCTAssertTrue(nextLaunch.hasCompletedSetup)
        XCTAssertEqual(nextLaunch.baseCurrency, "CHF")
    }
}
