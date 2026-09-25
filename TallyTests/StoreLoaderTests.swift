import CoreData
import SwiftData
import XCTest

@testable import Tally

private struct NotYet: Error {}

/// A store that won't open used to stop the app at every launch. Now it is a
/// state the app shows, and nothing about it touches the file.
@MainActor
final class StoreLoaderTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!
    private var backups: StoreBackups!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "default.store")
        backups = StoreBackups(directory: directory.appending(path: "Store Backups", directoryHint: .isDirectory))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        storeURL = nil
        backups = nil
    }

    /// A few random bytes: something no SQLite or SwiftData version can open.
    private func writeUnopenableStore() throws -> Data {
        let bytes = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        try bytes.write(to: storeURL)
        return bytes
    }

    private func loader() -> StoreLoader {
        let url = storeURL!
        let backups = backups!
        return StoreLoader { try TallyStore.open(ModelConfiguration(url: url), backingUpTo: backups) }
    }

    private func failure(of loader: StoreLoader) -> StoreFailure? {
        if case .failed(let failure) = loader.state { return failure }
        return nil
    }

    private func isReady(_ loader: StoreLoader) -> Bool {
        if case .ready = loader.state { return true }
        return false
    }

    // MARK: - A store that won't open

    func testAStoreThatWontOpenLeadsToTheRecoveryScreenNotACrash() throws {
        _ = try writeUnopenableStore()

        let loader = loader()

        let failure = try XCTUnwrap(failure(of: loader))
        XCTAssertFalse(failure.details.isEmpty)
    }

    func testAStoreThatWontOpenIsLeftByteForByteAsItWas() throws {
        let bytes = try writeUnopenableStore()

        let loader = loader()
        loader.tryAgain()
        loader.tryAgain()

        XCTAssertNotNil(failure(of: loader))
        XCTAssertEqual(try Data(contentsOf: storeURL), bytes)
    }

    /// Not replaced by an empty store, not moved aside, and no copy of it made.
    func testAStoreThatWontOpenIsTheOnlyFileThereAfterwards() throws {
        _ = try writeUnopenableStore()

        let loader = loader()
        loader.tryAgain()

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        XCTAssertEqual(files, ["default.store"])
    }

    // MARK: - Trying again

    func testTryingAgainOpensTheStoreOnceItCanBeOpened() throws {
        var attempts = 0
        let loader = StoreLoader {
            attempts += 1
            if attempts == 1 { throw NotYet() }
            return try TallyStore.makeContainer(inMemory: true)
        }
        XCTAssertNotNil(failure(of: loader))

        loader.tryAgain()

        XCTAssertTrue(isReady(loader))
        XCTAssertEqual(attempts, 2)
    }

    func testAStoreThatOpensIsReadyStraightAway() throws {
        let loader = loader()

        XCTAssertTrue(isReady(loader))
    }

    // MARK: - What the screen shows

    /// SwiftData's own error says only that the container didn't load. The
    /// details add what Core Data makes of the file.
    func testTheDetailsSayWhatCoreDataMakesOfTheFile() throws {
        _ = try writeUnopenableStore()

        let details = try XCTUnwrap(failure(of: loader())).details

        XCTAssertTrue(details.contains("Store metadata unreadable: NSCocoaErrorDomain 259"), details)
    }

    /// The error is what someone helping would need, so its type and code
    /// both appear, along with whatever caused it.
    func testTheDetailsNameTheErrorAndWhatCausedIt() {
        let cause = NSError(
            domain: NSSQLiteErrorDomain, code: 26, userInfo: [NSLocalizedDescriptionKey: "file is not a database"])
        let error = NSError(domain: NSCocoaErrorDomain, code: 259, userInfo: [NSUnderlyingErrorKey: cause])

        let details = StoreFailure(error).details

        XCTAssertTrue(details.contains("NSCocoaErrorDomain 259"), details)
        XCTAssertTrue(details.contains("NSSQLiteErrorDomain 26: file is not a database"), details)
    }
}
