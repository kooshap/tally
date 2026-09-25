import XCTest

@testable import Tally

final class NetWorthCalculatorTests: XCTestCase {
    private let jan = CalendarDay(year: 2026, month: 1, day: 5)
    private let feb = CalendarDay(year: 2026, month: 2, day: 5)
    private let mar = CalendarDay(year: 2026, month: 3, day: 5)

    /// Every currency at parity, so sign and carry-forward can be read without
    /// arithmetic in the way.
    private func flatRates(days: [CalendarDay] = []) -> RateTable {
        let all = days.isEmpty ? [jan, feb, mar] : days
        return RateTable(
            quotes: all.flatMap { day in
                ["USD", "CHF"].map { FXQuote(day: day, currencyCode: $0, unitsPerEUR: 1) }
            })
    }

    func testDebtIsSubtractedAndAssetsAdded() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 10_000)]),
                AccountLedger(type: .debt, currencyCode: "EUR", entries: [(jan, 4_000)]),
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].total, 6_000)
        XCTAssertEqual(series[0].totalsByType[.bank], 10_000)
        XCTAssertEqual(series[0].totalsByType[.debt], -4_000)
    }

    func testOnePointPerDayThatAnyAccountHasAnEntryOn() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 100), (mar, 300)]),
                AccountLedger(type: .broker, currencyCode: "EUR", entries: [(feb, 50)]),
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.map(\.day), [jan, feb, mar])
    }

    /// §4: an account not updated on day D is carried forward at its last
    /// known figure, not dropped to zero.
    func testUnupdatedAccountIsCarriedForward() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 1_000)]),
                AccountLedger(type: .broker, currencyCode: "EUR", entries: [(jan, 500), (feb, 700)]),
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        // On the February point the bank account still contributes its January 1,000.
        XCTAssertEqual(series.last?.total, 1_700)
    }

    func testAccountContributesNothingBeforeItsFirstEntry() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 1_000)]),
                AccountLedger(type: .broker, currencyCode: "EUR", entries: [(feb, 900)]),
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.first?.total, 1_000)
    }

    // MARK: - Archiving

    func testArchivedAccountCountsZeroFromItsArchiveDayOnward() {
        let ledger = AccountLedger(
            type: .bank,
            currencyCode: "EUR",
            archivedOn: feb,
            entries: [(jan, 1_000), (feb, 0)]
        )

        XCTAssertEqual(ledger.value(on: jan), 1_000)
        XCTAssertEqual(ledger.value(on: feb), 0)
        XCTAssertEqual(ledger.value(on: mar), 0)
    }

    func testArchiveDayProducesItsOwnPointEvenWithNoOtherActivity() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(
                    type: .bank,
                    currencyCode: "EUR",
                    archivedOn: feb,
                    entries: [(jan, 1_000)]
                )
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.map(\.day), [jan, feb])
        XCTAssertEqual(series.last?.total, 0)
    }

    func testArchivedAccountKeepsItsHistoryOnTheChart() {
        let series = NetWorthCalculator.series(
            ledgers: [
                AccountLedger(type: .bank, currencyCode: "EUR", archivedOn: feb, entries: [(jan, 1_000)])
            ],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.first?.total, 1_000, "the period before archiving must survive")
    }

    // MARK: - Currency

    func testConvertsEachAccountAtItsOwnDayRate() {
        let rates = RateTable(quotes: [
            FXQuote(day: jan, currencyCode: "USD", unitsPerEUR: 2),
            FXQuote(day: feb, currencyCode: "USD", unitsPerEUR: 4),
        ])
        let ledgers = [AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000), (feb, 1_000)])]

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: rates, baseCurrency: "EUR")

        // The same 1,000 USD is worth half as much once the euro doubles.
        XCTAssertEqual(series[0].total, 500)
        XCTAssertEqual(series[1].total, 250)
    }

    /// §4: a point is priced with its own date's rates and never re-priced
    /// with later ones.
    func testPastPointsAreNotRepricedByNewerRates() {
        let rates = RateTable(quotes: [
            FXQuote(day: jan, currencyCode: "USD", unitsPerEUR: 2),
            FXQuote(day: mar, currencyCode: "USD", unitsPerEUR: 10),
        ])
        let ledgers = [AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000)])]

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: rates, baseCurrency: "EUR")

        XCTAssertEqual(series[0].total, 500, "January stays at January's rate")
    }

    // MARK: - Missing rates

    func testPointWithNoRateIsMarkedMissingRatherThanEstimated() {
        let ledgers = [AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000)])]

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: .empty, baseCurrency: "EUR")

        XCTAssertNil(series[0].total)
        XCTAssertFalse(series[0].hasCompleteRates)
        XCTAssertEqual(series[0].missingCurrencies, ["USD"])
    }

    func testAMissingBaseCurrencyRateInvalidatesTheWholePoint() {
        let rates = RateTable(quotes: [FXQuote(day: jan, currencyCode: "USD", unitsPerEUR: 2)])
        let ledgers = [AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000)])]

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: rates, baseCurrency: "CHF")

        XCTAssertNil(series[0].total)
        XCTAssertTrue(series[0].missingCurrencies.contains("CHF"))
    }

    /// A zero-valued account contributes nothing, so its currency having no
    /// rate must not spoil an otherwise complete day.
    func testZeroBalanceInAnUnratedCurrencyDoesNotBreakTheDay() {
        let rates = RateTable(quotes: [FXQuote(day: jan, currencyCode: "USD", unitsPerEUR: 2)])
        let ledgers = [
            AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000)]),
            AccountLedger(type: .bank, currencyCode: "JPY", entries: [(jan, 0)]),
        ]

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: rates, baseCurrency: "EUR")

        XCTAssertEqual(series[0].total, 500)
        XCTAssertTrue(series[0].missingCurrencies.isEmpty)
    }

    func testMissingPointCarriesNoBreakdownToDrawWith() {
        let ledgers = [AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000)])]
        let series = NetWorthCalculator.series(ledgers: ledgers, rates: .empty, baseCurrency: "EUR")

        XCTAssertTrue(series[0].totalsByType.isEmpty)
    }

    // MARK: - Headline

    func testHeadlineReportsChangeSinceThePreviousPoint() {
        let series = NetWorthCalculator.series(
            ledgers: [AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 1_000), (feb, 1_250)])],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        let headline = NetWorthCalculator.headline(series)
        XCTAssertEqual(headline?.current.day, feb)
        XCTAssertEqual(headline?.change, 250)
    }

    func testHeadlineHasNoChangeOnTheFirstEverPoint() {
        let series = NetWorthCalculator.series(
            ledgers: [AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 1_000)])],
            rates: flatRates(),
            baseCurrency: "EUR"
        )

        XCTAssertNil(NetWorthCalculator.headline(series)?.change)
    }

    func testEmptyPortfolioHasNoHeadline() {
        XCTAssertNil(NetWorthCalculator.headline([]))
    }

    // MARK: - One account's line

    func testAnAccountsLineIsItsOwnBalancesInItsOwnCurrency() {
        let ledger = AccountLedger(type: .bank, currencyCode: "USD", entries: [(feb, 200), (jan, 100)])

        let line = ledger.history(using: .empty)

        XCTAssertEqual(line.map(\.day), [jan, feb])
        XCTAssertEqual(line.map(\.amount), [100, 200])
    }

    func testAnAccountsLineConvertsAtEachDaysOwnRate() {
        let rates = RateTable(quotes: [
            FXQuote(day: jan, currencyCode: "USD", unitsPerEUR: 2),
            FXQuote(day: feb, currencyCode: "USD", unitsPerEUR: 4),
        ])
        let ledger = AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000), (feb, 1_000)])

        let line = ledger.history(convertedTo: "EUR", using: rates)

        XCTAssertEqual(line.map(\.amount), [500, 250], "same dollars, a stronger euro")
    }

    func testConvertingAnAccountToItsOwnCurrencyNeedsNoRates() {
        let ledger = AccountLedger(type: .bank, currencyCode: "EUR", entries: [(jan, 1_000)])

        XCTAssertEqual(ledger.history(convertedTo: "EUR", using: .empty).map(\.amount), [1_000])
    }

    /// As on the net worth chart: a day with no rate is left out, never
    /// filled from another day's rate.
    func testADayWithNoRateIsLeftOffTheConvertedLine() {
        let rates = RateTable(quotes: [FXQuote(day: feb, currencyCode: "USD", unitsPerEUR: 2)])
        let ledger = AccountLedger(type: .bank, currencyCode: "USD", entries: [(jan, 1_000), (feb, 1_000)])

        let line = ledger.history(convertedTo: "EUR", using: rates)

        XCTAssertEqual(line.map(\.day), [feb])
    }

    // MARK: - Sign

    func testOnlyABankAccountAcceptsANegativeBalance() {
        XCTAssertTrue(AccountType.bank.accepts(-1))
        for type in [AccountType.broker, .realEstate, .debt] {
            XCTAssertFalse(type.accepts(-1), "\(type)")
            XCTAssertTrue(type.accepts(0), "\(type)")
            XCTAssertTrue(type.accepts(1), "\(type)")
        }
    }

    // MARK: - Precision

    func testMoneyDoesNotDriftTheWayBinaryFloatingPointWould() {
        let ledgers = (0..<10).map { _ in
            AccountLedger(
                id: UUID(),
                type: .bank,
                currencyCode: "EUR",
                entries: [(jan, Decimal(string: "0.1")!)]
            )
        }

        let series = NetWorthCalculator.series(ledgers: ledgers, rates: flatRates(), baseCurrency: "EUR")
        XCTAssertEqual(series[0].total, Decimal(string: "1.0"))
    }
}
