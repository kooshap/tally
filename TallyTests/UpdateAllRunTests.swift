import SwiftData
import XCTest

@testable import Tally

@MainActor
final class UpdateAllRunTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let english = Locale(identifier: "en_US")
    private let day = CalendarDay(year: 2026, month: 2, day: 5)
    private let runDay = CalendarDay(year: 2026, month: 3, day: 5)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func makeAccount(_ name: String, _ type: AccountType = .bank, currency: String = "EUR") -> Account {
        let account = Account(name: name, type: type, currencyCode: currency)
        context.insert(account)
        return account
    }

    /// A run started on `runDay` unless told otherwise.
    private func makeRun(_ accounts: [Account], startingOn start: CalendarDay? = nil) -> UpdateAllRun {
        UpdateAllRun(accounts: accounts, now: (start ?? runDay).date(), locale: english)
    }

    // MARK: - Starting

    func testEachFieldStartsFromTheAccountsLatestBalance() {
        let savings = makeAccount("Savings")
        BalanceStore.record(100, on: day, for: savings, in: context)
        BalanceStore.record(Decimal(string: "1234.5")!, on: runDay, for: savings, in: context)
        let fresh = makeAccount("Fresh")

        let run = makeRun([savings, fresh])

        XCTAssertEqual(run.drafts[savings.id], "1,234.5")
        XCTAssertNil(run.drafts[fresh.id], "an account with no balance starts empty")
        XCTAssertEqual(run.day, runDay)
        XCTAssertIdentical(run.current, savings)
        XCTAssertFalse(run.isDateFixed)
        XCTAssertFalse(run.canGoBack)
    }

    func testPrefillIsWrittenInTheDevicesLocale() {
        let account = makeAccount("Girokonto")
        BalanceStore.record(Decimal(string: "1234.5")!, on: day, for: account, in: context)

        let run = UpdateAllRun(accounts: [account], locale: Locale(identifier: "de_DE"))

        XCTAssertEqual(run.drafts[account.id], "1.234,5")
        XCTAssertEqual(run.amount(for: account), Decimal(string: "1234.5"), "reads back as the same amount")
    }

    // MARK: - Stepping

    func testNextAndBackStepThroughTheAccountsThenTheReview() {
        let first = makeAccount("First")
        let second = makeAccount("Second")
        var run = makeRun([first, second])

        run.next()
        XCTAssertIdentical(run.current, second)
        XCTAssertTrue(run.isDateFixed, "the date is chosen on the first account")
        XCTAssertTrue(run.canGoBack)

        run.next()
        XCTAssertTrue(run.isReviewing)

        run.back()
        XCTAssertFalse(run.isReviewing)
        XCTAssertIdentical(run.current, second, "back from the review returns to the last account")

        run.back()
        XCTAssertIdentical(run.current, first)
        XCTAssertFalse(run.isDateFixed)

        run.back()
        XCTAssertIdentical(run.current, first, "there is nothing before the first account")
    }

    func testASkippedAccountIsLeftOut() {
        let skipped = makeAccount("Skipped")
        let kept = makeAccount("Kept")
        BalanceStore.record(100, on: day, for: skipped, in: context)
        BalanceStore.record(200, on: day, for: kept, in: context)
        var run = makeRun([skipped, kept])

        run.skip()
        XCTAssertIdentical(run.current, kept)
        run.next()

        XCTAssertTrue(run.isReviewing)
        XCTAssertFalse(run.willSave(skipped))
        XCTAssertEqual(run.accountsToSave.map(\.name), ["Kept"])
        XCTAssertEqual(run.accountsLeftOut.map(\.name), ["Skipped"])

        run.save(in: context)

        XCTAssertEqual(skipped.entries.count, 1, "nothing was written to the skipped account")
        XCTAssertNil(skipped.entries.first { $0.day == runDay })
    }

    func testGoingBackToASkippedAccountAndChoosingNextSavesIt() {
        let account = makeAccount("Savings")
        let other = makeAccount("Other")
        var run = makeRun([account, other])
        run.drafts[account.id] = "100"

        run.skip()
        run.back()
        run.next()

        XCTAssertTrue(run.willSave(account))
    }

    // MARK: - Amounts

    func testABankAccountCanBeOverdrawn() {
        let account = makeAccount("Current", .bank)
        var run = makeRun([account])
        run.drafts[account.id] = "-50"

        XCTAssertFalse(run.isNegativeAndDisallowed(account))
        XCTAssertTrue(run.willSave(account))
    }

    func testOtherAccountTypesRefuseANegativeBalance() {
        for type in [AccountType.broker, .realEstate, .debt] {
            let account = makeAccount("\(type)", type)
            var run = makeRun([account])
            run.drafts[account.id] = "-50"

            XCTAssertTrue(run.isNegativeAndDisallowed(account), "\(type)")
            XCTAssertFalse(run.willSave(account), "\(type)")

            run.next()
            XCTAssertFalse(run.isReviewing, "Next doesn't move past a refused amount: \(type)")

            XCTAssertTrue(run.save(in: context).isEmpty, "\(type)")
            XCTAssertTrue(account.entries.isEmpty, "\(type)")
        }
    }

    func testEmptyOrUnreadableDraftsAreNotSaved() {
        let empty = makeAccount("Empty")
        let unreadable = makeAccount("Unreadable")
        var run = makeRun([empty, unreadable])
        run.drafts[unreadable.id] = "lots"

        XCTAssertFalse(run.willSave(empty))
        XCTAssertFalse(run.willSave(unreadable))
        XCTAssertFalse(run.isNegativeAndDisallowed(unreadable), "unreadable is not the same as refused")
        XCTAssertEqual(run.draftText(for: unreadable), "—")
        XCTAssertEqual(run.accountsLeftOut.map(\.name), ["Empty", "Unreadable"])

        XCTAssertTrue(run.save(in: context).isEmpty)
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertTrue(unreadable.entries.isEmpty)
    }

    func testTheReviewShowsEachAmountInItsAccountsCurrency() {
        let account = makeAccount("Konto", currency: "CHF")
        var run = makeRun([account])
        run.drafts[account.id] = "1,234.5"

        XCTAssertEqual(
            run.draftText(for: account),
            MoneyFormatting.string(Decimal(string: "1234.5")!, code: "CHF", locale: english)
        )
    }

    // MARK: - Saving

    func testEverySavedBalanceLandsOnTheOneChosenDay() {
        let savings = makeAccount("Savings")
        let broker = makeAccount("Broker", .broker, currency: "USD")
        let mortgage = makeAccount("Mortgage", .debt)
        var run = makeRun([savings, broker, mortgage], startingOn: day)
        run.date = runDay.date()
        run.drafts[savings.id] = "1,000"
        run.drafts[broker.id] = "2500.25"
        run.drafts[mortgage.id] = "300000"
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let saved = run.save(in: context, now: now)

        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(Set(saved.map(\.day)), [runDay])
        XCTAssertEqual(saved.map(\.updatedAt), [now, now, now])
        XCTAssertEqual(savings.currentAmount, 1_000)
        XCTAssertEqual(broker.currentAmount, Decimal(string: "2500.25"))
        XCTAssertEqual(mortgage.currentAmount, 300_000)
    }

    func testSavingOntoADayThatHasABalanceReplacesIt() {
        let account = makeAccount("Savings")
        BalanceStore.record(100, on: runDay, for: account, in: context)
        var run = makeRun([account])
        run.drafts[account.id] = "150"

        run.save(in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.currentAmount, 150)
    }

    func testSavingAgainAfterAFailedWriteAddsNoSecondEntry() {
        let account = makeAccount("Savings")
        var run = makeRun([account])
        run.drafts[account.id] = "150"

        run.save(in: context)
        run.save(in: context)

        XCTAssertEqual(account.entries.count, 1)
        XCTAssertEqual(account.currentAmount, 150)
    }
}
