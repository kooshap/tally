import Foundation

/// The made-up portfolio the App Store screenshots show: someone in the euro
/// area with a US brokerage account, a Swiss pension and UK savings, who has
/// updated Tally at the end of every month for three years.
///
/// Every figure comes from a fixed table or formula rather than a random
/// number, so each run, and each language, draws the same charts. Only the
/// dates move, so the history always ends last month.
enum ScreenshotPortfolio {
    struct Account {
        let name: String
        let type: AccountType
        let currencyCode: String
        /// Oldest-first.
        let entries: [(day: CalendarDay, amount: Decimal)]
    }

    /// How many month-ends of history there are.
    static let months = 36

    /// The accounts in list order, named in `languageCode` ("de" or anything
    /// else for English).
    static func accounts(
        today: CalendarDay,
        languageCode: String,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [Account] {
        let days = monthEnds(before: today, calendar: calendar)
        let german = languageCode.hasPrefix("de")

        func account(
            _ english: String,
            _ germanName: String,
            _ type: AccountType,
            _ currencyCode: String,
            updatedIn updates: [Int]? = nil,
            amount: (Int) -> Decimal
        ) -> Account {
            Account(
                name: german ? germanName : english,
                type: type,
                currencyCode: currencyCode,
                entries: (updates ?? Array(days.indices)).map { (day: days[$0], amount: amount($0)) }
            )
        }

        return [
            account("Current account", "Girokonto", .bank, "EUR") { month in
                // Salary in, rent and spending out: it moves around without a trend.
                let cents = 340_000 + current[month % 12] * 100 + month * 1_537 + (month * 4_373) % 100
                return Decimal(cents) / 100
            },
            account("UK savings", "Sparkonto UK", .bank, "GBP") { month in
                Decimal(9_500 + month * 175)
            },
            account("ETF portfolio", "ETF-Depot", .broker, "EUR") { month in
                invested(28_000 + month * 450, month: month)
            },
            account("US brokerage", "US-Depot", .broker, "USD") { month in
                invested(38_000 + month * 200, month: month)
            },
            account("Pillar 3a", "Säule 3a", .broker, "CHF") { month in
                invested(18_000 + month * 180, month: month, damped: true)
            },
            // Revalued once a year, as people do with a home.
            account("Apartment", "Wohnung", .realEstate, "EUR", updatedIn: [0, 12, 24]) { month in
                Decimal(380_000 + month / 12 * 12_500)
            },
            account("Mortgage", "Baufinanzierung", .debt, "EUR") { month in
                Decimal(298_400 - month * 1_040)
            },
        ]
    }

    /// Rates for every currency the accounts use, on every day they have a
    /// balance, so no point is left off the chart for want of one. One more
    /// set on the latest weekday, so Settings shows rates as of this week.
    static func quotes(
        today: CalendarDay,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [FXQuote] {
        let days = monthEnds(before: today, calendar: calendar) + [latestWeekday(onOrBefore: today, calendar: calendar)]
        return days.enumerated().flatMap { month, day in
            [
                FXQuote(day: day, currencyCode: "USD", unitsPerEUR: rate(10_850 + month * 9 + usd[month % 12])),
                FXQuote(day: day, currencyCode: "CHF", unitsPerEUR: rate(9_650 - month * 8 + chf[month % 12])),
                FXQuote(day: day, currencyCode: "GBP", unitsPerEUR: rate(8_580 - month * 3 + gbp[month % 12])),
            ]
        }
    }

    // MARK: - Dates

    /// The last day of each of the `months` months before `today`'s,
    /// oldest-first.
    static func monthEnds(before today: CalendarDay, calendar: Calendar) -> [CalendarDay] {
        let thisMonth = today.year * 12 + today.month - 1
        return (1...months).reversed().map { back in
            let year = (thisMonth - back) / 12
            let month = (thisMonth - back) % 12 + 1
            let first = CalendarDay(year: year, month: month, day: 1).date(in: calendar)
            let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            return CalendarDay(year: year, month: month, day: length)
        }
    }

    private static func latestWeekday(onOrBefore today: CalendarDay, calendar: Calendar) -> CalendarDay {
        var date = today.date(in: calendar)
        while calendar.isDateInWeekend(date), let previous = calendar.date(byAdding: .day, value: -1, to: date) {
            date = previous
        }
        return CalendarDay(date: date, calendar: calendar)
    }

    // MARK: - Figures

    /// What `contributed` is worth after `month` months of a market that
    /// climbs about 6% a year, with a sell-off a little past halfway.
    /// `damped` halves the swings, for a pension fund's cautious mix.
    private static func invested(_ contributed: Int, month: Int, damped: Bool = false) -> Decimal {
        let swing = market[month % 12] + (selloff[month] ?? 0)
        let perMille = 1_000 + month * 5 + (damped ? swing / 2 : swing)
        // To the nearest ten, as someone reading a brokerage app would type it.
        return Decimal(contributed * perMille / 10_000 * 10)
    }

    private static func rate(_ basisPoints: Int) -> Decimal {
        Decimal(basisPoints) / 10_000
    }

    private static let current = [0, 850, 1_920, 410, 2_630, 1_240, 3_080, 690, 1_530, 2_210, 330, 1_790]
    private static let market = [0, 12, -8, 20, 5, -15, 18, -5, 10, 25, -10, 8]
    private static let selloff = [19: -30, 20: -70, 21: -110, 22: -90, 23: -50, 24: -20]
    private static let usd = [0, 120, -80, 60, 210, -40, 150, 30, -110, 90, 180, -20]
    private static let chf = [0, -40, 30, -60, 20, -10, 50, -30, 10, -50, 40, 0]
    private static let gbp = [0, 30, -20, 40, -10, 20, -30, 10, 50, -40, 0, 20]
}
