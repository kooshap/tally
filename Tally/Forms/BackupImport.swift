import Foundation
import SwiftData

extension Backup {
    /// Every account, archived ones too, in list order, with its balances
    /// oldest first.
    init(exporting accounts: [Account]) {
        self.init(
            accounts: accounts.sorted { $0.sortOrder < $1.sortOrder }.map { account in
                AccountRecord(
                    id: account.id,
                    name: account.name,
                    type: account.type,
                    currencyCode: account.currencyCode,
                    notes: account.notes,
                    sortOrder: account.sortOrder,
                    archivedOn: account.archivedOn,
                    balances: account.sortedEntries.map { BalanceRecord(day: $0.day, amount: $0.amount) }
                )
            })
    }

    static func fileName(on day: CalendarDay = .today()) -> String {
        "Tally-\(day.isoString).csv"
    }

    /// Reads a file the user picked, which may be outside the app's sandbox
    /// or still in iCloud Drive.
    static func read(from url: URL, allowedDays: ClosedRange<CalendarDay>) throws(BackupError) -> Backup {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }

        var data: Data?
        var isTooLarge = false
        var coordinationError: NSError?
        // Coordinating the read downloads the file first if it's in iCloud Drive.
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            isTooLarge = size > maximumBytes
            if !isTooLarge {
                data = try? Data(contentsOf: url)
            }
        }
        if isTooLarge { throw BackupError([.tooLarge]) }
        guard let data, coordinationError == nil else { throw BackupError([.unreadableFile]) }
        return try Backup(data: data, allowedDays: allowedDays)
    }
}

/// What importing a backup will change, worked out in full before anything
/// is written so the user can confirm it (§6). Importing only adds: it adds
/// accounts and balances, replaces a balance on a day the file also has, and
/// leaves everything else as it is.
struct BackupImport {
    private(set) var newAccounts = 0
    private(set) var newBalances = 0
    private(set) var replacedBalances = 0

    private let backup: Backup
    private let existing: [Account]
    /// The account on the phone each file account merges into, by file ID.
    private var matches: [UUID: Account] = [:]

    init(_ backup: Backup, into existing: [Account]) throws(BackupError) {
        self.backup = backup
        self.existing = existing

        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // An account another file account matches by ID can't also be taken
        // by name.
        var claimed = Set(backup.accounts.compactMap { byID[$0.id]?.id })
        var problems: [BackupProblem] = []

        for record in backup.accounts {
            if let account = byID[record.id] {
                guard account.type == record.type, account.currencyCode == record.currencyCode else {
                    problems.append(.conflictsWithAccount(line: record.line, name: record.name))
                    continue
                }
                matches[record.id] = account
            } else {
                let candidates = existing.filter { account in
                    !claimed.contains(account.id)
                        && account.type == record.type
                        && account.currencyCode == record.currencyCode
                        && account.name.caseInsensitiveCompare(record.name) == .orderedSame
                }
                if candidates.count == 1, let account = candidates.first {
                    matches[record.id] = account
                    claimed.insert(account.id)
                }
            }
        }
        guard problems.isEmpty else { throw BackupError(problems) }

        for record in backup.accounts {
            guard let account = matches[record.id] else {
                newAccounts += 1
                newBalances += record.balances.count
                continue
            }
            let amounts = Dictionary(
                account.entries.map { ($0.dayNumber, $0.amount) }, uniquingKeysWith: { first, _ in first })
            for balance in record.balances {
                if let amount = amounts[balance.day.rawValue] {
                    if amount != balance.amount { replacedBalances += 1 }
                } else {
                    newBalances += 1
                }
            }
        }
    }

    var changesNothing: Bool {
        newAccounts == 0 && newBalances == 0 && replacedBalances == 0
    }

    /// The confirmation's message, one count per line.
    var summary: String {
        [
            String(localized: "Accounts to add: \(newAccounts, specifier: "%lld")"),
            String(localized: "Balances to add: \(newBalances, specifier: "%lld")"),
            String(localized: "Balances to replace: \(replacedBalances, specifier: "%lld")"),
        ].joined(separator: "\n")
    }

    /// Makes the changes in `context`, unsaved. New accounts go after the
    /// existing ones, in the file's order.
    func apply(in context: ModelContext, now: Date = .now) {
        var nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        // `sorted` is stable, so accounts sharing a sort order keep file order.
        for record in backup.accounts.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let account: Account
            if let match = matches[record.id] {
                account = match
            } else {
                account = Account(
                    name: record.name,
                    type: record.type,
                    currencyCode: record.currencyCode,
                    notes: record.notes,
                    sortOrder: nextSortOrder,
                    createdAt: now
                )
                account.id = record.id
                account.archivedOn = record.archivedOn
                context.insert(account)
                nextSortOrder += 1
            }

            for balance in record.balances {
                let current = account.entries.first { $0.dayNumber == balance.day.rawValue }
                if current?.amount != balance.amount {
                    BalanceStore.record(balance.amount, on: balance.day, for: account, in: context, now: now)
                }
            }
        }
    }
}
