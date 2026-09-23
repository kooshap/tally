import XCTest
import SwiftData
@testable import Tally

@MainActor
final class BalanceStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let day = CalendarDay(year: 2026, month: 2, day: 5)
    private let laterDay = CalendarDay(year: 2026, month: 3, day: 5)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Account.self, BalanceEntry.self, FXRate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
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
        let a = makeAccount()
        let b = makeAccount()

        BalanceStore.record(1, on: day, for: a, in: context)
        BalanceStore.record(2, on: day, for: b, in: context)

        XCTAssertEqual(a.entries.count, 1)
        XCTAssertEqual(b.entries.count, 1)
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
