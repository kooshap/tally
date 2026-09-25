import SwiftData
import XCTest

@testable import Tally

@MainActor
final class AccountFormTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let english = Locale(identifier: "en_US")
    private let today = CalendarDay(year: 2026, month: 9, day: 25)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func newAccountForm(
        name: String = "Savings",
        type: AccountType = .bank,
        currency: String = "EUR",
        openingBalance: String = ""
    ) -> AccountForm {
        var form = AccountForm(editing: nil, locale: english)
        form.name = name
        form.type = type
        form.currencyCode = currency
        form.openingBalance = openingBalance
        return form
    }

    private func allAccounts() throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    // MARK: - Creating

    func testANewAccountStartsInThePortfolioCurrency() {
        var form = AccountForm(editing: nil, locale: english)

        form.useCurrencyIfUnset("CHF")

        XCTAssertEqual(form.currencyCode, "CHF")
        XCTAssertFalse(form.isEditing)
    }

    func testANameIsRequiredAndSpacesDoNotCount() {
        XCTAssertFalse(newAccountForm(name: "").canSave)
        XCTAssertFalse(newAccountForm(name: "   \n").canSave)
        XCTAssertTrue(newAccountForm(name: "Savings").canSave)
    }

    func testSavingCreatesTheAccountWithATrimmedName() throws {
        var form = newAccountForm(name: "  Savings  ", type: .broker, currency: "USD")
        form.notes = "Index funds"

        let account = try XCTUnwrap(form.save(after: [], in: context, today: today))

        XCTAssertEqual(account.name, "Savings")
        XCTAssertEqual(account.type, .broker)
        XCTAssertEqual(account.currencyCode, "USD")
        XCTAssertEqual(account.notes, "Index funds")
        XCTAssertEqual(try allAccounts().count, 1)
    }

    func testEmptyNotesAreStoredAsNone() throws {
        let account = try XCTUnwrap(newAccountForm().save(after: [], in: context, today: today))

        XCTAssertNil(account.notes)
    }

    /// Archived accounts keep their place too, so a new one never lands in
    /// the middle when one is unarchived.
    func testANewAccountGoesAfterEveryExistingOne() throws {
        let first = try XCTUnwrap(newAccountForm(name: "A").save(after: [], in: context, today: today))
        first.sortOrder = 7
        BalanceStore.archive(first, on: today, in: context)

        let second = try XCTUnwrap(newAccountForm(name: "B").save(after: [first], in: context, today: today))

        XCTAssertEqual(second.sortOrder, 8)
    }

    func testTheFirstAccountIsFirstInTheList() throws {
        let account = try XCTUnwrap(newAccountForm().save(after: [], in: context, today: today))

        XCTAssertEqual(account.sortOrder, 0)
    }

    // MARK: - Opening balance

    func testAnOpeningBalanceIsRecordedAsTodaysBalance() throws {
        let form = newAccountForm(openingBalance: "2,500.75")

        let account = try XCTUnwrap(form.save(after: [], in: context, today: today))

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.latestEntry?.day, today)
        XCTAssertEqual(account.currentAmount, Decimal(string: "2500.75"))
    }

    func testNoOpeningBalanceMeansNoEntry() throws {
        let account = try XCTUnwrap(newAccountForm().save(after: [], in: context, today: today))

        XCTAssertTrue(account.entries.isEmpty)
    }

    /// A debt opened at -300,000 would be subtracted as a negative, adding
    /// 300,000 to net worth instead of taking it away.
    func testADebtCannotOpenWithANegativeBalance() throws {
        let form = newAccountForm(type: .debt, openingBalance: "-300000")

        XCTAssertTrue(form.isOpeningBalanceNegativeAndDisallowed)
        XCTAssertFalse(form.canSave)
        XCTAssertNil(form.save(after: [], in: context, today: today))
        XCTAssertTrue(try allAccounts().isEmpty)
    }

    func testABankAccountCanOpenOverdrawn() throws {
        let form = newAccountForm(type: .bank, openingBalance: "-50")

        XCTAssertTrue(form.canSave)
        let account = try XCTUnwrap(form.save(after: [], in: context, today: today))
        XCTAssertEqual(account.currentAmount, -50)
    }

    // MARK: - Editing

    func testEditingStartsFromTheAccountsFields() {
        let account = Account(name: "Mortgage", type: .debt, currencyCode: "CHF", notes: "Fixed until 2030")
        context.insert(account)

        let form = AccountForm(editing: account, locale: english)

        XCTAssertTrue(form.isEditing)
        XCTAssertEqual(form.name, "Mortgage")
        XCTAssertEqual(form.type, .debt)
        XCTAssertEqual(form.currencyCode, "CHF")
        XCTAssertEqual(form.notes, "Fixed until 2030")
    }

    func testEditingChangesTheAccountInPlaceAndAddsNoBalance() throws {
        let account = Account(name: "Old", type: .bank, currencyCode: "EUR", notes: "gone soon", sortOrder: 3)
        context.insert(account)
        var form = AccountForm(editing: account, locale: english)
        form.name = " New "
        form.type = .broker
        form.notes = ""
        form.openingBalance = "999"

        let saved = form.save(after: [account], in: context, today: today)

        XCTAssertIdentical(saved, account)
        XCTAssertEqual(account.name, "New")
        XCTAssertEqual(account.type, .broker)
        XCTAssertNil(account.notes)
        XCTAssertEqual(account.sortOrder, 3, "editing keeps the account's place")
        XCTAssertTrue(account.entries.isEmpty, "an opening balance only applies to a new account")
        XCTAssertEqual(try allAccounts().count, 1)
    }

    // MARK: - Locking currency and type

    func testANewAccountCanPickAnyCurrencyAndType() {
        XCTAssertFalse(newAccountForm().isCurrencyAndTypeLocked)
    }

    func testAnAccountWithNoBalancesCanStillChangeCurrencyAndType() throws {
        let account = Account(name: "Savings", type: .bank, currencyCode: "EUR")
        context.insert(account)
        var form = AccountForm(editing: account, locale: english)
        form.type = .broker
        form.currencyCode = "USD"

        XCTAssertFalse(form.isCurrencyAndTypeLocked)
        form.save(after: [account], in: context, today: today)

        XCTAssertEqual(account.type, .broker)
        XCTAssertEqual(account.currencyCode, "USD")
    }

    /// 250,000 recorded in EUR would otherwise read as 250,000 CHF, and a bank
    /// balance turned debt would flip from adding to subtracting.
    func testOnceAnAccountHasBalancesItsCurrencyAndTypeStay() throws {
        let account = Account(name: "Flat", type: .realEstate, currencyCode: "EUR")
        context.insert(account)
        BalanceStore.record(250_000, on: today, for: account, in: context)
        var form = AccountForm(editing: account, locale: english)
        form.name = "Apartment"
        form.type = .debt
        form.currencyCode = "CHF"

        XCTAssertTrue(form.isCurrencyAndTypeLocked)
        XCTAssertTrue(form.canSave, "the name and notes can still be edited")
        form.save(after: [account], in: context, today: today)

        XCTAssertEqual(account.name, "Apartment")
        XCTAssertEqual(account.type, .realEstate)
        XCTAssertEqual(account.currencyCode, "EUR")
    }
}
