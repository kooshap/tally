import Foundation
import LocalAuthentication
import SwiftUI

/// The parts of `LAContext` the lock uses, so tests can stand in for the device.
protocol DeviceOwnerAuthenticating: AnyObject {
    var localizedFallbackTitle: String? { get set }
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool
}

extension LAContext: DeviceOwnerAuthenticating {}

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

    /// A fresh context per attempt, as LocalAuthentication expects.
    private let makeContext: () -> any DeviceOwnerAuthenticating

    init(makeContext: @escaping () -> any DeviceOwnerAuthenticating = { LAContext() }) {
        self.makeContext = makeContext
    }

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

    /// Re-locks on leaving the app, not on a passing interruption like a
    /// notification banner, which only makes the scene inactive.
    func sceneDidChange(to phase: ScenePhase, enabled: Bool) {
        if phase == .background, enabled {
            lock()
        }
    }

    /// Whether to cover the balances, which is whenever the lock is on and the
    /// app isn't in front — including in the app switcher.
    static func hidesContent(enabled: Bool, phase: ScenePhase) -> Bool {
        enabled && phase != .active
    }

    func authenticate(reason: String) async {
        let context = makeContext()
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
