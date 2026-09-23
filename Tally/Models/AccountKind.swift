import Foundation

/// The kind of thing an account represents. Kind alone decides whether a
/// balance counts toward what you own or what you owe.
enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case cash
    case investment
    case retirement
    case property
    case vehicle
    case otherAsset
    case creditCard
    case loan
    case mortgage

    var id: String { rawValue }

    var isLiability: Bool {
        switch self {
        case .creditCard, .loan, .mortgage:
            return true
        case .cash, .investment, .retirement, .property, .vehicle, .otherAsset:
            return false
        }
    }

    var label: String {
        switch self {
        case .cash: return String(localized: "Cash")
        case .investment: return String(localized: "Investments")
        case .retirement: return String(localized: "Retirement")
        case .property: return String(localized: "Property")
        case .vehicle: return String(localized: "Vehicle")
        case .otherAsset: return String(localized: "Other asset")
        case .creditCard: return String(localized: "Credit card")
        case .loan: return String(localized: "Loan")
        case .mortgage: return String(localized: "Mortgage")
        }
    }

    var symbolName: String {
        switch self {
        case .cash: return "banknote"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .retirement: return "figure.and.child.holdinghands"
        case .property: return "house"
        case .vehicle: return "car"
        case .otherAsset: return "shippingbox"
        case .creditCard: return "creditcard"
        case .loan: return "doc.text"
        case .mortgage: return "building.columns"
        }
    }
}
