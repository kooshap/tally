import LocalAuthentication
import XCTest

@testable import Tally

/// Stands in for Face ID and the passcode prompt.
private final class FakeDevice: DeviceOwnerAuthenticating {
    var localizedFallbackTitle: String?
    var hasPasscode = true
    var outcome: Result<Bool, any Error> = .success(true)
    private(set) var policies: [LAPolicy] = []
    private(set) var reasons: [String] = []

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        if !hasPasscode {
            error?.pointee = LAError(.passcodeNotSet) as NSError
        }
        return hasPasscode
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        policies.append(policy)
        reasons.append(localizedReason)
        return try outcome.get()
    }
}

/// The gate's state machine, with the device replaced by `FakeDevice`.
@MainActor
final class AppLockTests: XCTestCase {
    private var device: FakeDevice!
    private var lock: AppLock!

    override func setUp() async throws {
        let device = FakeDevice()
        self.device = device
        lock = AppLock(makeContext: { device })
    }

    override func tearDown() async throws {
        device = nil
        lock = nil
    }

    func testNothingIsLockedWhileTheSettingIsOff() {
        XCTAssertFalse(lock.isLocked(enabled: false))
    }

    func testStartsLockedWhenTheSettingIsOn() {
        XCTAssertTrue(lock.isLocked(enabled: true))
    }

    func testRelocksAfterBeingUnlocked() {
        lock.unlockWithoutAuthenticating()
        XCTAssertFalse(lock.isLocked(enabled: true))

        lock.lock()

        XCTAssertTrue(lock.isLocked(enabled: true))
    }

    // MARK: - Authenticating

    func testASuccessfulScanUnlocks() async {
        await lock.authenticate(reason: "Unlock Tally")

        XCTAssertFalse(lock.isLocked(enabled: true))
        XCTAssertNil(lock.lastFailure)
        XCTAssertEqual(device.reasons, ["Unlock Tally"])
    }

    /// §6: the passcode must work when Face ID doesn't, which the
    /// biometrics-only policy would not allow.
    func testAsksForTheOwnerSoThePasscodeIsAFallback() async {
        await lock.authenticate(reason: "Unlock Tally")

        XCTAssertEqual(device.policies, [.deviceOwnerAuthentication])
    }

    func testACancelledPromptStaysLockedAndSaysWhy() async {
        device.outcome = .failure(LAError(.userCancel))

        await lock.authenticate(reason: "Unlock Tally")

        XCTAssertTrue(lock.isLocked(enabled: true))
        XCTAssertNotNil(lock.lastFailure)
    }

    func testASuccessClearsAnEarlierFailure() async {
        device.outcome = .failure(LAError(.authenticationFailed))
        await lock.authenticate(reason: "Unlock Tally")

        device.outcome = .success(true)
        await lock.authenticate(reason: "Unlock Tally")

        XCTAssertFalse(lock.isLocked(enabled: true))
        XCTAssertNil(lock.lastFailure)
    }

    /// With no passcode on the phone there is nothing to check against, and
    /// gating anyway would lock the owner out of their own data for good.
    func testAPhoneWithNoPasscodeIsLetInRatherThanStranded() async {
        device.hasPasscode = false

        await lock.authenticate(reason: "Unlock Tally")

        XCTAssertFalse(lock.isLocked(enabled: true))
        XCTAssertNotNil(lock.lastFailure)
        XCTAssertTrue(device.reasons.isEmpty, "no prompt is shown")
    }

    // MARK: - Leaving the app

    func testGoingToTheBackgroundRelocks() {
        lock.unlockWithoutAuthenticating()

        lock.sceneDidChange(to: .background, enabled: true)

        XCTAssertTrue(lock.isLocked(enabled: true))
    }

    /// A notification banner or Control Center only makes the scene inactive,
    /// and asking for Face ID again after each would be maddening.
    func testAPassingInterruptionDoesNotRelock() {
        lock.unlockWithoutAuthenticating()

        lock.sceneDidChange(to: .inactive, enabled: true)

        XCTAssertFalse(lock.isLocked(enabled: true))
    }

    func testNothingRelocksWhileTheSettingIsOff() {
        lock.unlockWithoutAuthenticating()

        lock.sceneDidChange(to: .background, enabled: false)

        XCTAssertTrue(lock.isUnlocked)
    }

    /// §6: balances are hidden in the app switcher whenever the lock is on.
    func testContentIsHiddenWheneverTheLockIsOnAndTheAppIsNotInFront() {
        XCTAssertTrue(AppLock.hidesContent(enabled: true, phase: .inactive))
        XCTAssertTrue(AppLock.hidesContent(enabled: true, phase: .background))
        XCTAssertFalse(AppLock.hidesContent(enabled: true, phase: .active))
        XCTAssertFalse(AppLock.hidesContent(enabled: false, phase: .background))
    }
}
