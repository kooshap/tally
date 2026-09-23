import XCTest
@testable import Tally

final class RateTableTests: XCTestCase {
    private let friday = CalendarDay(year: 2026, month: 9, day: 18)
    private let saturday = CalendarDay(year: 2026, month: 9, day: 19)
    private let monday = CalendarDay(year: 2026, month: 9, day: 21)

    private func table() -> RateTable {
        RateTable(quotes: [
            FXQuote(day: friday, currencyCode: "USD", unitsPerEUR: Decimal(string: "1.1700")!),
            FXQuote(day: monday, currencyCode: "USD", unitsPerEUR: Decimal(string: "1.1500")!),
            FXQuote(day: friday, currencyCode: "CHF", unitsPerEUR: Decimal(string: "0.9400")!),
            FXQuote(day: monday, currencyCode: "CHF", unitsPerEUR: Decimal(string: "0.9300")!)
        ])
    }

    func testEuroIsThePivotAndIsAlwaysOne() {
        XCTAssertEqual(RateTable.empty.unitsPerEUR("EUR", on: monday), 1)
    }

    func testWeekendResolvesBackToTheLastPublishedDay() {
        XCTAssertEqual(table().unitsPerEUR("USD", on: saturday), Decimal(string: "1.1700"))
        XCTAssertEqual(table().effectiveDay("USD", on: saturday), friday)
    }

    func testNeverResolvesForwardToALaterRate() {
        let beforeAnyData = CalendarDay(year: 2026, month: 9, day: 17)
        XCTAssertNil(table().unitsPerEUR("USD", on: beforeAnyData))
    }

    func testUnknownCurrencyHasNoRate() {
        XCTAssertNil(table().unitsPerEUR("XYZ", on: monday))
    }

    func testLaterQuoteForTheSameDayWins() {
        let restated = RateTable(quotes: [
            FXQuote(day: monday, currencyCode: "USD", unitsPerEUR: 1),
            FXQuote(day: monday, currencyCode: "USD", unitsPerEUR: 2)
        ])
        XCTAssertEqual(restated.unitsPerEUR("USD", on: monday), 2)
    }

    func testLatestDayIsTheNewestAcrossAllCurrencies() {
        XCTAssertEqual(table().latestDay, monday)
    }

    // MARK: - Conversion

    func testConvertsThroughTheEuroPivot() {
        // 1000 CHF at 0.93/EUR is 1075.26… EUR, which at 1.15 USD/EUR is 1236.55…
        let converted = table().convert(1_000, from: "CHF", to: "USD", on: monday)
        let expected = Decimal(1_000) / Decimal(string: "0.9300")! * Decimal(string: "1.1500")!
        XCTAssertEqual(converted, expected)
    }

    func testConvertingToTheSameCurrencyIsIdentityEvenWithNoRates() {
        XCTAssertEqual(RateTable.empty.convert(500, from: "USD", to: "USD", on: monday), 500)
    }

    func testConversionFailsRatherThanGuessingWhenARateIsMissing() {
        XCTAssertNil(table().convert(100, from: "JPY", to: "EUR", on: monday))
    }

    /// §4: because rates are stored against the euro, switching the base
    /// currency re-prices history from the same stored numbers.
    func testChangingBaseCurrencyUsesTheSameHistoricalRates() {
        let table = table()
        let inUSD = table.convert(1_000, from: "CHF", to: "USD", on: friday)!
        let inEUR = table.convert(1_000, from: "CHF", to: "EUR", on: friday)!
        let backToUSD = table.convert(inEUR, from: "EUR", to: "USD", on: friday)!

        XCTAssertEqual(inUSD, backToUSD)
    }
}
