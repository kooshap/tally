import Foundation
import SwiftData

/// What `AccountEditorView` edits, and the rules for saving it, kept out of the
/// view so they can be tested.
struct AccountForm {
    /// `nil` creates an account; otherwise edits this one in place.
    let account: Account?
    var name = ""
    var type: AccountType = .bank
    var currencyCode = ""
    var notes = ""
    /// Only offered when creating: recorded as today's balance.
    var openingBalance = ""

    private let locale: Locale

    init(editing account: Account?, locale: Locale = .current) {
        self.account = account
        self.locale = locale
        guard let account else { return }
        name = account.name
        type = account.type
        currencyCode = account.currencyCode
        notes = account.notes ?? ""
    }

    var isEditing: Bool { account != nil }

    /// A new account starts in the portfolio currency.
    mutating func useCurrencyIfUnset(_ code: String) {
        if currencyCode.isEmpty { currencyCode = code }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var openingAmount: Decimal? {
        guard !isEditing else { return nil }
        return MoneyFormatting.parse(openingBalance, code: currencyCode, locale: locale)
    }

    var isOpeningBalanceNegativeAndDisallowed: Bool {
        openingAmount.map { !type.accepts($0) } ?? false
    }

    var canSave: Bool {
        !trimmedName.isEmpty && !currencyCode.isEmpty && !isOpeningBalanceNegativeAndDisallowed
    }

    /// Applies the edit, or creates the account after `existing` in list order
    /// with any opening balance recorded on `today`. Returns nil and changes
    /// nothing if the form can't be saved.
    @discardableResult
    func save(after existing: [Account], in context: ModelContext, today: CalendarDay = .today()) -> Account? {
        guard canSave else { return nil }
        let notes = notes.isEmpty ? nil : notes

        if let account {
            account.name = trimmedName
            account.type = type
            account.currencyCode = currencyCode
            account.notes = notes
            return account
        }

        let new = Account(
            name: trimmedName,
            type: type,
            currencyCode: currencyCode,
            notes: notes,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(new)
        if let openingAmount {
            BalanceStore.record(openingAmount, on: today, for: new, in: context)
        }
        return new
    }
}
