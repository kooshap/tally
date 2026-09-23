import XCTest
@testable import Tally

final class ECBRatesParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "xml"),
            "fixture \(name).xml is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    /// Against the real eurofxref-daily.xml as published on 2026-09-22.
    func testParsesTheDailyFile() throws {
        let quotes = try ECBRatesParser.parse(fixture("eurofxref-daily"))

        XCTAssertEqual(quotes.count, 29)
        XCTAssertEqual(Set(quotes.map(\.day)), [CalendarDay(year: 2026, month: 9, day: 22)])

        let usd = try XCTUnwrap(quotes.first { $0.currencyCode == "USD" })
        XCTAssertEqual(usd.unitsPerEUR, Decimal(string: "1.1463"))
    }

    /// The daily file uses single-quoted attributes and the history file uses
    /// double quotes; one parser has to swallow both.
    func testParsesTheHistoryFileWithItsSeveralDays() throws {
        let quotes = try ECBRatesParser.parse(fixture("eurofxref-hist-sample"))
        let days = Set(quotes.map(\.day))

        XCTAssertEqual(days, [
            CalendarDay(year: 2026, month: 9, day: 18),
            CalendarDay(year: 2026, month: 9, day: 21),
            CalendarDay(year: 2026, month: 9, day: 22)
        ])
    }

    /// The gap between Friday the 18th and Monday the 21st is a real weekend in
    /// the real file — the table must read across it rather than report nothing.
    func testWeekendGapInRealDataResolvesBackward() throws {
        let table = RateTable(quotes: try ECBRatesParser.parse(fixture("eurofxref-hist-sample")))
        let saturday = CalendarDay(year: 2026, month: 9, day: 19)

        XCTAssertEqual(table.effectiveDay("USD", on: saturday), CalendarDay(year: 2026, month: 9, day: 18))
    }

    func testSkipsRetiredCurrenciesQuotedAsNotAvailable() throws {
        let quotes = try ECBRatesParser.parse(fixture("eurofxref-with-na"))

        XCTAssertEqual(Set(quotes.map(\.currencyCode)), ["USD", "CHF"])
        XCTAssertNil(RateTable(quotes: quotes).unitsPerEUR("HRK", on: CalendarDay(year: 2026, month: 9, day: 22)))
    }

    func testTruncatedFileThrowsRatherThanReturningHalfAnAnswer() throws {
        XCTAssertThrowsError(try ECBRatesParser.parse(fixture("eurofxref-malformed"))) { error in
            XCTAssertEqual(error as? ECBRatesError, .malformedXML)
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try ECBRatesParser.parse(Data()))
    }

    /// Rates are parsed with a fixed POSIX locale: "1.1463" is one and a bit,
    /// never eleven thousand, whatever the phone's region is set to.
    func testDecimalPointIsReadTheECBWayNotTheDeviceWay() throws {
        let quotes = try ECBRatesParser.parse(fixture("eurofxref-daily"))
        let usd = try XCTUnwrap(quotes.first { $0.currencyCode == "USD" })

        XCTAssertLessThan(usd.unitsPerEUR, 2)
    }
}
