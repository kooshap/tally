import CoreData
import SwiftData
import XCTest

@testable import Tally

/// A phone keeps its store across updates, and with no sync there is no other
/// copy. These tests open a store an earlier build actually wrote.
///
/// `tally-v1.store` was written by the app before its models were versioned:
/// three accounts (one archived), five entries, and four rates. When a
/// `TallySchemaV2` arrives, it must still open here with the same data.
@MainActor
final class SchemaMigrationTests: XCTestCase {
    private var directory: URL!

    private let jan31 = CalendarDay(year: 2024, month: 1, day: 31)
    private let feb29 = CalendarDay(year: 2024, month: 2, day: 29)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    /// A copy, because opening a store can rewrite it in place.
    private func copyOfV1Store() throws -> URL {
        let fixture = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "tally-v1", withExtension: "store"))
        let url = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    private func open(_ url: URL) throws -> ModelContext {
        ModelContext(try TallyStore.makeContainer(configuration: ModelConfiguration(url: url)))
    }

    private func accounts(in context: ModelContext) throws -> [Account] {
        try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    // MARK: - The V1 store

    func testTheV1StoreOpensWithEveryAccountIntact() throws {
        let context = try open(try copyOfV1Store())

        let accounts = try accounts(in: context)

        XCTAssertEqual(accounts.map(\.name), ["Girokonto", "Brokerage", "Mortgage"])
        XCTAssertEqual(accounts.map(\.type), [.bank, .broker, .debt])
        XCTAssertEqual(accounts.map(\.currencyCode), ["EUR", "USD", "CHF"])
        XCTAssertEqual(accounts[1].notes, "Index funds")
        XCTAssertEqual(accounts[0].createdAt, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testTheV1StoreKeepsEveryBalanceToTheCent() throws {
        let context = try open(try copyOfV1Store())

        let girokonto = try XCTUnwrap(try accounts(in: context).first)

        XCTAssertEqual(girokonto.sortedEntries.map(\.day), [jan31, feb29])
        XCTAssertEqual(girokonto.sortedEntries.map(\.amount), [Decimal(string: "1234.56"), Decimal(string: "2000.01")])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BalanceEntry>()), 5)
    }

    func testTheV1StoreKeepsTheArchiveAndItsZero() throws {
        let context = try open(try copyOfV1Store())

        let mortgage = try XCTUnwrap(try accounts(in: context).last)

        XCTAssertEqual(mortgage.archivedOn, feb29)
        XCTAssertEqual(mortgage.ledger.entries.map { $0.amount }, [300_000, 0])
    }

    func testTheV1StoreKeepsItsCachedRates() throws {
        let context = try open(try copyOfV1Store())

        let table = try RateStore.loadTable(from: context)

        XCTAssertEqual(table.unitsPerEUR("USD", on: jan31), Decimal(string: "1.0837"))
        XCTAssertEqual(table.unitsPerEUR("CHF", on: feb29), Decimal(string: "0.9528"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FXRate>()), 4)
    }

    /// Opening is only half of it: the app has to be able to go on writing to
    /// the store and read that back on the next launch.
    func testTheV1StoreTakesNewEntriesThatSurviveAReopen() throws {
        let url = try copyOfV1Store()
        let march = CalendarDay(year: 2024, month: 3, day: 31)
        do {
            let context = try open(url)
            let girokonto = try XCTUnwrap(try accounts(in: context).first)
            BalanceStore.record(2_500, on: march, for: girokonto, in: context)
            try context.save()
        }

        let reopened = try XCTUnwrap(try accounts(in: try open(url)).first)

        XCTAssertEqual(reopened.currentAmount, 2_500)
        XCTAssertEqual(reopened.entries.count, 3)
    }

    /// V1 is frozen. A compatible edit to it, such as a new property with a
    /// default, still opens the old store without complaint, so the tests above
    /// would not notice V1 being changed in place; this compares its storage with
    /// the model hashes the fixture recorded when it was written.
    func testSchemaV1IsStillTheModelTheFixtureWasWrittenWith() throws {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: try copyOfV1Store())
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: TallySchemaV1.models))

        XCTAssertTrue(
            model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
            "TallySchemaV1 changed; put the change in a new schema version instead")
    }

    // MARK: - The plan

    /// Catches a new schema version added to the plan without the app being
    /// moved onto it, or the other way round.
    func testTheAppsModelsAreTheLatestSchemaVersion() throws {
        let latest = try XCTUnwrap(TallyMigrationPlan.schemas.last)
        let appModels: [any PersistentModel.Type] = [Account.self, BalanceEntry.self, FXRate.self]

        XCTAssertEqual(
            Set(latest.models.map(ObjectIdentifier.init)),
            Set(appModels.map(ObjectIdentifier.init))
        )
    }

    func testSchemaVersionsOnlyEverIncrease() {
        let versions = TallyMigrationPlan.schemas.map { $0.versionIdentifier }

        XCTAssertEqual(versions, versions.sorted())
        XCTAssertEqual(Set(versions).count, versions.count)
        XCTAssertEqual(TallyMigrationPlan.stages.count, versions.count - 1, "one stage between each pair of versions")
    }
}
