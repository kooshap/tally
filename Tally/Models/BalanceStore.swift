import Foundation
import SwiftData

/// Writes that carry a rule the model layer alone cannot express.
enum BalanceStore {
    /// §6: the dates a balance may be entered for. The past can be backfilled
    /// back to the first rate Tally keeps — an earlier balance could never be
    /// converted — and the future cannot be known.
    static func allowedDates(now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let earliest = calendar.startOfDay(for: RateStore.earliestDay.date(in: calendar))
        return earliest...max(earliest, now)
    }

    /// The same range as calendar days, for checking an imported balance.
    static func allowedDays(today: CalendarDay = .today()) -> ClosedRange<CalendarDay> {
        RateStore.earliestDay...max(RateStore.earliestDay, today)
    }

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
        // Detach first: a deleted object stays in the relationship array until
        // the next save, and would still count as the account's latest balance.
        entry.account?.entries.removeAll { $0 === entry }
        context.delete(entry)
    }

    /// Deletes the entries at `offsets` in `account.entriesNewestFirst`, which
    /// is the list the account screen shows and swipes delete from.
    static func deleteEntries(at offsets: IndexSet, newestFirstOf account: Account, in context: ModelContext) {
        let listed = account.entriesNewestFirst
        for index in offsets where listed.indices.contains(index) {
            delete(listed[index], in: context)
        }
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
            entry.amount == 0
        {
            delete(entry, in: context)
        }
        account.archivedOn = nil
    }

    /// Deleting takes the history with it — the confirmation in the UI says so.
    static func delete(_ account: Account, in context: ModelContext) {
        context.delete(account)
    }

    /// Keeps `sortOrder` dense and in list order after a drag in the active
    /// list: `active` is numbered in the order given, then the rest of
    /// `accounts` (the archived ones, which that list doesn't show) after it.
    /// Renumbering only the active ones would leave an archived account's
    /// `sortOrder` shared with an active one, and unarchiving it would put it
    /// in no particular place.
    static func reorder(_ active: [Account], among accounts: [Account]) {
        let rest = accounts.filter { account in !active.contains { $0 === account } }
        for (index, account) in (active + rest).enumerated() {
            account.sortOrder = index
        }
    }
}
