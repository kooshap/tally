import Foundation
import SwiftData

/// Caches ECB quotes and hands the domain layer an immutable `RateTable`.
enum RateStore {
    /// Rates older than this are not kept. The ECB's history goes back to
    /// 1999, but only as one file, so the download stays the same size; this
    /// keeps the store and the in-memory table to about 40% of it (93,001 of
    /// 220,919 rates in the file fetched on 2026-09-23).
    static let earliestDay = CalendarDay(year: 2015, month: 1, day: 1)

    /// The quotes worth keeping: everything from `earliestDay` on, plus the
    /// last publication before it. The ECB does not publish on New Year's Day,
    /// so without that one day a balance dated 1 January 2015 would have no
    /// rate to carry forward.
    static func trimmed(_ quotes: [FXQuote]) -> [FXQuote] {
        let anchor = quotes.lazy.map(\.day).filter { $0 < earliestDay }.max()
        let firstKept = anchor ?? earliestDay
        return quotes.filter { $0.day >= firstKept }
    }

    /// Merges by day and currency: a quote already held for that pair is
    /// updated, not duplicated. The ECB does occasionally restate a rate.
    static func merge(_ quotes: [FXQuote], into context: ModelContext) throws {
        let quotes = trimmed(quotes)
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

    // MARK: - Off the main actor

    // Even trimmed to `earliestDay`, the history is ~93,000 rows. Merging, saving, or even fetching that
    // on the main context stalls the UI for seconds, so the coordinator goes
    // through these, each on a throwaway context of its own.

    static func mergeInBackground(_ quotes: [FXQuote], into container: ModelContainer) async throws -> RateTable {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            try merge(quotes, into: context)
            try context.save()
            return try loadTable(from: context)
        }.value
    }

    static func loadTableInBackground(from container: ModelContainer) async throws -> RateTable {
        try await Task.detached(priority: .userInitiated) {
            try loadTable(from: ModelContext(container))
        }.value
    }
}
