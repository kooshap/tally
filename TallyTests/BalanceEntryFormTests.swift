import SwiftData
import XCTest

@testable import Tally

@MainActor
final class BalanceEntryFormTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let english = Locale(identifier: "en_US")
    private let day = CalendarDay(year: 2026, month: 2, day: 5)
    private let laterDay = CalendarDay(year: 2026, month: 3, day: 5)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func makeAccount(_ type: AccountType = .bank, currency: String = "EUR") -> Account {
        let account = Account(name: "Test", type: type, currencyCode: currency)
        context.insert(account)
        return account
    }

    private func newEntryForm(for account: Account, amount: String, on day: CalendarDay) -> BalanceEntryForm {
        var form = BalanceEntryForm(account: account, entry: nil, locale: english)
        form.amountText = amount
        form.date = day.date()
        return form
    }

    // MARK: - Adding

    func testANewBalanceStartsEmptyAndDatedNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let form = BalanceEntryForm(account: makeAccount(), entry: nil, now: now, locale: english)

        XCTAssertEqual(form.amountText, "")
        XCTAssertEqual(form.date, now)
        XCTAssertFalse(form.canSave, "nothing typed yet")
        XCTAssertNil(form.notice)
    }

    func testSavingANewBalanceRecordsItOnThePickedDay() throws {
        let account = makeAccount()

        let saved = try XCTUnwrap(newEntryForm(for: account, amount: "1,234.50", on: day).save(in: context))

        XCTAssertEqual(saved.day, day)
        XCTAssertEqual(saved.amount, Decimal(string: "1234.5"))
        XCTAssertEqual(account.entries.count, 1)
    }

    func testANewBalanceOnADayThatHasOneSaysItWillReplaceIt() {
        let account = makeAccount()
        BalanceStore.record(100, on: day, for: account, in: context)

        let form = newEntryForm(for: account, amount: "200", on: day)

        XCTAssertTrue(form.wouldOverwrite)
        XCTAssertEqual(form.notice, .replacesThatDaysBalance)
        XCTAssertTrue(form.canSave, "replacing is allowed, just announced")
    }

    func testReplacingKeepsOneEntryForTheDay() {
        let account = makeAccount()
        BalanceStore.record(100, on: day, for: account, in: context)

        newEntryForm(for: account, amount: "200", on: day).save(in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.currentAmount, 200)
    }

    func testANewBalanceOnAnEmptyDayWarnsOfNothing() {
        let account = makeAccount()
        BalanceStore.record(100, on: day, for: account, in: context)

        let form = newEntryForm(for: account, amount: "200", on: laterDay)

        XCTAssertFalse(form.wouldOverwrite)
        XCTAssertNil(form.notice)
    }

    func testUnreadableTextCannotBeSaved() {
        let account = makeAccount()
        let form = newEntryForm(for: account, amount: "lots", on: day)

        XCTAssertFalse(form.canSave)
        XCTAssertNil(form.save(in: context))
        XCTAssertTrue(account.entries.isEmpty)
    }

    func testAmountsAreReadInTheDevicesLocale() {
        var form = BalanceEntryForm(account: makeAccount(), entry: nil, locale: Locale(identifier: "de_DE"))
        form.amountText = "1.234,56"

        XCTAssertEqual(form.amount, Decimal(string: "1234.56"))
    }

    // MARK: - Negative balances

    func testABankAccountCanBeOverdrawn() {
        let form = newEntryForm(for: makeAccount(.bank), amount: "-50", on: day)

        XCTAssertTrue(form.canSave)
        XCTAssertNil(form.notice)
    }

    func testOtherAccountTypesRefuseANegativeBalance() {
        for type in [AccountType.broker, .realEstate, .debt] {
            let account = makeAccount(type)
            let form = newEntryForm(for: account, amount: "-50", on: day)

            XCTAssertFalse(form.canSave, "\(type)")
            XCTAssertEqual(form.notice, .negativeNotAllowed, "\(type)")
            XCTAssertNil(form.save(in: context), "\(type)")
            XCTAssertTrue(account.entries.isEmpty, "\(type)")
        }
    }

    // MARK: - Editing

    func testEditingStartsFromTheEntrysAmountAndDay() {
        let account = makeAccount()
        let entry = BalanceStore.record(Decimal(string: "1234.5")!, on: day, for: account, in: context)

        let form = BalanceEntryForm(account: account, entry: entry, locale: english)

        XCTAssertEqual(form.amountText, "1234.5")
        XCTAssertEqual(form.day, day)
        XCTAssertEqual(form.notice, .dateIsFixed)
        XCTAssertFalse(form.wouldOverwrite, "an entry does not replace itself")
    }

    func testEditingChangesTheEntryInPlace() {
        let account = makeAccount()
        let entry = BalanceStore.record(100, on: day, for: account, in: context, now: .distantPast)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var form = BalanceEntryForm(account: account, entry: entry, locale: english)
        form.amountText = "150"

        let saved = form.save(in: context, now: now)

        XCTAssertTrue(saved === entry)
        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(entry.amount, 150)
        XCTAssertEqual(entry.updatedAt, now)
        XCTAssertEqual(entry.day, day)
    }
}
