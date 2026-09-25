import Foundation
import SwiftData

/// The store's shape as first shipped. Frozen: a change to any stored property
/// goes in a new version, never here, or phones holding a V1 store could no
/// longer open it.
///
/// To change the models:
/// 1. Copy this enum and its model files to `TallySchemaV2`, bump the version,
///    and make the change there.
/// 2. Point the typealiases below at V2.
/// 3. Append V2 to `TallyMigrationPlan.schemas` and add a stage from V1.
/// 4. Extend `SchemaMigrationTests` to open `tally-v1.store` under the new
///    plan, and check the fixture's data came through.
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
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try makeContainer(configuration: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: TallySchemaV1.self),
            migrationPlan: TallyMigrationPlan.self,
            configurations: configuration
        )
    }
}
