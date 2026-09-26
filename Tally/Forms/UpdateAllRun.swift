import Foundation
import SwiftData

/// What `UpdateAllView` steps through, and the rules for saving it, kept out
/// of the view so they can be tested.
struct UpdateAllRun {
    /// Fixed when the run starts, so `index` keeps pointing at the same account.
    let accounts: [Account]
    /// Every balance in the run is saved under this one date.
    var date: Date
    /// Keyed by account id: what will be written when the run is saved.
    var drafts: [UUID: String] = [:]
    private(set) var index = 0
    private(set) var skipped: Set<UUID> = []
    private(set) var isReviewing = false

    private let locale: Locale

    /// Pre-fills each field with the account's last known value, so an
    /// unchanged account is one tap.
    init(accounts: [Account], now: Date = .now, locale: Locale = .current) {
        self.accounts = accounts
        self.date = now
        self.locale = locale
        for account in accounts {
            guard let latest = account.latestEntry else { continue }
            drafts[account.id] = MoneyFormatting.editableString(latest.amount, locale: locale)
        }
    }

    var day: CalendarDay { CalendarDay(date: date) }

    var current: Account? {
        accounts.indices.contains(index) ? accounts[index] : nil
    }

    /// The date is chosen on the first account and held for the rest, so no
    /// run can straddle two days.
    var isDateFixed: Bool { index > 0 }

    var canGoBack: Bool { isReviewing || index > 0 }

    /// The text field's binding: `drafts[id, default: ""]` can't be one, as a
    /// key path can't capture the autoclosure behind `default:`.
    subscript(draftFor id: UUID) -> String {
        get { drafts[id] ?? "" }
        set { drafts[id] = newValue }
    }

    func amount(for account: Account) -> Decimal? {
        MoneyFormatting.parse(drafts[account.id] ?? "", code: account.currencyCode, locale: locale)
    }

    func isNegativeAndDisallowed(_ account: Account) -> Bool {
        amount(for: account).map { !account.type.accepts($0) } ?? false
    }

    /// Skipped, empty, unreadable, and refused amounts are all left out.
    func willSave(_ account: Account) -> Bool {
        guard !skipped.contains(account.id), let amount = amount(for: account) else { return false }
        return account.type.accepts(amount)
    }

    var accountsToSave: [Account] { accounts.filter(willSave) }
    var accountsLeftOut: [Account] { accounts.filter { !willSave($0) } }

    func draftText(for account: Account) -> String {
        guard let amount = amount(for: account) else { return "—" }
        return MoneyFormatting.string(amount, code: account.currencyCode, locale: locale)
    }

    /// Takes the current account's amount and moves on. Going back to a
    /// skipped account and choosing Next un-skips it, since that is what the
    /// amount on screen says will happen.
    mutating func next() {
        guard let account = current, !isNegativeAndDisallowed(account) else { return }
        skipped.remove(account.id)
        moveForward()
    }

    mutating func skip() {
        guard let account = current else { return }
        skipped.insert(account.id)
        moveForward()
    }

    /// From the review, back to the last account; otherwise to the previous one.
    mutating func back() {
        if isReviewing {
            isReviewing = false
        } else if index > 0 {
            index -= 1
        }
    }

    private mutating func moveForward() {
        if index + 1 < accounts.count {
            index += 1
        } else {
            isReviewing = true
        }
    }

    /// Records every account that will be saved under the run's one date.
    /// Saving again after a failed write is safe: `record` replaces the entry
    /// it wrote the first time rather than adding a second.
    @discardableResult
    func save(in context: ModelContext, now: Date = .now) -> [BalanceEntry] {
        accounts.compactMap { account in
            guard willSave(account), let amount = amount(for: account) else { return nil }
            return BalanceStore.record(amount, on: day, for: account, in: context, now: now)
        }
    }
}
