import XCTest

@testable import Tally

final class ChartRangeTests: XCTestCase {
    private let today = CalendarDay(year: 2026, month: 9, day: 29)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    func testRangesReachBackWholeMonthsFromToday() {
        XCTAssertEqual(ChartRange.sixMonths.firstDay(today: today, calendar: calendar), day(2026, 3, 29))
        XCTAssertEqual(ChartRange.oneYear.firstDay(today: today, calendar: calendar), day(2025, 9, 29))
        XCTAssertNil(ChartRange.all.firstDay(today: today, calendar: calendar))
    }

    func testTheFirstDayIsInsideTheRange() {
        XCTAssertTrue(ChartRange.oneYear.includes(day(2025, 9, 29), today: today, calendar: calendar))
        XCTAssertFalse(ChartRange.oneYear.includes(day(2025, 9, 28), today: today, calendar: calendar))
        XCTAssertTrue(ChartRange.all.includes(day(2015, 1, 1), today: today, calendar: calendar))
    }

    func testEveryRangeIsOfferedForALongMonthlyHistory() {
        let days = (1...36).map { offset in
            CalendarDay(date: calendar.date(byAdding: .month, value: -offset, to: today.date(in: calendar))!)
        }.reversed()

        XCTAssertEqual(ChartRange.offered(for: Array(days), today: today, calendar: calendar), ChartRange.allCases)
    }

    /// A range holding one point can't draw a line, and one holding every point
    /// is the same chart as All.
    func testRangesThatCantDrawOrChangeNothingAreLeftOut() {
        let days = [day(2025, 1, 1), day(2025, 11, 1), day(2026, 9, 1)]
        XCTAssertEqual(ChartRange.offered(for: days, today: today, calendar: calendar), [.oneYear, .all])

        let recent = [day(2026, 8, 1), day(2026, 9, 1)]
        XCTAssertEqual(ChartRange.offered(for: recent, today: today, calendar: calendar), [.all])

        XCTAssertEqual(ChartRange.offered(for: [], today: today, calendar: calendar), [.all])
    }
}
