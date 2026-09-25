import Foundation
import SwiftData

/// The store's shape as first shipped. Frozen: a change to any stored property
/// goes in a new version, never here, or phones holding a V1 store could no
/// longer open it.
///
/// To change the models:
/// 1. Copy this enum and its model files to `TallySchemaV2`, bump the version,
///    and make the change there.
/// 2. Point the typealiases below and `TallyStore.currentVersion` at V2.
/// 3. Append V2 to `TallyMigrationPlan.schemas` and add a stage from V1.
/// 4. Extend `SchemaMigrationTests` to open `tally-v1.store` under the new
///    plan, and check the fixture's data came through.
/// 5. `StoreBackupTests` then expects the V1 fixture to be copied aside before
///    it migrates. Check that it passes: that copy is the way back if the
///    stage goes wrong on someone's phone.
enum TallySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Account.self, BalanceEntry.self, FXRate.self]
    }
}

// The rest of the app names the current version's models.
typealias Account = TallySchemaV1.Account
typealias BalanceEntry = TallySchemaV1.BalanceEntry
typealias FXRate = TallySchemaV1.FXRate

enum TallyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TallySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Every container, the app's and the tests', opens through here, so they all
/// read the store with the same schema and migration plan.
enum TallyStore {
    /// The version the app reads and writes. A store written under anything
    /// else is migrated to it on open.
    static var currentVersion: any VersionedSchema.Type { TallySchemaV1.self }

    /// The store on the phone: SwiftData's default location, Application
    /// Support/default.store. No URL is given, so an install from before this
    /// existed goes on opening the same file.
    static var onDevice: ModelConfiguration {
        ModelConfiguration(isStoredInMemoryOnly: false)
    }

    /// Where copies are kept before a migration. Application Support is in the
    /// iPhone backup, so the copies are too.
    static var backupsOnDevice: StoreBackups {
        StoreBackups(
            directory: URL.applicationSupportDirectory.appending(path: "Store Backups", directoryHint: .isDirectory))
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: currentVersion),
            migrationPlan: TallyMigrationPlan.self,
            configurations: configuration
        )
    }

    /// Opens a store on disk, first copying it aside if opening it would
    /// migrate it. With no sync there is no other copy to go back to if a
    /// migration goes wrong. If the copy can't be made, the store isn't
    /// opened either, so it is never migrated without one.
    static func open(_ configuration: ModelConfiguration, backingUpTo backups: StoreBackups) throws -> ModelContainer {
        try backups.backUpIfMigrating(storeAt: configuration.url)
        do {
            return try makeContainer(configuration: configuration)
        } catch {
            throw StoreOpenError(error, storeAt: configuration.url, backups: backups)
        }
    }
}
