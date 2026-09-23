import Foundation

/// The ECB euro foreign exchange reference rate files. These three URLs were
/// verified live on 2026-09-22: daily carried 29 currencies, the 90-day file 64
/// business days, and the full history 7,098 days back to 1999-01-04.
enum ECBEndpoint: String, CaseIterable, Sendable {
    case daily
    case ninetyDays
    case fullHistory

    var url: URL {
        switch self {
        case .daily:
            return URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
        case .ninetyDays:
            return URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!
        case .fullHistory:
            return URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml")!
        }
    }

    /// The only host the app is ever allowed to contact.
    static let host = "www.ecb.europa.eu"
}
