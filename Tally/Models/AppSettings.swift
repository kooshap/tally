import Foundation
import Observation

/// Small, non-record settings. Kept in `UserDefaults` rather than SwiftData so
/// reading the base currency never needs a model context — the formatter and
/// the lock screen both want it before any query runs.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let baseCurrency = "baseCurrency"
        static let faceIDEnabled = "faceIDEnabled"
        static let lastRatesFetch = "lastRatesFetch"
        static let hasCompletedSetup = "hasCompletedSetup"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseCurrency = defaults.string(forKey: Key.baseCurrency) ?? CurrencyCatalog.deviceDefault()
        self.faceIDEnabled = defaults.bool(forKey: Key.faceIDEnabled)
        self.lastRatesFetch = defaults.object(forKey: Key.lastRatesFetch) as? Date
        self.hasCompletedSetup = defaults.bool(forKey: Key.hasCompletedSetup)
    }

    /// Changing this re-prices the whole history from the cached euro-relative
    /// rates; nothing is re-fetched and no past point changes shape.
    var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: Key.baseCurrency) }
    }

    var faceIDEnabled: Bool {
        didSet { defaults.set(faceIDEnabled, forKey: Key.faceIDEnabled) }
    }

    var lastRatesFetch: Date? {
        didSet { defaults.set(lastRatesFetch, forKey: Key.lastRatesFetch) }
    }

    var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: Key.hasCompletedSetup) }
    }

    /// §3: the base currency is chosen once, at first launch.
    func completeSetup(baseCurrency: String) {
        self.baseCurrency = baseCurrency
        hasCompletedSetup = true
    }

    /// §5: refresh at most once a day.
    var needsRateRefresh: Bool {
        guard let lastRatesFetch else { return true }
        return Date.now.timeIntervalSince(lastRatesFetch) > 24 * 60 * 60
    }
}
