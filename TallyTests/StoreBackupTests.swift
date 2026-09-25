import SwiftData
import XCTest

@testable import Tally

/// A model Tally never had. A store written with it stands in for one written
/// under another schema version, which the app's models can't read without a
/// migration.
@Model
private final class Stranger {
    var name: String = ""

    init(name: String) {
        self.name = name
    }
}

/// With no sync, a migration that goes wrong on a phone would leave no copy of
/// the data anywhere. These check a copy is taken first, and only then.
@MainActor
final class StoreBackupTests: XCTestCase {
    private var directory: URL!
    private var backups: StoreBackups!
    private var storeURL: URL!
    private var writers: [ModelContainer] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        backups = StoreBackups(directory: directory.appending(path: "Store Backups", directoryHint: .isDirectory))
        storeURL = directory.appending(path: "default.store")
    }

    override func tearDown() async throws {
        writers = []
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        backups = nil
        storeURL = nil
    }

    // MARK: - Stores

    /// Writes a store under another model, and copies it to `storeURL` while it
    /// is still open, the way a phone holds it when the app is closed: the
    /// latest writes still in `-wal`, beside an `-shm`.
    private func writeStoreFromAnotherVersion(names: [String] = ["Old account"]) throws {
        let writer = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: writer, withIntermediateDirectories: true)
        let url = writer.appending(path: "default.store")
        let container = try ModelContainer(for: Stranger.self, configurations: ModelConfiguration(url: url))
        writers.append(container)
        let context = ModelContext(container)
        for name in names {
            context.insert(Stranger(name: name))
        }
        try context.save()

        for suffix in [""] + StoreBackups.sidecarSuffixes {
            let copy = sidecar(suffix, of: storeURL)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: sidecar(suffix, of: url), to: copy)
        }
    }

    private func writeStoreFromThisVersion() throws {
        let context = ModelContext(try TallyStore.makeContainer(configuration: ModelConfiguration(url: storeURL)))
        context.insert(Account(name: "Girokonto", type: .bank, currencyCode: "EUR"))
        try context.save()
    }

    private func copyOfV1Fixture() throws {
        let fixture = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "tally-v1", withExtension: "store"))
        try FileManager.default.copyItem(at: fixture, to: storeURL)
    }

    private func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private func sidecar(_ suffix: String, of url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }

    // MARK: - When a copy is taken

    func testANewInstallHasNothingToBackUp() throws {
        XCTAssertNil(try backups.backUpIfMigrating(storeAt: storeURL))
        XCTAssertEqual(try backups.existing(), [])
    }

    /// The everyday launch: the store already matches the models, so it opens
    /// as it is, and nothing is copied, however many times it opens.
    func testAStoreTheAppAlreadyReadsIsNeverBackedUp() throws {
        try writeStoreFromThisVersion()

        for _ in 1...3 {
            XCTAssertNil(try backups.backUpIfMigrating(storeAt: storeURL))
            _ = try TallyStore.open(ModelConfiguration(url: storeURL), backingUpTo: backups)
        }

        XCTAssertEqual(try backups.existing(), [])
    }

    /// Nothing to do while V1 is current. Once a V2 is added, a phone holding
    /// a V1 store must get a copy of it before the stage runs.
    func testTheV1StoreIsBackedUpExactlyWhenTheSchemaHasMovedPastIt() throws {
        try copyOfV1Fixture()
        let movedOn = TallyStore.currentVersion.versionIdentifier != TallySchemaV1.versionIdentifier

        let backup = try backups.backUpIfMigrating(storeAt: storeURL)

        XCTAssertEqual(backup != nil, movedOn)
        if let backup {
            XCTAssertEqual(try contents(of: backup.appending(path: "default.store")), try contents(of: storeURL))
        }
    }

    /// Garbage can't be migrated any more than it can be opened, so there is
    /// nothing a copy would protect.
    func testAStoreWhoseMetadataCantBeReadIsNotBackedUp() throws {
        try Data([0x54, 0x61, 0x6C, 0x6C, 0x79, 0x00, 0xFF]).write(to: storeURL)

        XCTAssertNil(try backups.backUpIfMigrating(storeAt: storeURL))
        XCTAssertEqual(try backups.existing(), [])
    }

    // MARK: - What the copy holds

    func testAStoreAMigrationWouldChangeIsCopiedWithItsSidecars() throws {
        try writeStoreFromAnotherVersion()
        let store = try contents(of: storeURL)
        let wal = try contents(of: sidecar("-wal", of: storeURL))
        XCTAssertFalse(wal.isEmpty, "the latest writes should still be in -wal")

        let backup = try XCTUnwrap(try backups.backUpIfMigrating(storeAt: storeURL))

        let copied = try FileManager.default.contentsOfDirectory(atPath: backup.path(percentEncoded: false))
        XCTAssertEqual(Set(copied), ["default.store", "default.store-wal", "default.store-shm"])
        XCTAssertEqual(try contents(of: backup.appending(path: "default.store")), store)
        XCTAssertEqual(try contents(of: backup.appending(path: "default.store-wal")), wal)
        XCTAssertEqual(
            try contents(of: backup.appending(path: "default.store-shm")),
            try contents(of: sidecar("-shm", of: storeURL)))
    }

    /// The copy is taken before the store is opened, whatever opening it then
    /// does to it. On iOS 26, SwiftData migrates even this store, from a model
    /// it has never seen, dropping the entity it doesn't know along with its
    /// rows, rather than refusing to open it.
    func testOpeningAStoreThatNeedsMigratingCopiesItFirst() throws {
        try writeStoreFromAnotherVersion()
        let before = try contents(of: storeURL)

        _ = try? TallyStore.open(ModelConfiguration(url: storeURL), backingUpTo: backups)

        let backup = try XCTUnwrap(try backups.existing().first)
        XCTAssertEqual(try contents(of: backup.appending(path: "default.store")), before)
    }

    /// The copy is a store in its own right: open it with the models that
    /// wrote it, and the data is there.
    func testTheCopyOpensWithTheDataItHeld() throws {
        try writeStoreFromAnotherVersion(names: ["Girokonto", "Mortgage"])
        let backup = try XCTUnwrap(try backups.backUpIfMigrating(storeAt: storeURL))
        writers = []

        let reopened = try ModelContainer(
            for: Stranger.self, configurations: ModelConfiguration(url: backup.appending(path: "default.store")))
        let names = try ModelContext(reopened).fetch(FetchDescriptor<Stranger>()).map(\.name)

        XCTAssertEqual(Set(names), ["Girokonto", "Mortgage"])
    }

    // MARK: - How many are kept

    /// Tapping "Try again" after a failed migration meets the same store each
    /// time. Copying it again would soon push out the backups before it.
    func testTheSameStoreIsNotCopiedTwice() throws {
        try writeStoreFromAnotherVersion()

        let first = try backups.backUpIfMigrating(storeAt: storeURL, now: Date(timeIntervalSince1970: 1_000))
        let second = try backups.backUpIfMigrating(storeAt: storeURL, now: Date(timeIntervalSince1970: 2_000))

        XCTAssertNotNil(first)
        XCTAssertEqual(second, first)
        XCTAssertEqual(try backups.existing().count, 1)
    }

    func testOnlyTheNewestBackupsAreKept() throws {
        var made: [URL] = []
        for hour in 0..<5 {
            try writeStoreFromAnotherVersion(names: (0...hour).map { "Account \($0)" })
            let now = Date(timeIntervalSince1970: 1_700_000_000 + Double(hour) * 3_600)
            made.append(try XCTUnwrap(try backups.backUpIfMigrating(storeAt: storeURL, now: now)))
        }

        XCTAssertEqual(backups.limit, 3)
        XCTAssertEqual(
            try backups.existing().map(\.lastPathComponent), made.suffix(3).reversed().map(\.lastPathComponent))
    }

    func testTwoBackupsInTheSameInstantBothKeepTheirOwnFolder() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try writeStoreFromAnotherVersion(names: ["First"])
        let first = try XCTUnwrap(try backups.backUpIfMigrating(storeAt: storeURL, now: now))
        try writeStoreFromAnotherVersion(names: ["Second"])
        let second = try XCTUnwrap(try backups.backUpIfMigrating(storeAt: storeURL, now: now))

        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertEqual(try backups.existing().map(\.lastPathComponent), [second, first].map(\.lastPathComponent))
    }

    // MARK: - On the phone

    /// Installs from before backups existed opened SwiftData's default store;
    /// they must go on opening the same file.
    func testThePhoneStillOpensSwiftDatasDefaultStore() {
        XCTAssertEqual(TallyStore.onDevice.url, URL.applicationSupportDirectory.appending(path: "default.store"))
        XCTAssertFalse(TallyStore.onDevice.isStoredInMemoryOnly)
    }

    /// Application Support is in the iPhone backup, so the copies are too.
    func testBackupsOnThePhoneLiveInApplicationSupport() {
        XCTAssertEqual(
            TallyStore.backupsOnDevice.directory.deletingLastPathComponent().standardizedFileURL,
            URL.applicationSupportDirectory.standardizedFileURL)
    }
}
