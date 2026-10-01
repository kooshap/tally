import XCTest

@testable import Tally

/// Reading and writing the backup file, without a store.
final class BackupTests: XCTestCase {
    private let allowed = CalendarDay(year: 2015, month: 1, day: 1)...CalendarDay(year: 2026, month: 10, day: 1)
    private let checkingID = UUID(uuidString: "6F1C2E8A-0000-4000-8000-0000000000A2")!
    private let header = "account_id,account_name,account_type,currency,notes,sort_order,archived_on,date,amount"

    private func read(_ lines: [String]) throws(BackupError) -> Backup {
        try Backup(data: Data(lines.joined(separator: "\r\n").utf8), allowedDays: allowed)
    }

    private func problems(_ lines: [String]) -> [BackupProblem] {
        do {
            _ = try read(lines)
            return []
        } catch {
            return error.problems
        }
    }

    private func row(
        id: String? = nil, name: String = "Checking", type: String = "bank", currency: String = "EUR",
        notes: String = "", sortOrder: String = "0", archivedOn: String = "", date: String = "2025-01-31",
        amount: String = "5728.50"
    ) -> String {
        CSV.encode([[id ?? checkingID.uuidString, name, type, currency, notes, sortOrder, archivedOn, date, amount]])
            .trimmingCharacters(in: .newlines)
    }

    // MARK: - Writing

    func testWritesOneRowPerBalanceUnderTheHeader() {
        let backup = Backup(accounts: [
            .init(
                id: checkingID, name: "Checking, main", type: .bank, currencyCode: "EUR", notes: "Joint",
                sortOrder: 0, archivedOn: nil,
                balances: [
                    .init(day: CalendarDay(year: 2025, month: 1, day: 31), amount: Decimal(string: "5728.5")!),
                    .init(day: CalendarDay(year: 2025, month: 2, day: 28), amount: -12),
                ])
        ])

        XCTAssertEqual(
            backup.csv,
            """
            \(header)\r
            \(checkingID.uuidString),"Checking, main",bank,EUR,Joint,0,,2025-01-31,5728.5\r
            \(checkingID.uuidString),"Checking, main",bank,EUR,Joint,0,,2025-02-28,-12\r

            """)
    }

    func testAnAccountWithNoBalancesStillGetsARow() {
        let backup = Backup(accounts: [
            .init(
                id: checkingID, name: "Old", type: .debt, currencyCode: "CHF", notes: nil, sortOrder: 3,
                archivedOn: CalendarDay(year: 2025, month: 6, day: 30), balances: [])
        ])

        XCTAssertTrue(backup.csv.hasSuffix("\(checkingID.uuidString),Old,debt,CHF,,3,2025-06-30,,\r\n"))
    }

    func testWhatIsWrittenReadsBackTheSame() throws {
        let csv = [
            header,
            row(name: "Checking \"main\"", notes: "line one\nline two", date: "2025-02-28", amount: "-0.01"),
            row(name: "Checking \"main\"", notes: "line one\nline two", date: "2025-01-31", amount: "123456789.123"),
            row(
                id: UUID().uuidString, name: "House", type: "realEstate", currency: "GBP", sortOrder: "1", date: "",
                amount: ""),
        ].joined(separator: "\r\n")

        let backup = try Backup(data: Data(csv.utf8), allowedDays: allowed)
        let again = try Backup(data: Data(backup.csv.utf8), allowedDays: allowed)

        XCTAssertEqual(again.csv, backup.csv)
        XCTAssertEqual(backup.accounts.first?.balances.map(\.amount), [Decimal(string: "123456789.123")!, -0.01])
    }

    // MARK: - Reading

    func testReadsAccountsAndSortsTheirBalances() throws {
        let backup = try read([
            header,
            row(date: "2025-02-28", amount: "6102.17"),
            row(date: "2025-01-31", amount: "5728.50"),
        ])

        let account = try XCTUnwrap(backup.accounts.first)
        XCTAssertEqual(backup.accounts.count, 1)
        XCTAssertEqual(account.id, checkingID)
        XCTAssertEqual(account.type, .bank)
        XCTAssertNil(account.notes)
        XCTAssertEqual(account.line, 2)
        XCTAssertEqual(account.balances.map(\.day.isoString), ["2025-01-31", "2025-02-28"])
        XCTAssertEqual(account.balances.map(\.amount), [Decimal(string: "5728.50")!, Decimal(string: "6102.17")!])
    }

    func testColumnsCanComeInAnyOrderAndUnknownOnesAreIgnored() throws {
        let backup = try read([
            "amount,date,later_column,archived_on,sort_order,notes,currency,account_type,account_name,account_id",
            "10,2025-01-31,whatever,,0,,usd,broker,Shares,\(checkingID.uuidString)",
        ])

        XCTAssertEqual(backup.accounts.first?.currencyCode, "USD")
        XCTAssertEqual(backup.accounts.first?.balances.first?.amount, 10)
    }

    func testAByteOrderMarkIsSkipped() throws {
        let data = Data("\u{FEFF}".utf8) + Data([header, row()].joined(separator: "\n").utf8)

        XCTAssertEqual(try Backup(data: data, allowedDays: allowed).accounts.count, 1)
    }

    func testAHeaderOnlyFileHasNoAccounts() throws {
        XCTAssertTrue(try read([header]).accounts.isEmpty)
    }

    func testAFileWithoutTheColumnsIsNotABackup() {
        XCTAssertEqual(problems(["date,amount", "2025-01-31,10"]), [.notABackup])
        XCTAssertEqual(problems([]), [.notABackup])
    }

    func testAFileThatIsNotUTF8IsNotABackup() {
        let data = header.data(using: .utf16)!

        XCTAssertThrowsError(try Backup(data: data, allowedDays: allowed)) { error in
            XCTAssertEqual(error as? BackupError, BackupError([.notABackup]))
        }
    }

    func testAFileOverTheLimitIsTooLarge() {
        let data = Data(count: Backup.maximumBytes + 1)

        XCTAssertThrowsError(try Backup(data: data, allowedDays: allowed)) { error in
            XCTAssertEqual(error as? BackupError, BackupError([.tooLarge]))
        }
    }

    func testEveryBadRowIsReportedByLine() {
        XCTAssertEqual(
            problems([
                header,
                row(id: "not-a-uuid"),
                row(id: UUID().uuidString, name: "  "),
                row(id: UUID().uuidString, type: "crypto"),
                row(id: UUID().uuidString, currency: "BTC"),
                row(id: UUID().uuidString, sortOrder: "first"),
                row(id: UUID().uuidString, archivedOn: "2025-02-30"),
                row(date: "31.01.2025"),
                row(date: "2014-12-31"),
                row(date: "2026-10-02"),
                row(amount: "5.728,50"),
                row(amount: "12abc"),
                row(date: "2025-03-31", amount: ""),
                "too,few,values",
            ]),
            [
                .invalidID(line: 2),
                .emptyName(line: 3),
                .unknownType(line: 4, "crypto"),
                .unsupportedCurrency(line: 5, "BTC"),
                .invalidSortOrder(line: 6, "first"),
                .invalidDate(line: 7, "2025-02-30"),
                .invalidDate(line: 8, "31.01.2025"),
                .dateOutOfRange(line: 9, "2014-12-31"),
                .dateOutOfRange(line: 10, "2026-10-02"),
                .invalidAmount(line: 11, "5.728,50"),
                .invalidAmount(line: 12, "12abc"),
                .dateWithoutAmount(line: 13),
                .wrongValueCount(line: 14),
            ])
    }

    func testOnlyABankAccountMayBeNegative() {
        XCTAssertEqual(problems([header, row(amount: "-1")]), [])
        XCTAssertEqual(problems([header, row(type: "debt", amount: "-1")]), [.negativeAmount(line: 2)])
    }

    func testTwoBalancesOnOneDayAreRefused() {
        XCTAssertEqual(
            problems([header, row(amount: "1"), row(amount: "2")]),
            [.duplicateDay(line: 3)])
    }

    func testAnAccountsRowsMustAgreeOnItsDetails() {
        XCTAssertEqual(
            problems([header, row(date: "2025-01-31"), row(name: "Renamed", date: "2025-02-28")]),
            [.detailsDiffer(line: 3, firstLine: 2)])
    }

    func testABadAccountIsReportedOnceNotOnEveryRow() {
        XCTAssertEqual(
            problems([header, row(currency: "XXX", date: "2025-01-31"), row(currency: "XXX", date: "2025-02-28")]),
            [.unsupportedCurrency(line: 2, "XXX")])
    }

    func testAnUnclosedQuoteNamesItsLine() {
        XCTAssertEqual(problems([header, row(), "\"open"]), [.unclosedQuote(line: 3)])
    }

    func testEveryProblemHasAMessage() {
        XCTAssertEqual(
            BackupProblem.detailsDiffer(line: 7, firstLine: 2).message,
            "Line 7: the account's details differ from line 2.")
        XCTAssertFalse(BackupProblem.notABackup.message.isEmpty)
    }
}
