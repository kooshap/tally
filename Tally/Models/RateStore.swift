import Foundation
import SwiftData

/// Caches ECB quotes and hands the domain layer an immutable `RateTable`.
enum RateStore {
    /// Merges by day and currency: a quote already held for that pair is
    /// updated, not duplicated. The ECB does occasionally restate a rate.
    static func merge(_ quotes: [FXQuote], into context: ModelContext) throws {
        guard !quotes.isEmpty else { return }

        let existing = try context.fetch(FetchDescriptor<FXRate>())
        var index: [Int: [String: FXRate]] = [:]
        for rate in existing {
            index[rate.dayNumber, default: [:]][rate.currencyCode] = rate
        }

        for quote in quotes where quote.currencyCode != CurrencyCatalog.base {
            if let stored = index[quote.day.rawValue]?[quote.currencyCode] {
                if stored.unitsPerEUR != quote.unitsPerEUR {
                    stored.unitsPerEUR = quote.unitsPerEUR
                }
            } else {
                let rate = FXRate(
                    day: quote.day,
                    currencyCode: quote.currencyCode,
                    unitsPerEUR: quote.unitsPerEUR
                )
                context.insert(rate)
                index[quote.day.rawValue, default: [:]][quote.currencyCode] = rate
            }
        }
    }

    static func loadTable(from context: ModelContext) throws -> RateTable {
        let rates = try context.fetch(FetchDescriptor<FXRate>())
        return RateTable(quotes: rates.map(\.quote))
    }

    static func isEmpty(_ context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<FXRate>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty
    }
}
