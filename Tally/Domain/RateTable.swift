import Foundation

/// One ECB reference rate: how many units of `currencyCode` one euro bought on
/// `day`.
struct FXQuote: Hashable, Sendable {
    let day: CalendarDay
    let currencyCode: String
    let unitsPerEUR: Decimal

    init(day: CalendarDay, currencyCode: String, unitsPerEUR: Decimal) {
        self.day = day
        self.currencyCode = currencyCode.uppercased()
        self.unitsPerEUR = unitsPerEUR
    }
}

/// An immutable snapshot of every rate the app knows, indexed for lookup by
/// currency and day.
///
/// The ECB publishes on business days only, so a lookup for a Saturday, a
/// holiday, or any day a currency simply wasn't quoted resolves to the most
/// recent published day at or before it — never to a later one, and never to an
/// interpolation.
struct RateTable: Sendable {
    /// Per currency, quotes sorted oldest-first for binary search.
    private let quotesByCurrency: [String: [FXQuote]]

    init(quotes: [FXQuote]) {
        var grouped: [String: [FXQuote]] = [:]
        for quote in quotes where quote.currencyCode != CurrencyCatalog.base {
            grouped[quote.currencyCode, default: []].append(quote)
        }
        // A day may appear twice after merging a daily file into history; the
        // later-listed quote wins, matching the merge-by-date-and-currency rule.
        for (code, list) in grouped {
            var deduped: [CalendarDay: FXQuote] = [:]
            for quote in list { deduped[quote.day] = quote }
            grouped[code] = deduped.values.sorted { $0.day < $1.day }
        }
        self.quotesByCurrency = grouped
    }

    static let empty = RateTable(quotes: [])

    var isEmpty: Bool { quotesByCurrency.isEmpty }

    /// The newest day any rate was published for, for "Rates as of …".
    var latestDay: CalendarDay? {
        quotesByCurrency.values.compactMap { $0.last?.day }.max()
    }

    /// Units of `code` per euro on `day`, using the latest publication at or
    /// before it. `nil` means the app has no basis to convert and must say so.
    func unitsPerEUR(_ code: String, on day: CalendarDay) -> Decimal? {
        let code = code.uppercased()
        if code == CurrencyCatalog.base { return 1 }
        guard let quotes = quotesByCurrency[code] else { return nil }
        return Self.latestQuote(in: quotes, onOrBefore: day)?.unitsPerEUR
    }

    /// The ECB day a conversion on `day` actually resolved to, for display.
    func effectiveDay(_ code: String, on day: CalendarDay) -> CalendarDay? {
        let code = code.uppercased()
        if code == CurrencyCatalog.base { return day }
        guard let quotes = quotesByCurrency[code] else { return nil }
        return Self.latestQuote(in: quotes, onOrBefore: day)?.day
    }

    /// `value_B = amount_C / unitsPerEUR(C, D) × unitsPerEUR(B, D)`
    ///
    /// Routing through the euro is what lets the base currency change without
    /// re-fetching anything: the stored history is already euro-relative, so
    /// every past point re-prices with its own day's rates.
    func convert(_ amount: Decimal, from source: String, to target: String, on day: CalendarDay) -> Decimal? {
        let source = source.uppercased()
        let target = target.uppercased()
        if source == target { return amount }
        guard let sourceRate = unitsPerEUR(source, on: day),
            let targetRate = unitsPerEUR(target, on: day),
            sourceRate != 0
        else { return nil }
        return amount / sourceRate * targetRate
    }

    /// Binary search for the last quote at or before `day`.
    private static func latestQuote(in quotes: [FXQuote], onOrBefore day: CalendarDay) -> FXQuote? {
        var low = 0
        var high = quotes.count - 1
        var found: FXQuote?
        while low <= high {
            let mid = (low + high) / 2
            if quotes[mid].day <= day {
                found = quotes[mid]
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }
}
