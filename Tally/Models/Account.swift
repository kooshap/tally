import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    /// Stored raw so an unknown value from a newer build degrades instead of crashing.
    var typeRawValue: String = AccountType.bank.rawValue
    var currencyCode: String = CurrencyCatalog.base
    var notes: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    /// `yyyymmdd`, or nil while active. See `CalendarDay` for why it isn't a `Date`.
    var archivedOnDayNumber: Int?

    @Relationship(deleteRule: .cascade, inverse: \BalanceEntry.account)
    var entries: [BalanceEntry] = []

    init(
        name: String,
        type: AccountType,
        currencyCode: String,
        notes: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.currencyCode = currencyCode.uppercased()
        self.notes = notes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRawValue) ?? .bank }
        set { typeRawValue = newValue.rawValue }
    }

    var archivedOn: CalendarDay? {
        get { archivedOnDayNumber.flatMap(CalendarDay.init(rawValue:)) }
        set { archivedOnDayNumber = newValue?.rawValue }
    }

    var isArchived: Bool { archivedOnDayNumber != nil }

    /// Oldest-first, which is the order the calculator and the history list want.
    var sortedEntries: [BalanceEntry] {
        entries.sorted { $0.dayNumber < $1.dayNumber }
    }

    var latestEntry: BalanceEntry? {
        entries.max { $0.dayNumber < $1.dayNumber }
    }

    /// The account's own currency, not converted.
    var currentAmount: Decimal {
        latestEntry?.amount ?? 0
    }

    /// The pure-value form the calculator works on.
    var ledger: AccountLedger {
        AccountLedger(
            id: id,
            name: name,
            type: type,
            currencyCode: currencyCode,
            archivedOn: archivedOn,
            entries: sortedEntries.map { (day: $0.day, amount: $0.amount) }
        )
    }
}
