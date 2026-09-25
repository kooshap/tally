import CoreData
import Foundation
import SwiftData

/// Opens the store at launch, and holds on to the error instead of stopping
/// the app when it can't.
///
/// With no sync, the store is the only copy of the user's data. A crash at
/// every launch would leave them no way to tell that the data is still there,
/// and nothing to do but delete the app, which would delete the data with it.
@MainActor
@Observable
final class StoreLoader {
    enum State {
        case ready(ModelContainer)
        case failed(StoreFailure)
    }

    private(set) var state: State
    private let open: () throws -> ModelContainer

    init(open: @escaping () throws -> ModelContainer) {
        self.open = open
        state = Self.attempt(open)
    }

    /// Opens the store again, the same way, and never by starting a new one:
    /// an empty store in its place would look like the data had been lost.
    func tryAgain() {
        state = Self.attempt(open)
    }

    private static func attempt(_ open: () throws -> ModelContainer) -> State {
        do {
            return .ready(try open())
        } catch {
            return .failed(StoreFailure(error))
        }
    }
}

/// SwiftData reports every store that won't load as the same
/// `loadIssueModelContainer`, and drops the reason Core Data gave. This asks
/// Core Data about the file directly, so the details can say whether it is
/// unreadable or was written under a model that needed migrating.
struct StoreOpenError: Error {
    let error: any Error
    let diagnosis: String

    init(_ error: any Error, storeAt url: URL, backups: StoreBackups) {
        self.error = error
        do {
            _ = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            let migrating = backups.needsMigration(storeAt: url)
            diagnosis = "Store metadata readable; needs migration: \(migrating ? "yes" : "no")"
        } catch {
            diagnosis = "Store metadata unreadable: " + StoreFailure.describe(error as NSError)
        }
    }
}

/// What the recovery screen shows under "Technical details".
struct StoreFailure: Equatable {
    let details: String

    init(_ error: any Error) {
        let opening = error as? StoreOpenError
        let error = opening?.error ?? error
        var lines = [String(describing: error)]
        var next: NSError? = error as NSError
        while let current = next {
            lines.append(Self.describe(current))
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if let opening {
            lines.append(opening.diagnosis)
        }
        details = lines.joined(separator: "\n")
    }

    /// Domain and code first, since those are what identify an error; the
    /// description is in the phone's language.
    static func describe(_ error: NSError) -> String {
        "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
