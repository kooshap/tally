import Foundation

/// Display only. Every calculation stays in `Decimal`; these helpers are the
/// last step before text.
enum MoneyFormatting {
    static func string(_ amount: Decimal, code: String, locale: Locale = .current) -> String {
        amount.formatted(
            .currency(code: code)
                .locale(locale)
                .precision(.fractionLength(0...2))
        )
    }

    /// Compact form for chart axes: 1.2M, 340k.
    static func compact(_ amount: Decimal, code: String, locale: Locale = .current) -> String {
        let magnitude = abs((amount as NSDecimalNumber).doubleValue)
        let formatted: String
        switch magnitude {
        case 1_000_000...:
            formatted = (amount / 1_000_000).formatted(.number.locale(locale).precision(.fractionLength(0...1))) + "M"
        case 10_000...:
            formatted = (amount / 1_000).formatted(.number.locale(locale).precision(.fractionLength(0))) + "k"
        default:
            return string(amount, code: code, locale: locale)
        }
        return "\(formatted) \(code)"
    }

    /// A signed change, always carrying its sign so a rise reads unambiguously.
    static func signedChange(_ amount: Decimal, code: String, locale: Locale = .current) -> String {
        let formatted = string(abs(amount), code: code, locale: locale)
        if amount > 0 { return "+\(formatted)" }
        if amount < 0 { return "−\(formatted)" }
        return formatted
    }

    /// What an amount field is pre-filled with: no symbol, no grouping, and the
    /// locale's decimal separator, so `parse` reads back exactly this amount.
    /// `"\(amount)"` would not survive a round trip in a locale such as German,
    /// where the `.` it writes is a grouping separator.
    static func editableString(_ amount: Decimal, locale: Locale = .current) -> String {
        amount.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(0...10))
        )
    }

    /// Reads a typed amount, tolerating grouping separators and a stray symbol.
    static func parse(_ text: String, code: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = try? Decimal(trimmed, format: .number.locale(locale)) { return value }
        if let value = try? Decimal(trimmed, format: .currency(code: code).locale(locale)) { return value }

        let separator = locale.decimalSeparator ?? "."
        let cleaned =
            trimmed
            .filter { $0.isNumber || $0 == "-" || String($0) == separator }
            .replacingOccurrences(of: separator, with: ".")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
