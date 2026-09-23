import Foundation

/// What an account represents. Type alone fixes the sign in the total, so a
/// mortgage is entered and stored as a positive outstanding balance and
/// subtracted only when the net worth is summed.
enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case bank
    case broker
    case realEstate
    case debt

    var id: String { rawValue }

    /// `+1` for things you own, `-1` for things you owe.
    var sign: Decimal {
        self == .debt ? -1 : 1
    }

    var isLiability: Bool { self == .debt }

    /// A bank balance may legitimately be negative (an overdraft); the others
    /// are entered as positive figures.
    var allowsNegativeBalance: Bool { self == .bank }

    var localizedName: String {
        switch self {
        case .bank: return String(localized: "Bank account")
        case .broker: return String(localized: "Broker account")
        case .realEstate: return String(localized: "Real estate")
        case .debt: return String(localized: "Debt")
        }
    }

    var symbolName: String {
        switch self {
        case .bank: return "banknote"
        case .broker: return "chart.line.uptrend.xyaxis"
        case .realEstate: return "house"
        case .debt: return "creditcard"
        }
    }
}
