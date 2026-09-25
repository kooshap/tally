import SwiftData
import XCTest

@testable import Tally

@MainActor
final class RateStoreTests: XCTestCase {
    private var container: ModelContainer!

    private let day = CalendarDay(year: 2026, month: 9, day: 22)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
    }

    /// `count` quotes over consecutive synthetic days, eight currencies a day.
    private func quotes(count: Int) -> [FXQuote] {
        let codes = ["USD", "GBP", "CHF", "JPY", "SEK", "NOK", "DKK", "PLN"]
        var quotes: [FXQuote] = []
        var index = 0
        while quotes.count < count {
            let day = CalendarDay(year: 2015 + index / 336, month: index / 28 % 12 + 1, day: index % 28 + 1)
            for code in codes where quotes.count < count {
                quotes.append(FXQuote(day: day, currencyCode: code, unitsPerEUR: 1))
            }
            index += 1
        }
        return quotes
    }

    // MARK: - Trimming to 2015

    func testRatesBeforeTheCutoffAreNotStored() throws {
        let context = ModelContext(container)
        try RateStore.merge(
            [
                FXQuote(
                    day: CalendarDay(year: 1999, month: 1, day: 4), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.1789")!),
                FXQuote(
                    day: CalendarDay(year: 2014, month: 12, day: 30), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.2209")!),
                FXQuote(
                    day: CalendarDay(year: 2014, month: 12, day: 31), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.2141")!),
                FXQuote(
                    day: CalendarDay(year: 2015, month: 1, day: 2), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.2043")!),
            ], into: context)

        let stored = try context.fetch(FetchDescriptor<FXRate>())
        XCTAssertEqual(
            stored.map(\.day).sorted(),
            [
                CalendarDay(year: 2014, month: 12, day: 31),
                CalendarDay(year: 2015, month: 1, day: 2),
            ])
    }

    /// New Year's Day has no ECB publication, so the cutoff day itself must
    /// still resolve to the last rate before it.
    func testABalanceOnTheCutoffDayStillHasARate() throws {
        let context = ModelContext(container)
        try RateStore.merge(
            [
                FXQuote(
                    day: CalendarDay(year: 2014, month: 12, day: 31), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.2141")!),
                FXQuote(
                    day: CalendarDay(year: 2015, month: 1, day: 2), currencyCode: "USD",
                    unitsPerEUR: Decimal(string: "1.2043")!),
            ], into: context)

        let table = try RateStore.loadTable(from: context)

        XCTAssertEqual(table.unitsPerEUR("USD", on: RateStore.earliestDay), Decimal(string: "1.2141"))
        XCTAssertNil(table.unitsPerEUR("USD", on: CalendarDay(year: 2014, month: 12, day: 30)))
    }

    func testAFileEntirelyAfterTheCutoffIsKeptWhole() {
        let quotes = quotes(count: 100)
        XCTAssertEqual(RateStore.trimmed(quotes), quotes)
    }

    func testIsEmptyUntilSomethingIsMerged() throws {
        let context = ModelContext(container)
        XCTAssertTrue(try RateStore.isEmpty(context))

        try RateStore.merge([FXQuote(day: day, currencyCode: "USD", unitsPerEUR: 1)], into: context)

        XCTAssertFalse(try RateStore.isEmpty(context))
    }

    func testMergeInBackgroundPersistsAndReturnsTheTable() async throws {
        let table = try await RateStore.mergeInBackground(
            [FXQuote(day: day, currencyCode: "usd", unitsPerEUR: Decimal(string: "1.1463")!)],
            into: container
        )

        XCTAssertEqual(table.unitsPerEUR("USD", on: day), Decimal(string: "1.1463"))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<FXRate>()), 1)
    }

    func testMergeInBackgroundUpdatesARestatedRate() async throws {
        _ = try await RateStore.mergeInBackground(
            [FXQuote(day: day, currencyCode: "USD", unitsPerEUR: 2)], into: container)
        let table = try await RateStore.mergeInBackground(
            [FXQuote(day: day, currencyCode: "USD", unitsPerEUR: 3)], into: container)

        XCTAssertEqual(table.unitsPerEUR("USD", on: day), 3)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<FXRate>()), 1)
    }

    func testLoadTableInBackgroundSeesWhatTheMainContextSaved() async throws {
        let context = ModelContext(container)
        try RateStore.merge(
            [FXQuote(day: day, currencyCode: "GBP", unitsPerEUR: Decimal(string: "0.8578")!)], into: context)
        try context.save()

        let table = try await RateStore.loadTableInBackground(from: container)

        XCTAssertEqual(table.unitsPerEUR("GBP", on: day), Decimal(string: "0.8578"))
    }

    /// The ECB history is ~93,000 rows from 2015 on. With a `#Unique`
    /// constraint on `FXRate`, Core Data's save went quadratic: 32,000 rows
    /// took 30 s, and the untrimmed file would have frozen first launch for
    /// over twenty minutes.
    /// Without it, this is about a second. The bound is loose on purpose.
    func testSavingALargeHistoryScalesLinearly() async throws {
        let start = Date.now

        let table = try await RateStore.mergeInBackground(quotes(count: 40_000), into: container)

        XCTAssertFalse(table.isEmpty)
        XCTAssertLessThan(Date.now.timeIntervalSince(start), 10)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<FXRate>()), 40_000)
    }
}
