import Foundation

/// How far back the dashboard chart reaches, counted from today.
enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    /// What the range button says.
    var shortLabel: String {
        switch self {
        case .sixMonths: return String(localized: "6M")
        case .oneYear: return String(localized: "1Y")
        case .all: return String(localized: "All")
        }
    }

    /// What VoiceOver says for the button.
    var spokenLabel: String {
        switch self {
        case .sixMonths: return String(localized: "6 months")
        case .oneYear: return String(localized: "1 year")
        case .all: return String(localized: "All time")
        }
    }

    private var months: Int? {
        switch self {
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }

    /// The earliest day inside the range, or `nil` when it reaches all the way
    /// back.
    func firstDay(today: CalendarDay, calendar: Calendar = .current) -> CalendarDay? {
        guard let months,
            let start = calendar.date(byAdding: .month, value: -months, to: today.date(in: calendar))
        else { return nil }
        return CalendarDay(date: start, calendar: calendar)
    }

    func includes(_ day: CalendarDay, today: CalendarDay, calendar: Calendar = .current) -> Bool {
        guard let first = firstDay(today: today, calendar: calendar) else { return true }
        return day >= first
    }

    /// The ranges worth a button for a chart with points on `days`. A shorter
    /// range needs two points to draw a line, and must leave some out, or it is
    /// just `.all` under another name. `.all` is always offered.
    static func offered(for days: [CalendarDay], today: CalendarDay, calendar: Calendar = .current) -> [Self] {
        allCases.filter { range in
            guard range != .all else { return true }
            let inside = days.count { range.includes($0, today: today, calendar: calendar) }
            return inside >= 2 && inside < days.count
        }
    }
}
