import Foundation
import SwiftData

/// Writes that carry a rule the model layer alone cannot express.
enum BalanceStore {
    /// Records `amount` for `account` on `day`, replacing that day's entry if
    /// one already exists. This is the "at most one entry per account per day"
    /// rule: a second edit on the same day overwrites rather than adding a
    /// second graph point.
    @discardableResult
    static func record(
        _ amount: Decimal,
        on day: CalendarDay,
        for account: Account,
        in context: ModelContext,
        now: Date = .now
    ) -> BalanceEntry {
        if let existing = account.entries.first(where: { $0.dayNumber == day.rawValue }) {
            existing.amount = amount
            existing.updatedAt = now
            return existing
        }

        let entry = BalanceEntry(day: day, amount: amount, updatedAt: now)
        entry.account = account
        account.entries.append(entry)
        context.insert(entry)
        return entry
    }

    static func delete(_ entry: BalanceEntry, in context: ModelContext) {
        context.delete(entry)
    }

    /// §6: archiving writes a zero balance on the archive date, so the chart
    /// shows the account falling out of the total rather than the total
    /// silently stepping down with no point to explain it.
    static func archive(
        _ account: Account,
        on day: CalendarDay = .today(),
        in context: ModelContext,
        now: Date = .now
    ) {
        record(0, on: day, for: account, in: context, now: now)
        account.archivedOn = day
    }

    /// Undoes `archive`, removing the zero entry it wrote — but only if that
    /// day's entry is still zero, so a balance typed after archiving survives.
    static func unarchive(_ account: Account, in context: ModelContext) {
        guard let archivedOn = account.archivedOn else { return }
        if let entry = account.entries.first(where: { $0.dayNumber == archivedOn.rawValue }),
           entry.amount == 0 {
            context.delete(entry)
        }
        account.archivedOn = nil
    }

    /// Deleting takes the history with it — the confirmation in the UI says so.
    static func delete(_ account: Account, in context: ModelContext) {
        context.delete(account)
    }

    /// Keeps `sortOrder` dense and in list order after a drag.
    static func reorder(_ accounts: [Account]) {
        for (index, account) in accounts.enumerated() {
            account.sortOrder = index
        }
    }
}
