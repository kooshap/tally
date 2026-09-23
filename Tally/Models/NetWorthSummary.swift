import Foundation

/// A plain value type so the arithmetic can be tested without a model container.
struct NetWorthSummary: Equatable {
    /// One account reduced to the only two facts the total cares about.
    struct Entry: Equatable {
        var amount: Decimal
        var isLiability: Bool
    }

    var assets: Decimal = 0
    var liabilities: Decimal = 0

    var net: Decimal { assets - liabilities }

    init(assets: Decimal = 0, liabilities: Decimal = 0) {
        self.assets = assets
        self.liabilities = liabilities
    }

    init(entries: [Entry]) {
        for entry in entries {
            if entry.isLiability {
                liabilities += entry.amount
            } else {
                assets += entry.amount
            }
        }
    }

    init(accounts: [Account]) {
        self.init(entries: accounts.map {
            Entry(amount: $0.currentValue, isLiability: $0.kind.isLiability)
        })
    }
}
