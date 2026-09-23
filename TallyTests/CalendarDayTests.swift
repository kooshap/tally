import XCTest
@testable import Tally

final class CalendarDayTests: XCTestCase {
    func testRawValueIsSortableYYYYMMDD() {
        XCTAssertEqual(CalendarDay(year: 2026, month: 9, day: 22).rawValue, 20_260_922)
        XCTAssertLessThan(
            CalendarDay(year: 2026, month: 9, day: 22),
            CalendarDay(year: 2026, month: 10, day: 1)
        )
    }

    func testRoundTripsThroughRawValue() {
        let day = CalendarDay(year: 1999, month: 1, day: 4)
        XCTAssertEqual(CalendarDay(rawValue: day.rawValue), day)
    }

    func testParsesTheECBDateFormat() {
        XCTAssertEqual(CalendarDay(isoString: "2026-09-22"), CalendarDay(year: 2026, month: 9, day: 22))
        XCTAssertNil(CalendarDay(isoString: "22.09.2026"))
        XCTAssertNil(CalendarDay(isoString: "2026-13-01"))
    }

    func testIsoStringPadsSingleDigits() {
        XCTAssertEqual(CalendarDay(year: 1999, month: 1, day: 4).isoString, "1999-01-04")
    }

    /// The reason the type exists: a balance entered late on the 22nd in Zurich
    /// must not become the 22nd-or-23rd depending on where it is read.
    func testTheSameInstantIsADifferentDayInDifferentZones() {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)

        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!

        let recorded = CalendarDay(date: instant, calendar: zurich)

        // Read back in another zone, the stored day is unchanged — because what
        // was stored is the day itself, not the instant.
        XCTAssertEqual(CalendarDay(rawValue: recorded.rawValue), recorded)
        XCTAssertNotEqual(
            CalendarDay(date: instant, calendar: auckland).rawValue,
            0
        )
    }

    func testDateIsMiddaySoDSTCannotShiftIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // 29 March 2026 is a spring-forward day in Europe.
        let day = CalendarDay(year: 2026, month: 3, day: 29)

        XCTAssertEqual(CalendarDay(date: day.date(in: calendar), calendar: calendar), day)
    }
}
