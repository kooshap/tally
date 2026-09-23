import Foundation

enum ECBRatesError: Error, Equatable {
    case malformedXML
    case noRatesFound
    case unexpectedHost(String?)
    case badStatus(Int)
}

/// Parses the ECB's nested `Cube` format:
///
/// ```xml
/// <Cube>
///   <Cube time="2026-09-22">
///     <Cube currency="USD" rate="1.1463"/>
/// ```
///
/// The same shape covers the daily, 90-day, and full-history files, so one
/// parser serves all three.
enum ECBRatesParser {
    static func parse(_ data: Data) throws -> [FXQuote] {
        let delegate = CubeDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ECBRatesError.malformedXML }
        guard !delegate.quotes.isEmpty else { throw ECBRatesError.noRatesFound }
        return delegate.quotes
    }

    private final class CubeDelegate: NSObject, XMLParserDelegate {
        var quotes: [FXQuote] = []
        private var currentDay: CalendarDay?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard elementName == "Cube" else { return }

            if let time = attributes["time"] {
                currentDay = CalendarDay(isoString: time)
                return
            }

            guard let day = currentDay,
                let code = attributes["currency"],
                let raw = attributes["rate"]
            else { return }

            // Retired currencies appear as rate="N/A" in older history files.
            // Skipping them leaves a gap, which the table reports as a missing
            // rate rather than papering over.
            guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
                value > 0
            else { return }

            quotes.append(FXQuote(day: day, currencyCode: code, unitsPerEUR: value))
        }
    }
}
