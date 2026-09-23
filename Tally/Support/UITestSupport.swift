import Foundation
import SwiftData

/// Launch-argument hooks so the UI test starts from a known portfolio.
///
/// Only active when the argument is passed, which Xcode's UI test runner does
/// and the App Store build never can.
enum UITestSupport {
    static let resetArgument = "-uiTestingReset"

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains(resetArgument)
    }

    /// A throwaway defaults suite, so a test run cannot disturb real settings.
    static func makeSettings() -> AppSettings {
        guard isRunningUITests else { return AppSettings() }

        let suite = UserDefaults(suiteName: "tally.uitests")!
        suite.removePersistentDomain(forName: "tally.uitests")

        let settings = AppSettings(defaults: suite)
        settings.baseCurrency = "EUR"
        settings.faceIDEnabled = false
        settings.hasCompletedSetup = true
        return settings
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isRunningUITests)
        return try ModelContainer(
            for: Account.self, BalanceEntry.self, FXRate.self,
            configurations: configuration
        )
    }

    /// Two accounts with a known last balance, which is what the update flow
    /// pre-fills from.
    @MainActor
    static func seed(_ container: ModelContainer) {
        guard isRunningUITests else { return }
        let context = container.mainContext
        let day = CalendarDay.today()

        let current = Account(name: "Current account", type: .bank, currencyCode: "EUR", sortOrder: 0)
        let mortgage = Account(name: "Mortgage", type: .debt, currencyCode: "EUR", sortOrder: 1)
        context.insert(current)
        context.insert(mortgage)

        BalanceStore.record(4_000, on: day, for: current, in: context)
        BalanceStore.record(300_000, on: day, for: mortgage, in: context)

        try? context.save()
    }
}
