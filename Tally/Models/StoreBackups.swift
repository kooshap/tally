import CoreData
import Foundation
import SwiftData

/// Copies of the store taken just before a migration, so a migration that goes
/// wrong on someone's phone can still be undone.
///
/// A copy is made only when the store on disk was written under a different
/// model than the app's, which is exactly when opening it would migrate it.
/// Every other launch opens the store as it is and copies nothing.
///
/// A mismatch isn't always refused. SwiftData will migrate a store it has no
/// stage for when it can infer one, and an inferred migration drops whatever
/// the new models no longer have, so the copy is taken whichever way the open
/// then goes.
struct StoreBackups {
    /// Each backup is a folder in here holding the store and its sidecars.
    let directory: URL
    /// Enough to reach back past a couple of updates in a row, without a store
    /// of a decade's balances and rates filling the phone.
    var limit = 3
    /// The models the store is about to be opened with.
    var models: [any PersistentModel.Type] = TallyStore.currentVersion.models

    /// SQLite keeps recent writes in `-wal` until they are folded into the main
    /// file, so the main file alone can be missing the latest balances.
    static let sidecarSuffixes = ["-wal", "-shm"]

    /// Copies the store at `url` aside if the current models can't read it
    /// without migrating it, and returns the backup that holds it.
    ///
    /// Nothing is copied for a new install, a store the models already match,
    /// or a store whose metadata can't be read: that last one can't be
    /// migrated either, and opening it fails without writing to it. When the
    /// newest backup already holds this exact store, as it does when the user
    /// taps "Try again" after a failed migration, that backup is returned and
    /// no copy is made, so retries can't push the older backups out.
    @discardableResult
    func backUpIfMigrating(storeAt url: URL, now: Date = .now) throws -> URL? {
        guard needsMigration(storeAt: url) else { return nil }

        let files = Self.files(ofStoreAt: url)
        if let newest = try existing().first, Self.holds(files, backup: newest) {
            return newest
        }

        let backup = try makeFolder(for: now)
        do {
            for file in files {
                try FileManager.default.copyItem(at: file, to: backup.appending(path: file.lastPathComponent))
            }
        } catch {
            // A half-made copy, say on a full phone, must not pass for a backup.
            try? FileManager.default.removeItem(at: backup)
            throw error
        }
        prune()
        return backup
    }

    /// Whether opening the store with `models` would run a migration.
    func needsMigration(storeAt url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url),
            let model = NSManagedObjectModel.makeManagedObjectModel(for: models)
        else { return false }
        return !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }

    /// The backups there are, newest first.
    func existing() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// The store file and whichever sidecars sit next to it.
    static func files(ofStoreAt url: URL) -> [URL] {
        let sidecars = sidecarSuffixes.map {
            url.deletingLastPathComponent().appending(path: url.lastPathComponent + $0)
        }
        return [url] + sidecars.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// `-shm` is left out of the comparison: it is SQLite's index into `-wal`,
    /// rebuilt from it, and it changes whenever the store is read at all.
    private static func holds(_ files: [URL], backup: URL) -> Bool {
        files.filter { !$0.lastPathComponent.hasSuffix("-shm") }.allSatisfy {
            FileManager.default.contentsEqual(
                atPath: $0.path(percentEncoded: false),
                andPath: backup.appending(path: $0.lastPathComponent).path(percentEncoded: false))
        }
    }

    /// Named for the moment it was taken, in UTC, so the names sort by age.
    private func makeFolder(for date: Date) throws -> URL {
        let stamp = date.formatted(
            .iso8601
                .year().month().day()
                .dateTimeSeparator(.standard)
                .time(includingFractionalSeconds: true)
                .timeSeparator(.omitted)
        )
        var folder = directory.appending(path: stamp, directoryHint: .isDirectory)
        var attempt = 1
        while FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            attempt += 1
            folder = directory.appending(path: "\(stamp)-\(attempt)", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Only ever after a new copy is in place, so there is always one left.
    private func prune() {
        guard let backups = try? existing() else { return }
        for old in backups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
