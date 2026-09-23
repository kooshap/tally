import Foundation
import SwiftData

/// One thing you own or owe. Its worth is the most recent `ValueSnapshot`;
/// older snapshots are kept so the balance has a history.
@Model
final class Account {
    var name: String = ""
    /// Stored raw so the enum can gain cases without a migration.
    var kindRawValue: String = AccountKind.cash.rawValue
    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ValueSnapshot.account)
    var snapshots: [ValueSnapshot] = []

    init(name: String, kind: AccountKind, notes: String = "", createdAt: Date = .now) {
        self.name = name
        self.kindRawValue = kind.rawValue
        self.notes = notes
        self.createdAt = createdAt
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRawValue) ?? .otherAsset }
        set { kindRawValue = newValue.rawValue }
    }

    var latestSnapshot: ValueSnapshot? {
        snapshots.max { $0.recordedAt < $1.recordedAt }
    }

    /// Always non-negative: a mortgage of 400k is stored as 400_000, not -400_000.
    var currentValue: Decimal {
        latestSnapshot?.amount ?? 0
    }

    /// Snapshots oldest-first, for history lists and charts.
    var history: [ValueSnapshot] {
        snapshots.sorted { $0.recordedAt < $1.recordedAt }
    }

    func record(_ amount: Decimal, on date: Date = .now) -> ValueSnapshot {
        let snapshot = ValueSnapshot(amount: amount, recordedAt: date)
        snapshot.account = self
        snapshots.append(snapshot)
        return snapshot
    }
}
