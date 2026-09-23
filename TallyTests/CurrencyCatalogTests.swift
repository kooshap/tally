import XCTest

@testable import Tally

final class CurrencyCatalogTests: XCTestCase {
    func testOffersTheECBCurrenciesPlusEuroInOrder() {
        XCTAssertEqual(CurrencyCatalog.all.count, 30)
        XCTAssertTrue(CurrencyCatalog.all.contains("EUR"))
        XCTAssertEqual(CurrencyCatalog.all, CurrencyCatalog.all.sorted())
    }

    func testSupportIgnoresCase() {
        XCTAssertTrue(CurrencyCatalog.isSupported("chf"))
        XCTAssertTrue(CurrencyCatalog.isSupported("EUR"))
    }

    /// §4 forbids guessing a rate, so a currency the ECB does not publish is
    /// never offered — including retired ones that only appear in history.
    func testRejectsCurrenciesTheECBDoesNotPublish() {
        XCTAssertFalse(CurrencyCatalog.isSupported("ARS"))
        XCTAssertFalse(CurrencyCatalog.isSupported("HRK"))
    }

    func testDeviceDefaultUsesTheLocaleCurrencyWhenPublished() {
        XCTAssertEqual(CurrencyCatalog.deviceDefault(locale: Locale(identifier: "en_US")), "USD")
        XCTAssertEqual(CurrencyCatalog.deviceDefault(locale: Locale(identifier: "de_CH")), "CHF")
    }

    func testDeviceDefaultFallsBackToEuro() {
        XCTAssertEqual(CurrencyCatalog.deviceDefault(locale: Locale(identifier: "es_AR")), "EUR")
    }

    func testDisplayNameIsLocalizedAndCarriesTheCode() {
        XCTAssertEqual(CurrencyCatalog.displayName("USD", locale: Locale(identifier: "en_US")), "US Dollar (USD)")
        XCTAssertEqual(
            CurrencyCatalog.displayName("CHF", locale: Locale(identifier: "de_DE")), "Schweizer Franken (CHF)")
    }

    func testDisplayNameFallsBackToTheBareCode() {
        XCTAssertEqual(CurrencyCatalog.displayName("XYZ", locale: Locale(identifier: "en_US")), "XYZ")
    }
}
