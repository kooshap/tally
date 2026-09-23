import Foundation

/// Formatting only — the currency is a display preference, not a conversion.
/// Tally never fetches exchange rates, so mixing currencies across accounts
/// would silently produce a wrong total. One currency, chosen once.
enum CurrencyFormat {
    static let defaultCode: String = Locale.current.currency?.identifier ?? "USD"

    static func string(_ amount: Decimal, code: String = defaultCode) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }

    /// Reads what a person typed into a plain text field, tolerating grouping
    /// separators and a stray currency symbol.
    static func parse(_ text: String, code: String = defaultCode) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = try? Decimal(trimmed, format: .number.grouping(.automatic)) {
            return value
        }
        if let value = try? Decimal(trimmed, format: .currency(code: code)) {
            return value
        }
        let digitsOnly = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        return Decimal(string: digitsOnly.replacingOccurrences(of: ",", with: ""))
    }
}
