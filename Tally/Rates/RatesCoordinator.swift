import Foundation
import SwiftData
import SwiftUI

/// Decides which ECB file to fetch, merges the result, and holds the table the
/// views read from.
@MainActor
@Observable
final class RatesCoordinator {
    enum Status: Equatable {
        case idle
        case refreshing
        case failed(String)
    }

    private(set) var table: RateTable = .empty
    private(set) var status: Status = .idle

    private let service: RatesService

    init(service: RatesService = RatesService()) {
        self.service = service
    }

    /// Reads whatever is already cached. Called before any network attempt, so
    /// the app is usable offline straight away.
    func loadCached(from context: ModelContext) async {
        let cached = (try? await RateStore.loadTableInBackground(from: context.container)) ?? .empty
        // A refresh that finished during the read, say one started by the app
        // coming to the front, loaded the whole store after merging into it, so
        // this read has nothing it lacks.
        guard table.isEmpty else { return }
        table = cached
    }

    /// §5: the full history on first launch, so backfilled entries get the
    /// rates of their own date; afterwards the 90-day file, which covers gaps
    /// left by the app not being opened for a while.
    func refreshIfNeeded(context: ModelContext, settings: AppSettings) async {
        let hasNoRates = (try? RateStore.isEmpty(context)) ?? true
        if hasNoRates {
            await refresh(.fullHistory, context: context, settings: settings)
        } else if settings.needsRateRefresh {
            await refresh(.ninetyDays, context: context, settings: settings)
        }
    }

    /// iOS can keep the app running for days, so the once-a-day check at launch
    /// also runs each time it comes back to the front.
    func sceneDidChange(to phase: ScenePhase, context: ModelContext, settings: AppSettings) async {
        guard phase == .active else { return }
        await refreshIfNeeded(context: context, settings: settings)
    }

    /// §5: on failure keep the cached rates and stay quiet — Settings shows the
    /// "Rates as of …" date and offers a manual retry.
    func refresh(_ endpoint: ECBEndpoint, context: ModelContext, settings: AppSettings) async {
        guard status != .refreshing else { return }
        status = .refreshing

        do {
            let quotes = try await service.fetch(endpoint)
            table = try await RateStore.mergeInBackground(quotes, into: context.container)
            settings.lastRatesFetch = .now
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Backfills history when a point turns out to predate the cached range.
    func backfillHistory(context: ModelContext, settings: AppSettings) async {
        await refresh(.fullHistory, context: context, settings: settings)
    }
}
