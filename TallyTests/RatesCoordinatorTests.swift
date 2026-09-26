import SwiftData
import XCTest

@testable import Tally

/// §5: which ECB file is fetched when, and what survives a failed fetch. The
/// network is `RecordingURLProtocol`, so nothing here leaves the machine.
@MainActor
final class RatesCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var settings: AppSettings!
    private var defaultsSuite: String!

    private let september22 = CalendarDay(year: 2026, month: 9, day: 22)

    override func setUp() async throws {
        container = try TallyStore.makeContainer(inMemory: true)
        context = ModelContext(container)
        defaultsSuite = "tally.tests.\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: defaultsSuite)!)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        container = nil
        context = nil
        settings = nil
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: name, withExtension: "xml"))
        return try Data(contentsOf: url)
    }

    private func makeCoordinator(stub: Data, statusCode: Int = 200) -> RatesCoordinator {
        RecordingURLProtocol.reset(stub: stub, statusCode: statusCode)
        return RatesCoordinator(service: RatesService(session: RecordingURLProtocol.makeSession()))
    }

    private var requestedURLs: [URL] {
        RecordingURLProtocol.requests.compactMap(\.url)
    }

    private func storedRateCount() throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<FXRate>())
    }

    // MARK: - Which file

    func testFirstLaunchFetchesTheFullHistory() async throws {
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-hist-sample"))

        await coordinator.refreshIfNeeded(context: context, settings: settings)

        XCTAssertEqual(requestedURLs, [ECBEndpoint.fullHistory.url])
        XCTAssertEqual(try storedRateCount(), 87, "3 days × 29 currencies")
        XCTAssertEqual(coordinator.table.latestDay, september22)
        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertNotNil(settings.lastRatesFetch)
    }

    func testAStaleCacheFetchesOnlyTheNinetyDayFile() async throws {
        try RateStore.merge([FXQuote(day: september22, currencyCode: "USD", unitsPerEUR: 1)], into: context)
        try context.save()
        settings.lastRatesFetch = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-daily"))

        await coordinator.refreshIfNeeded(context: context, settings: settings)

        XCTAssertEqual(requestedURLs, [ECBEndpoint.ninetyDays.url])
    }

    /// §5: at most once a day.
    func testAFreshCacheFetchesNothing() async throws {
        try RateStore.merge([FXQuote(day: september22, currencyCode: "USD", unitsPerEUR: 1)], into: context)
        try context.save()
        settings.lastRatesFetch = .now
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-daily"))

        await coordinator.refreshIfNeeded(context: context, settings: settings)

        XCTAssertTrue(requestedURLs.isEmpty)
    }

    func testBackfillAlwaysFetchesTheFullHistory() async throws {
        settings.lastRatesFetch = .now
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-hist-sample"))

        await coordinator.backfillHistory(context: context, settings: settings)

        XCTAssertEqual(requestedURLs, [ECBEndpoint.fullHistory.url])
    }

    // MARK: - Failure keeps what was cached

    func testAFailedFetchKeepsTheCachedTableAndSaysWhy() async throws {
        try RateStore.merge([FXQuote(day: september22, currencyCode: "USD", unitsPerEUR: 2)], into: context)
        try context.save()
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-malformed"))
        await coordinator.loadCached(from: context)

        await coordinator.refresh(.ninetyDays, context: context, settings: settings)

        guard case .failed = coordinator.status else {
            XCTFail("expected a failed status, got \(coordinator.status)")
            return
        }
        XCTAssertEqual(coordinator.table.unitsPerEUR("USD", on: september22), 2)
        XCTAssertNil(settings.lastRatesFetch, "a failure must not count as today's fetch")
        XCTAssertEqual(try storedRateCount(), 1)
    }

    func testAServerErrorIsAFailureNotAnEmptyTable() async throws {
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-daily"), statusCode: 500)

        await coordinator.refresh(.daily, context: context, settings: settings)

        XCTAssertEqual(coordinator.status, .failed(ECBRatesError.badStatus(500).localizedDescription))
        XCTAssertEqual(try storedRateCount(), 0)
    }

    func testASuccessfulRetryClearsTheFailure() async throws {
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-malformed"))
        await coordinator.refresh(.daily, context: context, settings: settings)

        RecordingURLProtocol.reset(stub: try fixture("eurofxref-daily"))
        await coordinator.refresh(.daily, context: context, settings: settings)

        XCTAssertEqual(coordinator.status, .idle)
        XCTAssertEqual(coordinator.table.latestDay, september22)
    }

    // MARK: - Cache

    func testLoadCachedReadsWhatAnEarlierLaunchStored() async throws {
        try RateStore.merge(
            [FXQuote(day: september22, currencyCode: "CHF", unitsPerEUR: Decimal(string: "0.9393")!)], into: context)
        try context.save()
        let coordinator = makeCoordinator(stub: Data())

        await coordinator.loadCached(from: context)

        XCTAssertEqual(coordinator.table.unitsPerEUR("CHF", on: september22), Decimal(string: "0.9393"))
        XCTAssertTrue(requestedURLs.isEmpty, "reading the cache never touches the network")
    }

    func testRefetchingTheSameFileDoesNotDuplicateRates() async throws {
        let coordinator = makeCoordinator(stub: try fixture("eurofxref-hist-sample"))

        await coordinator.refresh(.fullHistory, context: context, settings: settings)
        await coordinator.refresh(.fullHistory, context: context, settings: settings)

        XCTAssertEqual(try storedRateCount(), 87)
    }
}
