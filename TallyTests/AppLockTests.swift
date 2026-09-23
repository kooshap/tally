import XCTest
@testable import Tally

/// The gate's state machine. `authenticate` itself goes to LocalAuthentication
/// and is left to the device.
@MainActor
final class AppLockTests: XCTestCase {
    func testNothingIsLockedWhileTheSettingIsOff() {
        XCTAssertFalse(AppLock().isLocked(enabled: false))
    }

    func testStartsLockedWhenTheSettingIsOn() {
        XCTAssertTrue(AppLock().isLocked(enabled: true))
    }

    func testRelocksAfterBeingUnlocked() {
        let lock = AppLock()
        lock.unlockWithoutAuthenticating()
        XCTAssertFalse(lock.isLocked(enabled: true))

        lock.lock()

        XCTAssertTrue(lock.isLocked(enabled: true))
    }
}
