import XCTest

@testable import Tally

/// The App Store screenshots are only as good as this data: a gap in the rates
/// would put the "Some days can't be shown" banner on the first screenshot.
final class ScreenshotPortfolioTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 9, day: 29)

    private func ledgers(_ accounts: [ScreenshotPortfolio.Account]) -> [AccountLedger] {
        accounts.map { AccountLedger(type: $0.type, currencyCode: $0.currencyCode, entries: $0.entries) }
    }

    private func series(today: CalendarDay, languageCode: String = "en") -> [NetWorthPoint] {
        NetWorthCalculator.series(
            ledgers: ledgers(
                ScreenshotPortfolio.accounts(today: today, languageCode: languageCode, calendar: calendar)),
            rates: RateTable(quotes: ScreenshotPortfolio.quotes(today: today, calendar: calendar)),
            baseCurrency: "EUR"
        )
    }

    func testEveryPointHasTheRatesItNeeds() {
        let points = series(today: today)

        XCTAssertEqual(points.count, ScreenshotPortfolio.months)
        XCTAssertTrue(points.allSatisfy(\.hasCompleteRates))
    }

    /// Any base currency the viewer might pick in Settings still charts, not
    /// just the euro.
    func testEveryPointConvertsToEachCurrencyInThePortfolio() {
        let accounts = ScreenshotPortfolio.accounts(today: today, languageCode: "en", calendar: calendar)
        let rates = RateTable(quotes: ScreenshotPortfolio.quotes(today: today, calendar: calendar))

        for base in Set(accounts.map(\.currencyCode)) {
            let points = NetWorthCalculator.series(ledgers: ledgers(accounts), rates: rates, baseCurrency: base)
            XCTAssertTrue(points.allSatisfy(\.hasCompleteRates), "missing rates in \(base)")
        }
    }

    func testHistoryIsThreeYearsOfMonthEndsEndingLastMonth() {
        let days = ScreenshotPortfolio.monthEnds(before: today, calendar: calendar)

        XCTAssertEqual(days.first, CalendarDay(year: 2023, month: 9, day: 30))
        XCTAssertEqual(days.last, CalendarDay(year: 2026, month: 8, day: 31))
        XCTAssertTrue(days.contains(CalendarDay(year: 2024, month: 2, day: 29)))
        XCTAssertEqual(days, days.sorted())
    }

    func testMonthEndsCrossTheYearFromJanuary() {
        let days = ScreenshotPortfolio.monthEnds(before: CalendarDay(year: 2027, month: 1, day: 5), calendar: calendar)

        XCTAssertEqual(days.last, CalendarDay(year: 2026, month: 12, day: 31))
        XCTAssertEqual(days.first, CalendarDay(year: 2024, month: 1, day: 31))
    }

    func testEveryBalanceIsOneTheAppWouldAccept() {
        for account in ScreenshotPortfolio.accounts(today: today, languageCode: "en", calendar: calendar) {
            XCTAssertTrue(CurrencyCatalog.all.contains(account.currencyCode), account.currencyCode)
            for entry in account.entries {
                XCTAssertTrue(account.type.accepts(entry.amount), "\(account.name) on \(entry.day.isoString)")
                XCTAssertGreaterThanOrEqual(entry.day, RateStore.earliestDay)
                XCTAssertLessThan(entry.day, today)
            }
        }
    }

    /// The first screenshot is the total line: it should end well above where
    /// it started, and dip on the way.
    func testNetWorthRisesOverallWithADip() throws {
        let totals = series(today: today).compactMap(\.total)
        let first = try XCTUnwrap(totals.first)
        let last = try XCTUnwrap(totals.last)

        XCTAssertGreaterThan(last, first)
        XCTAssertTrue(zip(totals, totals.dropFirst()).contains { $1 < $0 })
    }

    func testTheAccountsSpanFourCurrenciesAndEveryType() {
        let accounts = ScreenshotPortfolio.accounts(today: today, languageCode: "en", calendar: calendar)

        XCTAssertEqual(Set(accounts.map(\.currencyCode)), ["EUR", "USD", "CHF", "GBP"])
        XCTAssertEqual(Set(accounts.map(\.type)), Set(AccountType.allCases))
    }

    func testGermanRenamesTheAccountsButChangesNoFigure() {
        let english = ScreenshotPortfolio.accounts(today: today, languageCode: "en", calendar: calendar)
        let german = ScreenshotPortfolio.accounts(today: today, languageCode: "de", calendar: calendar)

        XCTAssertEqual(german.map(\.name).first, "Girokonto")
        XCTAssertEqual(english.map(\.name).first, "Current account")
        for (inEnglish, inGerman) in zip(english, german) {
            XCTAssertEqual(inEnglish.entries.map(\.amount), inGerman.entries.map(\.amount))
            XCTAssertEqual(inEnglish.entries.map(\.day), inGerman.entries.map(\.day))
        }
    }

    func testTheLatestRatesAreFromTheLastWeekday() {
        // 2026-09-27 is a Sunday.
        let rates = RateTable(
            quotes: ScreenshotPortfolio.quotes(today: CalendarDay(year: 2026, month: 9, day: 27), calendar: calendar))

        XCTAssertEqual(rates.latestDay, CalendarDay(year: 2026, month: 9, day: 25))
    }
}
