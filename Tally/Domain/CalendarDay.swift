import Foundation

/// A calendar day with no time and no time zone.
///
/// Balances and ECB rates are both "a date", never "a moment". Storing them as
/// `Date` would mean a balance entered on the 1st in Zurich could read as the
/// 31st after a flight to New York, and would make matching an entry to that
/// day's ECB rate depend on the reader's time zone. The stored form is a sortable
/// `yyyymmdd` integer, so comparison and equality are exact.
struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// `20260922` — sortable, and what gets persisted.
    var rawValue: Int { year * 10_000 + month * 100 + day }

    init?(rawValue: Int) {
        guard rawValue > 0 else { return nil }
        let year = rawValue / 10_000
        let month = (rawValue / 100) % 100
        let day = rawValue % 100
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `1999-01-04`, the form the ECB publishes.
    init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon local time, which keeps the day stable across DST transitions
    /// when the value is handed to a `DatePicker` or a date formatter.
    func date(in calendar: Calendar = .current) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    static func today(_ calendar: Calendar = .current, now: Date = .now) -> CalendarDay {
        CalendarDay(date: now, calendar: calendar)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
