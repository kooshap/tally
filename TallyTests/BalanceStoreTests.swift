import SwiftData
import XCTest

@testable import Tally

@MainActor
final class BalanceStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let day = CalendarDay(year: 2026, month: 2, day: 5)
    private let laterDay = CalendarDay(year: 2026, month: 3, day: 5)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func makeAccount(type: AccountType = .bank, currency: String = "EUR") -> Account {
        let account = Account(name: "Test", type: type, currencyCode: currency)
        context.insert(account)
        return account
    }

    // MARK: - One entry per account per day

    func testSecondEntryOnTheSameDayOverwritesTheFirst() {
        let account = makeAccount()

        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.record(1_250, on: day, for: account, in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.currentAmount, 1_250)
    }

    func testOverwritingKeepsOneGraphPointForThatDay() {
        let account = makeAccount()

        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.record(1_250, on: day, for: account, in: context)

        XCTAssertEqual(account.ledger.entries.count, 1)
    }

    func testOverwritingTouchesUpdatedAt() {
        let account = makeAccount()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(3_600)

        BalanceStore.record(1_000, on: day, for: account, in: context, now: first)
        let entry = BalanceStore.record(1_250, on: day, for: account, in: context, now: second)

        XCTAssertEqual(entry.updatedAt, second)
    }

    func testDifferentDaysAreSeparateEntries() {
        let account = makeAccount()

        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.record(1_100, on: laterDay, for: account, in: context)

        XCTAssertEqual(account.entries.count, 2)
        XCTAssertEqual(account.currentAmount, 1_100)
    }

    func testTwoAccountsCanShareADay() {
        let first = makeAccount()
        let second = makeAccount()

        BalanceStore.record(1, on: day, for: first, in: context)
        BalanceStore.record(2, on: day, for: second, in: context)

        XCTAssertEqual(first.entries.count, 1)
        XCTAssertEqual(second.entries.count, 1)
    }

    // MARK: - Allowed dates

    func testBalancesCanBeBackfilledToTheFirstKeptRateAndNoFurther() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let range = BalanceStore.allowedDates(now: now)

        XCTAssertEqual(CalendarDay(date: range.lowerBound), RateStore.earliestDay)
        XCTAssertEqual(range.upperBound, now, "no future dates")
        XCTAssertFalse(range.contains(CalendarDay(year: 2014, month: 12, day: 31).date()))
    }

    /// The whole of 1 January counts, whatever the time of day the picker
    /// carries and whichever time zone the phone is in.
    func testTheFirstAllowedDayStartsAtMidnightInAnyTimeZone() throws {
        for identifier in ["Pacific/Kiritimati", "Europe/Zurich", "Pacific/Pago_Pago"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))

            let lowerBound = BalanceStore.allowedDates(calendar: calendar).lowerBound

            XCTAssertEqual(CalendarDay(date: lowerBound, calendar: calendar), RateStore.earliestDay, identifier)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: lowerBound), DateComponents(hour: 0, minute: 0),
                identifier)
        }
    }

    // MARK: - Archiving

    func testArchivingWritesAZeroOnTheArchiveDay() {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)

        BalanceStore.archive(account, on: laterDay, in: context)

        XCTAssertEqual(account.archivedOn, laterDay)
        XCTAssertEqual(account.currentAmount, 0)
        XCTAssertEqual(account.entries.count, 2, "the pre-archive history stays")
    }

    func testUnarchivingRemovesTheZeroItWrote() {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.archive(account, on: laterDay, in: context)

        BalanceStore.unarchive(account, in: context)

        XCTAssertNil(account.archivedOn)
        XCTAssertEqual(account.currentAmount, 1_000)
    }

    /// A balance typed after archiving is real data and must survive an undo.
    func testUnarchivingKeepsANonZeroBalanceTypedOnTheArchiveDay() {
        let account = makeAccount()
        BalanceStore.archive(account, on: laterDay, in: context)
        BalanceStore.record(42, on: laterDay, for: account, in: context)

        BalanceStore.unarchive(account, in: context)

        XCTAssertNil(account.archivedOn)
        XCTAssertEqual(account.currentAmount, 42)
    }

    /// The zero must leave the account at once, not at the next save, or the
    /// list keeps showing a balance of 0 after the account is restored.
    func testUnarchivingRestoresTheBalanceBeforeAnySave() throws {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.archive(account, on: laterDay, in: context)
        try context.save()

        BalanceStore.unarchive(account, in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.latestEntry?.day, day)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BalanceEntry>()), 1)
    }

    func testUnarchivingAnActiveAccountChangesNothing() {
        let account = makeAccount()
        BalanceStore.record(0, on: day, for: account, in: context)

        BalanceStore.unarchive(account, in: context)

        XCTAssertEqual(account.entries.count, 1, "a real zero balance is not the archive marker")
    }

    func testArchivedAccountStillContributesItsPastToTheSeries() {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)
        BalanceStore.archive(account, on: laterDay, in: context)

        let rates = RateTable(quotes: [])
        let series = NetWorthCalculator.series(
            ledgers: [account.ledger],
            rates: rates,
            baseCurrency: "EUR"
        )

        XCTAssertEqual(series.map(\.day), [day, laterDay])
        XCTAssertEqual(series.first?.total, 1_000)
        XCTAssertEqual(series.last?.total, 0)
    }

    // MARK: - Deleting and ordering

    func testDeletingAnEntryFallsBackToThePreviousBalance() {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)
        let later = BalanceStore.record(1_100, on: laterDay, for: account, in: context)

        BalanceStore.delete(later, in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.currentAmount, 1_000)
    }

    func testDeletingAnAccountTakesItsEntriesWithIt() throws {
        let account = makeAccount()
        BalanceStore.record(1_000, on: day, for: account, in: context)
        try context.save()

        BalanceStore.delete(account, in: context)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<BalanceEntry>()).isEmpty)
    }

    func testReorderMakesSortOrderMatchListOrder() {
        let first = makeAccount()
        let second = makeAccount()
        let third = makeAccount()

        BalanceStore.reorder([third, first, second])

        XCTAssertEqual(third.sortOrder, 0)
        XCTAssertEqual(first.sortOrder, 1)
        XCTAssertEqual(second.sortOrder, 2)
    }

    // MARK: - Model

    func testAnUnknownTypeFromANewerBuildDegradesToBank() {
        let account = makeAccount(type: .broker)
        account.typeRawValue = "crypto"

        XCTAssertEqual(account.type, .bank)
    }

    func testCurrencyCodesAreStoredUppercased() {
        XCTAssertEqual(makeAccount(currency: "chf").currencyCode, "CHF")
    }

    func testAnEntryCanBeMovedToAnotherDay() {
        let account = makeAccount()
        let entry = BalanceStore.record(1_000, on: day, for: account, in: context)

        entry.day = laterDay

        XCTAssertEqual(entry.dayNumber, laterDay.rawValue)
        XCTAssertEqual(account.ledger.entries.first?.day, laterDay)
    }

    // MARK: - Rate merging

    func testMergingRatesUpdatesRatherThanDuplicating() throws {
        let quote = FXQuote(day: day, currencyCode: "USD", unitsPerEUR: 2)
        try RateStore.merge([quote], into: context)
        try RateStore.merge([FXQuote(day: day, currencyCode: "USD", unitsPerEUR: 3)], into: context)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<FXRate>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.unitsPerEUR, 3)
    }

    func testEuroIsNeverStoredBecauseItIsThePivot() throws {
        try RateStore.merge([FXQuote(day: day, currencyCode: "EUR", unitsPerEUR: 1)], into: context)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<FXRate>()).isEmpty)
    }
}
