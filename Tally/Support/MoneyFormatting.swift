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

    /// A change as a share, unsigned, to sit beside `signedChange`: 4.2%.
    static func percent(_ fraction: Decimal, locale: Locale = .current) -> String {
        abs(fraction).formatted(.percent.locale(locale).precision(.fractionLength(1)))
    }

    /// What an amount field is pre-filled with: no symbol, the locale's
    /// grouping, and its decimal separator, so `parse` reads back exactly this
    /// amount. `"\(amount)"` would not survive a round trip in a locale such as
    /// German, where the `.` it writes is a grouping separator.
    static func editableString(_ amount: Decimal, locale: Locale = .current) -> String {
        amount.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(0...10))
        )
    }

    /// Regroups the whole-number digits of a half-typed amount — 1234567
    /// becomes 1,234,567 — and keeps the rest as typed: the sign, a trailing
    /// decimal separator, and fraction digits. Anything that isn't a plain
    /// number comes back untouched, leaving the verdict to `parse`.
    ///
    /// `caret` is the insertion point as a character offset into `text`. It
    /// comes back moved to sit after the same digit it followed before, so
    /// typing or deleting mid-number doesn't throw the cursor to the end.
    static func regroupedForTyping(
        _ text: String,
        caret: Int,
        locale: Locale = .current
    ) -> (text: String, caret: Int) {
        let unchanged = (text, caret)
        let decimalSeparator = Character(locale.decimalSeparator ?? ".")
        let groupingMarks = groupingMarks(locale)

        var rest = Substring(text)
        var sign = ""
        if let first = rest.first, first == "-" || first == "−" {
            sign = String(first)
            rest = rest.dropFirst()
        }
        let parts = rest.split(separator: decimalSeparator, maxSplits: 1, omittingEmptySubsequences: false)
        let digits = parts[0].filter { !groupingMarks.contains($0) }
        let fraction = parts.count > 1 ? String(decimalSeparator) + parts[1] : ""

        let isPlainDigits: (Substring) -> Bool = { $0.allSatisfy { $0.isASCII && $0.isNumber } }
        // Past 30 digits `Decimal` starts rounding, which would rewrite what was typed.
        guard isPlainDigits(Substring(digits)), isPlainDigits(fraction.dropFirst()), digits.count <= 30 else {
            return unchanged
        }

        let grouped =
            digits.isEmpty
            ? ""
            : (Decimal(string: digits) ?? 0).formatted(.number.locale(locale).grouping(.automatic))
        let result = sign + grouped + fraction

        // Everything but grouping marks is carried over one for one, so the
        // caret belongs after as many of those as it followed before.
        let kept = text.prefix(caret).count { !groupingMarks.contains($0) }
        var newCaret = 0
        var seen = 0
        for character in result {
            if seen == kept { break }
            newCaret += 1
            if !groupingMarks.contains(character) { seen += 1 }
        }
        return (result, newCaret)
    }

    /// An amount field's text after one keystroke or paste: `replacement`
    /// put in place of the characters at `range`, then regrouped. `range` and
    /// the returned caret are character offsets. Deleting only a grouping mark
    /// deletes the digit before it too, since the mark alone would just come
    /// straight back.
    static func applyingEdit(
        to text: String,
        replacing range: Range<Int>,
        with replacement: String,
        locale: Locale = .current
    ) -> (text: String, caret: Int) {
        var characters = Array(text)
        var range = range.clamped(to: 0..<characters.count)
        if replacement.isEmpty, range.count == 1, range.lowerBound > 0,
            groupingMarks(locale).contains(characters[range.lowerBound])
        {
            range = (range.lowerBound - 1)..<range.upperBound
        }
        characters.replaceSubrange(range, with: Array(replacement))
        return regroupedForTyping(String(characters), caret: range.lowerBound + replacement.count, locale: locale)
    }

    /// What may separate groups of digits as typed: the locale's own mark, and
    /// the spaces and apostrophes people type for it.
    private static func groupingMarks(_ locale: Locale) -> Set<Character> {
        let decimalSeparator = Character(locale.decimalSeparator ?? ".")
        return Set(
            [locale.groupingSeparator ?? ",", " ", "\u{00A0}", "\u{202F}", "'", "’"]
                .compactMap(\.first)
                .filter { $0 != decimalSeparator }
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
