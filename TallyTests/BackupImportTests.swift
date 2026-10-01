import SwiftData
import XCTest

@testable import Tally

/// Exporting the store and merging a backup into it.
@MainActor
final class BackupImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let january = CalendarDay(year: 2025, month: 1, day: 31)
    private let february = CalendarDay(year: 2025, month: 2, day: 28)
    private let march = CalendarDay(year: 2025, month: 3, day: 31)
    private let allowed = CalendarDay(year: 2015, month: 1, day: 1)...CalendarDay(year: 2026, month: 10, day: 1)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    @discardableResult
    private func makeAccount(
        _ name: String, type: AccountType = .bank, currency: String = "EUR", sortOrder: Int = 0,
        balances: [(CalendarDay, Decimal)] = []
    ) -> Account {
        let account = Account(name: name, type: type, currencyCode: currency, sortOrder: sortOrder)
        context.insert(account)
        for (day, amount) in balances {
            BalanceStore.record(amount, on: day, for: account, in: context)
        }
        return account
    }

    private func accounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func record(
        _ name: String, id: UUID = UUID(), type: AccountType = .bank, currency: String = "EUR", sortOrder: Int = 0,
        archivedOn: CalendarDay? = nil, balances: [(CalendarDay, Decimal)] = []
    ) -> Backup.AccountRecord {
        Backup.AccountRecord(
            id: id, name: name, type: type, currencyCode: currency, notes: nil, sortOrder: sortOrder,
            archivedOn: archivedOn, balances: balances.map { Backup.BalanceRecord(day: $0.0, amount: $0.1) }, line: 2)
    }

    private func amounts(_ account: Account) -> [Decimal] {
        account.sortedEntries.map(\.amount)
    }

    // MARK: - Moving to a new phone

    func testABackupRestoresIntoAnEmptyStore() throws {
        let checking = makeAccount("Checking", sortOrder: 0, balances: [(january, 100), (february, -5)])
        checking.notes = "Joint"
        let house = makeAccount(
            "House", type: .realEstate, currency: "GBP", sortOrder: 1, balances: [(january, 500_000)])
        BalanceStore.archive(house, on: march, in: context)
        makeAccount("Empty", type: .debt, currency: "CHF", sortOrder: 2)
        let csv = Backup(exporting: try accounts()).csv

        let newPhone = ModelContext(try TallyStore.makeContainer(inMemory: true))
        let backup = try Backup(data: Data(csv.utf8), allowedDays: allowed)
        let plan = try BackupImport(backup, into: [])
        plan.apply(in: newPhone)
        try newPhone.save()

        XCTAssertEqual(plan.newAccounts, 3)
        XCTAssertEqual(plan.newBalances, 4)
        XCTAssertEqual(plan.replacedBalances, 0)
        let restored = try newPhone.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(restored.map(\.name), ["Checking", "House", "Empty"])
        XCTAssertEqual(restored.map(\.id), try accounts().map(\.id))
        XCTAssertEqual(restored.map(\.type), [.bank, .realEstate, .debt])
        XCTAssertEqual(restored.map(\.currencyCode), ["EUR", "GBP", "CHF"])
        XCTAssertEqual(restored[0].notes, "Joint")
        XCTAssertEqual(restored[1].archivedOn, march)
        XCTAssertEqual(amounts(restored[0]), [100, -5])
        XCTAssertEqual(amounts(restored[1]), [500_000, 0])
        XCTAssertEqual(Backup(exporting: restored).csv, csv)
    }

    // MARK: - Merging

    func testImportingTheSameFileAgainChangesNothing() throws {
        makeAccount("Checking", balances: [(january, 100)])
        let backup = Backup(exporting: try accounts())

        let plan = try BackupImport(backup, into: try accounts())

        XCTAssertTrue(plan.changesNothing)
    }

    func testABalanceOnANewDayIsAddedAndOneOnTheSameDayReplaced() throws {
        let checking = makeAccount("Checking", balances: [(january, 100), (february, 200)])
        let backup = Backup(accounts: [
            record("Checking", id: checking.id, balances: [(january, 100), (february, 250), (march, 300)])
        ])

        let plan = try BackupImport(backup, into: try accounts())
        plan.apply(in: context)

        XCTAssertEqual(plan.newAccounts, 0)
        XCTAssertEqual(plan.newBalances, 1)
        XCTAssertEqual(plan.replacedBalances, 1)
        XCTAssertEqual(amounts(checking), [100, 250, 300])
    }

    func testNothingOnThePhoneIsDeleted() throws {
        let checking = makeAccount("Checking", balances: [(january, 100)])
        makeAccount("Savings", sortOrder: 1)
        let backup = Backup(accounts: [record("Checking", id: checking.id, balances: [(february, 200)])])

        try BackupImport(backup, into: try accounts()).apply(in: context)

        XCTAssertEqual(try accounts().map(\.name), ["Checking", "Savings"])
        XCTAssertEqual(amounts(checking), [100, 200])
    }

    func testAMatchedAccountKeepsItsDetailsOnThePhone() throws {
        let checking = makeAccount("Checking")
        let backup = Backup(accounts: [
            record("Renamed in the file", id: checking.id, sortOrder: 9, archivedOn: march)
        ])

        try BackupImport(backup, into: try accounts()).apply(in: context)

        XCTAssertEqual(checking.name, "Checking")
        XCTAssertEqual(checking.sortOrder, 0)
        XCTAssertNil(checking.archivedOn)
    }

    func testAnAccountWithoutAMatchingIDMatchesByNameTypeAndCurrency() throws {
        let checking = makeAccount("Checking", balances: [(january, 100)])
        let backup = Backup(accounts: [record("CHECKING", balances: [(february, 200)])])

        let plan = try BackupImport(backup, into: try accounts())
        plan.apply(in: context)

        XCTAssertEqual(plan.newAccounts, 0)
        XCTAssertEqual(try accounts().count, 1)
        XCTAssertEqual(amounts(checking), [100, 200])
    }

    func testANameMatchNeedsTheSameTypeAndCurrency() throws {
        makeAccount("Checking", currency: "EUR")

        let plan = try BackupImport(Backup(accounts: [record("Checking", currency: "USD")]), into: try accounts())

        XCTAssertEqual(plan.newAccounts, 1)
    }

    func testTwoAccountsWithTheNameLeaveNothingToMatchByName() throws {
        makeAccount("Checking")
        makeAccount("Checking", sortOrder: 1)

        let plan = try BackupImport(Backup(accounts: [record("Checking")]), into: try accounts())

        XCTAssertEqual(plan.newAccounts, 1)
    }

    func testAnAccountMatchedByIDIsNotAlsoTakenByName() throws {
        let checking = makeAccount("Checking")
        let backup = Backup(accounts: [
            record("Checking", balances: [(january, 1)]),
            record("Checking", id: checking.id, balances: [(january, 2)]),
        ])

        let plan = try BackupImport(backup, into: try accounts())
        plan.apply(in: context)

        XCTAssertEqual(plan.newAccounts, 1)
        XCTAssertEqual(amounts(checking), [2])
    }

    func testAMatchWithADifferentCurrencyOrTypeIsRefused() throws {
        let checking = makeAccount("Checking", currency: "EUR")
        let backup = Backup(accounts: [record("Checking", id: checking.id, currency: "USD")])

        XCTAssertThrowsError(try BackupImport(backup, into: try accounts())) { error in
            XCTAssertEqual(
                error as? BackupError, BackupError([.conflictsWithAccount(line: 2, name: "Checking")]))
        }
    }

    func testNewAccountsGoAfterTheExistingOnesInTheFilesOrder() throws {
        makeAccount("Existing", sortOrder: 4)
        let backup = Backup(accounts: [record("Second", sortOrder: 1), record("First", sortOrder: 0)])

        try BackupImport(backup, into: try accounts()).apply(in: context)

        XCTAssertEqual(try accounts().map(\.name), ["Existing", "First", "Second"])
        XCTAssertEqual(try accounts().map(\.sortOrder), [4, 5, 6])
    }

    func testTheSummaryCountsEachKindOfChange() throws {
        let checking = makeAccount("Checking", balances: [(january, 100)])
        let backup = Backup(accounts: [
            record("Checking", id: checking.id, balances: [(january, 150)]),
            record("Savings", balances: [(january, 1), (february, 2)]),
        ])

        let plan = try BackupImport(backup, into: try accounts())

        XCTAssertEqual(plan.summary, "Accounts to add: 1\nBalances to add: 2\nBalances to replace: 1")
    }

    func testTheFileIsNamedForTheDay() {
        XCTAssertEqual(Backup.fileName(on: march), "Tally-2025-03-31.csv")
    }
}
