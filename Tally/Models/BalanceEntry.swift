import Foundation
import SwiftData

/// One hand-entered balance for one account on one day.
///
/// At most one per account per day: entering a balance again on the same day
/// overwrites it rather than adding a second point. `BalanceStore.record`
/// enforces that, since the rule spans a relationship and cannot be expressed
/// as a `#Unique` constraint.
@Model
final class BalanceEntry {
    var id: UUID = UUID()
    /// `yyyymmdd`.
    var dayNumber: Int = 0
    var amount: Decimal = Decimal.zero
    /// When the figure was last touched, for "edited" affordances. Not used in
    /// any calculation — the day is what the maths keys on.
    var updatedAt: Date = Date.now
    var account: Account?

    init(day: CalendarDay, amount: Decimal, updatedAt: Date = .now) {
        self.id = UUID()
        self.dayNumber = day.rawValue
        self.amount = amount
        self.updatedAt = updatedAt
    }

    var day: CalendarDay {
        get { CalendarDay(rawValue: dayNumber) ?? CalendarDay(year: 1970, month: 1, day: 1) }
        set { dayNumber = newValue.rawValue }
    }
}
