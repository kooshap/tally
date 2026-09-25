import Foundation
import SwiftData

/// What `BalanceEntryEditor` edits, and the rules for saving it, kept out of
/// the view so they can be tested.
struct BalanceEntryForm {
    /// The one line of explanation under the fields, most important first.
    enum Notice: Equatable {
        case dateIsFixed
        case replacesThatDaysBalance
        case negativeNotAllowed
    }

    let account: Account
    /// `nil` adds a balance; otherwise edits this one in place.
    let entry: BalanceEntry?
    var amountText: String
    var date: Date

    private let locale: Locale

    init(account: Account, entry: BalanceEntry?, now: Date = .now, locale: Locale = .current) {
        self.account = account
        self.entry = entry
        self.locale = locale
        if let entry {
            amountText = MoneyFormatting.editableString(entry.amount, locale: locale)
            date = entry.day.date()
        } else {
            amountText = ""
            date = now
        }
    }

    var amount: Decimal? {
        MoneyFormatting.parse(amountText, code: account.currencyCode, locale: locale)
    }

    var day: CalendarDay { CalendarDay(date: date) }

    /// A new balance on a day that already has one replaces it.
    var wouldOverwrite: Bool {
        entry == nil && account.entries.contains { $0.dayNumber == day.rawValue }
    }

    var isNegativeAndDisallowed: Bool {
        amount.map { !account.type.accepts($0) } ?? false
    }

    var canSave: Bool {
        amount != nil && !isNegativeAndDisallowed
    }

    var notice: Notice? {
        if entry != nil { return .dateIsFixed }
        if wouldOverwrite { return .replacesThatDaysBalance }
        if isNegativeAndDisallowed { return .negativeNotAllowed }
        return nil
    }

    /// Writes the balance, or does nothing and returns nil if it can't be saved.
    @discardableResult
    func save(in context: ModelContext, now: Date = .now) -> BalanceEntry? {
        guard canSave, let amount else { return nil }
        guard let entry else {
            return BalanceStore.record(amount, on: day, for: account, in: context, now: now)
        }
        entry.amount = amount
        entry.updatedAt = now
        return entry
    }
}
