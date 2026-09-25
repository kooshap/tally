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

    /// The app is only hosting the unit-test bundle. The tests build their own
    /// in-memory containers, so the app itself should open no store and
    /// download nothing while they run.
    static var isHostingUnitTests: Bool {
        !isRunningUITests
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        // Together with the rate `seed` writes, this means the run finds a
        // fresh cache and never goes to the network.
        settings.lastRatesFetch = .now
        return settings
    }

    static func makeContainer() throws -> ModelContainer {
        let inMemory = isRunningUITests || isHostingUnitTests
        let container = try TallyStore.makeContainer(inMemory: inMemory)
        seed(container)
        return container
    }

    /// Two accounts with a known last balance, which is what the update flow
    /// pre-fills from. Written before the first frame, so no view can see an
    /// empty store and act on it.
    static func seed(_ container: ModelContainer) {
        guard isRunningUITests else { return }
        let context = ModelContext(container)
        let day = CalendarDay.today()

        let current = Account(name: "Current account", type: .bank, currencyCode: "EUR", sortOrder: 0)
        let mortgage = Account(name: "Mortgage", type: .debt, currencyCode: "EUR", sortOrder: 1)
        context.insert(current)
        context.insert(mortgage)

        BalanceStore.record(4_000, on: day, for: current, in: context)
        BalanceStore.record(300_000, on: day, for: mortgage, in: context)
        context.insert(FXRate(day: day, currencyCode: "USD", unitsPerEUR: 1.1))

        try? context.save()
    }
}
