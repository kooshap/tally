import Foundation

/// One account flattened into the facts the maths needs, so the calculator can
/// be exercised without a `ModelContainer`.
struct AccountLedger: Sendable {
    let id: UUID
    let name: String
    let type: AccountType
    let currencyCode: String
    let archivedOn: CalendarDay?
    /// Balances, oldest-first, at most one per day.
    let entries: [(day: CalendarDay, amount: Decimal)]

    init(
        id: UUID = UUID(),
        name: String = "",
        type: AccountType,
        currencyCode: String,
        archivedOn: CalendarDay? = nil,
        entries: [(day: CalendarDay, amount: Decimal)]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currencyCode = currencyCode
        self.archivedOn = archivedOn
        self.entries = entries.sorted { $0.day < $1.day }
    }

    /// §4: the amount of the latest entry dated on or before `day`
    /// (carry-forward); zero before the first entry, and zero once archived.
    func value(on day: CalendarDay) -> Decimal {
        if let archivedOn, archivedOn <= day { return 0 }
        var carried: Decimal = 0
        for entry in entries {
            if entry.day <= day { carried = entry.amount } else { break }
        }
        return carried
    }

    /// True once this account has anything to contribute on `day`.
    func isActive(on day: CalendarDay) -> Bool {
        if let archivedOn, archivedOn <= day { return false }
        return entries.first.map { $0.day <= day } ?? false
    }
}

/// Net worth on one day, in the base currency.
struct NetWorthPoint: Identifiable, Sendable {
    let day: CalendarDay
    /// `nil` when a rate was missing — the point is excluded from the chart
    /// rather than drawn at a guessed value.
    let total: Decimal?
    let totalsByType: [AccountType: Decimal]
    /// Currencies with no rate at or before this day.
    let missingCurrencies: [String]

    var id: Int { day.rawValue }
    var hasCompleteRates: Bool { total != nil }
}

enum NetWorthCalculator {
    /// §4: one point per calendar day on which any entry exists, archive days
    /// included. Each point is priced with the rates of its own date and is
    /// never re-priced with later ones.
    static func series(
        ledgers: [AccountLedger],
        rates: RateTable,
        baseCurrency: String
    ) -> [NetWorthPoint] {
        let days = Set(
            ledgers.flatMap { ledger in
                ledger.entries.map { $0.day } + (ledger.archivedOn.map { [$0] } ?? [])
            }
        ).sorted()

        return days.map { day in
            point(on: day, ledgers: ledgers, rates: rates, baseCurrency: baseCurrency)
        }
    }

    static func point(
        on day: CalendarDay,
        ledgers: [AccountLedger],
        rates: RateTable,
        baseCurrency: String
    ) -> NetWorthPoint {
        var totalsByType: [AccountType: Decimal] = [:]
        var running: Decimal = 0
        var missing: Set<String> = []

        for ledger in ledgers {
            let amount = ledger.value(on: day)
            // An account carried at zero contributes nothing, so a currency it
            // uses must not be reported missing on its account.
            guard amount != 0 else { continue }

            guard
                let converted = rates.convert(
                    amount,
                    from: ledger.currencyCode,
                    to: baseCurrency,
                    on: day
                )
            else {
                missing.insert(ledger.currencyCode.uppercased())
                continue
            }

            let signed = converted * ledger.type.sign
            running += signed
            totalsByType[ledger.type, default: 0] += signed
        }

        // A missing base-currency rate invalidates every conversion on the day.
        if rates.unitsPerEUR(baseCurrency, on: day) == nil {
            missing.insert(baseCurrency.uppercased())
        }

        return NetWorthPoint(
            day: day,
            total: missing.isEmpty ? running : nil,
            totalsByType: missing.isEmpty ? totalsByType : [:],
            missingCurrencies: missing.sorted()
        )
    }

    /// The headline figure and its movement since the previous point.
    static func headline(_ series: [NetWorthPoint]) -> (current: NetWorthPoint, change: Decimal?)? {
        guard let current = series.last else { return nil }
        let previous = series.dropLast().last
        guard let now = current.total, let before = previous?.total else {
            return (current, nil)
        }
        return (current, now - before)
    }
}
