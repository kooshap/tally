import Foundation
import SwiftData

/// A cached ECB reference rate. EUR is the pivot at exactly 1 and is never
/// stored.
///
/// One row per day and currency is enforced by `RateStore.merge`, not by a
/// `#Unique` constraint: Core Data validates uniqueness in quadratic time, and
/// the ~200,000-row untrimmed history took over twenty minutes to save with it.
@Model
final class FXRate {
    #Index<FXRate>([\.dayNumber], [\.currencyCode], [\.dayNumber, \.currencyCode])

    /// `yyyymmdd` of the ECB business day.
    var dayNumber: Int = 0
    var currencyCode: String = ""
    var unitsPerEUR: Decimal = Decimal.zero

    init(day: CalendarDay, currencyCode: String, unitsPerEUR: Decimal) {
        self.dayNumber = day.rawValue
        self.currencyCode = currencyCode.uppercased()
        self.unitsPerEUR = unitsPerEUR
    }

    var day: CalendarDay {
        CalendarDay(rawValue: dayNumber) ?? CalendarDay(year: 1999, month: 1, day: 1)
    }

    var quote: FXQuote {
        FXQuote(day: day, currencyCode: currencyCode, unitsPerEUR: unitsPerEUR)
    }
}
