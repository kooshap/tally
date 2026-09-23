import Foundation
import LocalAuthentication

/// Optional Face ID / passcode gate, off by default.
///
/// Uses `deviceOwnerAuthentication` rather than the biometrics-only policy, so
/// the device passcode works when Face ID fails or isn't enrolled — otherwise a
/// failed scan would lock someone out of their own data with no way back in.
@MainActor
@Observable
final class AppLock {
    private(set) var isUnlocked = false
    private(set) var lastFailure: String?

    /// True when the app should be hidden in the switcher and behind a gate.
    func isLocked(enabled: Bool) -> Bool {
        enabled && !isUnlocked
    }

    func unlockWithoutAuthenticating() {
        isUnlocked = true
    }

    func lock() {
        isUnlocked = false
    }

    func authenticate(reason: String) async {
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device: there is nothing to authenticate
            // against, so gating would strand the data.
            isUnlocked = true
            lastFailure = error?.localizedDescription
            return
        }

        do {
            isUnlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastFailure = nil
        } catch {
            isUnlocked = false
            lastFailure = error.localizedDescription
        }
    }

    /// Whether the device can gate at all, for the Settings toggle.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}
