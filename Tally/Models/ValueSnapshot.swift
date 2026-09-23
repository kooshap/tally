import Foundation
import SwiftData

/// What an account was worth at one moment. Entered by hand — nothing here
/// is fetched from anywhere.
@Model
final class ValueSnapshot {
    var amount: Decimal = Decimal.zero
    var recordedAt: Date = Date.now
    var account: Account?

    init(amount: Decimal, recordedAt: Date = .now) {
        self.amount = amount
        self.recordedAt = recordedAt
    }
}
