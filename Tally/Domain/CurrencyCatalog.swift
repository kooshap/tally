import Foundation

/// The currencies a user may pick: those the ECB publishes, plus EUR itself.
///
/// Deliberately closed. Offering a currency the ECB does not publish would let
/// someone build a portfolio the app can never convert, and §4 forbids guessing
/// a rate.
enum CurrencyCatalog {
    /// EUR is the pivot: every ECB rate is expressed as units per euro.
    static let base = "EUR"

    /// Taken from eurofxref-daily.xml as published on 2026-09-22 (29 currencies).
    /// The full history file carries 41 codes in all; the extras are retired
    /// ones such as HRK and BGN, which stay convertible for old entries but
    /// are not offered for new accounts.
    static let published: [String] = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR",
        "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY",
        "USD", "ZAR",
    ]

    static let all: [String] = ([base] + published).sorted()

    static func isSupported(_ code: String) -> Bool {
        all.contains(code.uppercased())
    }

    /// "US Dollar (USD)", localized by the reader's own locale.
    static func displayName(_ code: String, locale: Locale = .current) -> String {
        guard let name = locale.localizedString(forCurrencyCode: code) else { return code }
        return "\(name) (\(code))"
    }

    /// The device's currency when the app has never been configured, falling
    /// back to EUR when it is one the ECB does not publish.
    static func deviceDefault(locale: Locale = .current) -> String {
        guard let code = locale.currency?.identifier, isSupported(code) else { return base }
        return code
    }
}
