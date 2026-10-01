import Foundation

/// The backup file (§6): every account and balance as a CSV, one row per
/// balance, in a form that reads the same whatever language the phone is in.
struct Backup {
    struct AccountRecord {
        var id: UUID
        var name: String
        var type: AccountType
        var currencyCode: String
        var notes: String?
        var sortOrder: Int
        var archivedOn: CalendarDay?
        /// Oldest first.
        var balances: [BalanceRecord]
        /// The first line the account is on, for problems found when merging.
        var line = 0
    }

    struct BalanceRecord {
        var day: CalendarDay
        var amount: Decimal
        var line = 0
    }

    enum Column: String, CaseIterable {
        case accountID = "account_id"
        case accountName = "account_name"
        case accountType = "account_type"
        case currency
        case notes
        case sortOrder = "sort_order"
        case archivedOn = "archived_on"
        case date
        case amount
    }

    /// Ten years of monthly balances for fifty accounts is about 1 MB.
    static let maximumBytes = 5_000_000

    var accounts: [AccountRecord]

    init(accounts: [AccountRecord]) {
        self.accounts = accounts
    }

    var csv: String {
        var rows = [Column.allCases.map(\.rawValue)]
        for account in accounts {
            let details = [
                account.id.uuidString,
                account.name,
                account.type.rawValue,
                account.currencyCode,
                account.notes ?? "",
                String(account.sortOrder),
                account.archivedOn?.isoString ?? "",
            ]
            if account.balances.isEmpty {
                rows.append(details + ["", ""])
            }
            for balance in account.balances {
                // `Decimal.description` always uses a dot and no grouping.
                rows.append(details + [balance.day.isoString, balance.amount.description])
            }
        }
        return CSV.encode(rows)
    }
}

// MARK: - Reading

/// Why a file can't be imported. Every problem in the file is listed, not
/// just the first, so it can be fixed in one go.
struct BackupError: Error, Equatable {
    var problems: [BackupProblem]

    init(_ problems: [BackupProblem]) {
        self.problems = problems
    }
}

enum BackupProblem: Equatable {
    case unreadableFile
    case tooLarge
    case notABackup
    case unclosedQuote(line: Int)
    case wrongValueCount(line: Int)
    case invalidID(line: Int)
    case emptyName(line: Int)
    case unknownType(line: Int, String)
    case unsupportedCurrency(line: Int, String)
    case invalidSortOrder(line: Int, String)
    case invalidDate(line: Int, String)
    case dateOutOfRange(line: Int, String)
    case invalidAmount(line: Int, String)
    case negativeAmount(line: Int)
    case dateWithoutAmount(line: Int)
    case duplicateDay(line: Int)
    case detailsDiffer(line: Int, firstLine: Int)
    /// The file and the phone disagree on an account's currency or type, so
    /// its balances would mean something else here.
    case conflictsWithAccount(line: Int, name: String)
}

extension Backup {
    /// Reads a backup file, checking every row. `allowedDays` is the range a
    /// balance may be entered for by hand; the file is held to the same.
    init(data: Data, allowedDays: ClosedRange<CalendarDay>) throws(BackupError) {
        guard data.count <= Self.maximumBytes else { throw BackupError([.tooLarge]) }
        guard var text = String(data: data, encoding: .utf8) else { throw BackupError([.notABackup]) }
        if text.unicodeScalars.first == "\u{FEFF}" {
            text.unicodeScalars.removeFirst()
        }

        let records: [CSV.Record]
        do {
            records = try CSV.decode(text)
        } catch {
            throw BackupError([.unclosedQuote(line: error.line)])
        }

        guard let header = records.first else { throw BackupError([.notABackup]) }
        var columns: [Column: Int] = [:]
        for (position, name) in header.fields.enumerated() {
            if let column = Column(rawValue: name), columns[column] == nil {
                columns[column] = position
            }
        }
        guard columns.count == Column.allCases.count else { throw BackupError([.notABackup]) }

        var reader = Reader(columns: columns, width: header.fields.count, allowedDays: allowedDays)
        for record in records.dropFirst() {
            reader.read(record)
        }
        guard reader.problems.isEmpty else { throw BackupError(reader.problems) }

        self.init(
            accounts: reader.accounts.map { account in
                var account = account
                account.balances.sort { $0.day < $1.day }
                return account
            })
    }

    /// Accumulates accounts and problems row by row.
    private struct Reader {
        let columns: [Column: Int]
        let width: Int
        let allowedDays: ClosedRange<CalendarDay>

        var accounts: [AccountRecord] = []
        var problems: [BackupProblem] = []
        /// Each account's position in `accounts`, and the details its first row
        /// gave, which every later row must repeat.
        private var seen: [UUID: (position: Int, details: [String])] = [:]
        /// Accounts whose details were wrong: reported once, and their
        /// balances skipped.
        private var rejected: Set<UUID> = []
        private var days: [UUID: Set<CalendarDay>] = [:]

        init(columns: [Column: Int], width: Int, allowedDays: ClosedRange<CalendarDay>) {
            self.columns = columns
            self.width = width
            self.allowedDays = allowedDays
        }

        private static let detailColumns: [Column] = [
            .accountName, .accountType, .currency, .notes, .sortOrder, .archivedOn,
        ]

        mutating func read(_ record: CSV.Record) {
            let line = record.line
            guard record.fields.count == width else {
                problems.append(.wrongValueCount(line: line))
                return
            }
            // Every column is present: `init(data:)` checked the header.
            let values = Dictionary(uniqueKeysWithValues: columns.map { ($0.key, record.fields[$0.value]) })
            func value(_ column: Column) -> String {
                values[column] ?? ""
            }

            guard let position = accountPosition(value: value, line: line),
                let balance = balance(
                    date: value(.date), amount: value(.amount), type: accounts[position].type, line: line)
            else { return }
            guard days[accounts[position].id, default: []].insert(balance.day).inserted else {
                problems.append(.duplicateDay(line: line))
                return
            }
            accounts[position].balances.append(balance)
        }

        /// Where the row's account is in `accounts`, added on its first row.
        /// Nil, after noting why, when the account is wrong.
        private mutating func accountPosition(value: (Column) -> String, line: Int) -> Int? {
            guard let id = UUID(uuidString: value(.accountID)) else {
                problems.append(.invalidID(line: line))
                return nil
            }
            guard !rejected.contains(id) else { return nil }

            let details = Self.detailColumns.map(value)
            if let first = seen[id] {
                guard first.details == details else {
                    problems.append(.detailsDiffer(line: line, firstLine: accounts[first.position].line))
                    return nil
                }
                return first.position
            }
            guard let account = account(id: id, value: value, line: line) else {
                rejected.insert(id)
                return nil
            }
            seen[id] = (accounts.count, details)
            accounts.append(account)
            return accounts.count - 1
        }

        /// The row's balance. Nil when it has none, or after noting what's
        /// wrong with it.
        private mutating func balance(date: String, amount: String, type: AccountType, line: Int) -> BalanceRecord? {
            switch (date.isEmpty, amount.isEmpty) {
            case (true, true):
                return nil
            case (false, false):
                break
            default:
                problems.append(.dateWithoutAmount(line: line))
                return nil
            }
            guard let day = day(date, line: line) else { return nil }
            guard let parsed = Self.amount(amount) else {
                problems.append(.invalidAmount(line: line, amount))
                return nil
            }
            guard type.accepts(parsed) else {
                problems.append(.negativeAmount(line: line))
                return nil
            }
            return BalanceRecord(day: day, amount: parsed, line: line)
        }

        /// The account a row describes, or nil after noting what's wrong with it.
        private mutating func account(id: UUID, value: (Column) -> String, line: Int) -> AccountRecord? {
            let count = problems.count

            let name = value(.accountName).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                problems.append(.emptyName(line: line))
            }
            let type = AccountType(rawValue: value(.accountType))
            if type == nil {
                problems.append(.unknownType(line: line, value(.accountType)))
            }
            let currency = value(.currency).uppercased()
            if !CurrencyCatalog.isSupported(currency) {
                problems.append(.unsupportedCurrency(line: line, value(.currency)))
            }
            let sortOrder = Int(value(.sortOrder))
            if sortOrder == nil {
                problems.append(.invalidSortOrder(line: line, value(.sortOrder)))
            }
            var archivedOn: CalendarDay?
            if !value(.archivedOn).isEmpty {
                archivedOn = day(value(.archivedOn), line: line)
            }

            guard problems.count == count, let type, let sortOrder else { return nil }
            let notes = value(.notes)
            return AccountRecord(
                id: id,
                name: name,
                type: type,
                currencyCode: currency,
                notes: notes.isEmpty ? nil : notes,
                sortOrder: sortOrder,
                archivedOn: archivedOn,
                balances: [],
                line: line
            )
        }

        private mutating func day(_ text: String, line: Int) -> CalendarDay? {
            guard let day = Self.day(text) else {
                problems.append(.invalidDate(line: line, text))
                return nil
            }
            guard allowedDays.contains(day) else {
                problems.append(.dateOutOfRange(line: line, text))
                return nil
            }
            return day
        }

        /// Strictly `yyyy-MM-dd`, and a day the calendar has.
        static func day(_ text: String) -> CalendarDay? {
            guard text.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil,
                let day = CalendarDay(isoString: text)
            else { return nil }
            let parts = DateComponents(year: day.year, month: day.month, day: day.day)
            return parts.isValidDate(in: Calendar(identifier: .gregorian)) ? day : nil
        }

        /// A dot for decimals and nothing else. `Decimal(string:)` alone would
        /// read "12abc" as 12.
        static func amount(_ text: String) -> Decimal? {
            guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil else { return nil }
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

// MARK: - Messages

extension BackupProblem {
    var message: String {
        switch self {
        case .unreadableFile:
            return String(localized: "Tally couldn't open this file.")
        case .tooLarge:
            return String(localized: "This file is too large to be a Tally backup.")
        case .notABackup:
            return String(localized: "This isn't a Tally backup file.")
        case .unclosedQuote(let line):
            return String(localized: "Line \(line, specifier: "%lld"): a quoted value is never closed.")
        case .wrongValueCount(let line):
            return String(localized: "Line \(line, specifier: "%lld"): the number of values doesn't match the header.")
        case .invalidID(let line):
            return String(localized: "Line \(line, specifier: "%lld"): the account ID isn't valid.")
        case .emptyName(let line):
            return String(localized: "Line \(line, specifier: "%lld"): the account name is empty.")
        case .unknownType(let line, let type):
            return String(localized: "Line \(line, specifier: "%lld"): “\(type)” isn't an account type.")
        case .unsupportedCurrency(let line, let code):
            return String(localized: "Line \(line, specifier: "%lld"): Tally doesn't offer the currency “\(code)”.")
        case .invalidSortOrder(let line, let text):
            return String(localized: "Line \(line, specifier: "%lld"): the sort order “\(text)” isn't a whole number.")
        case .invalidDate(let line, let text):
            return String(localized: "Line \(line, specifier: "%lld"): “\(text)” isn't a date in the form 2025-01-31.")
        case .dateOutOfRange(let line, let text):
            return String(localized: "Line \(line, specifier: "%lld"): \(text) is before 2015 or in the future.")
        case .invalidAmount(let line, let text):
            return String(localized: "Line \(line, specifier: "%lld"): “\(text)” isn't an amount in the form -1234.56.")
        case .negativeAmount(let line):
            return String(
                localized: "Line \(line, specifier: "%lld"): only a bank account can have a negative balance.")
        case .dateWithoutAmount(let line):
            return String(localized: "Line \(line, specifier: "%lld"): a balance needs both a date and an amount.")
        case .duplicateDay(let line):
            return String(localized: "Line \(line, specifier: "%lld"): the account already has a balance on this day.")
        case .detailsDiffer(let line, let firstLine):
            return String(
                localized:
                    "Line \(line, specifier: "%lld"): the account's details differ from line \(firstLine, specifier: "%lld")."
            )
        case .conflictsWithAccount(let line, let name):
            return String(
                localized:
                    "Line \(line, specifier: "%lld"): “\(name)” has a different currency or type on this iPhone.")
        }
    }
}
