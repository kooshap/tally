import XCTest
@testable import Tally

final class AccountTests: XCTestCase {
    func testCurrentValueIsZeroBeforeAnySnapshot() {
        let account = Account(name: "Chequing", kind: .cash)
        XCTAssertEqual(account.currentValue, 0)
        XCTAssertNil(account.latestSnapshot)
    }

    func testCurrentValueTracksTheMostRecentSnapshotNotTheLastAdded() {
        let account = Account(name: "Brokerage", kind: .investment)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = old.addingTimeInterval(86_400 * 30)

        _ = account.record(50_000, on: recent)
        _ = account.record(41_000, on: old)

        XCTAssertEqual(account.currentValue, 50_000)
    }

    func testHistoryIsOldestFirst() {
        let account = Account(name: "Mortgage", kind: .mortgage)
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(86_400)

        _ = account.record(400_000, on: second)
        _ = account.record(405_000, on: first)

        XCTAssertEqual(account.history.map(\.amount), [405_000, 400_000])
    }

    func testKindRoundTripsThroughItsRawValue() {
        let account = Account(name: "Car loan", kind: .cash)
        account.kind = .loan

        XCTAssertEqual(account.kindRawValue, "loan")
        XCTAssertTrue(account.kind.isLiability)
    }

    func testUnknownStoredKindFallsBackInsteadOfCrashing() {
        let account = Account(name: "From a newer build", kind: .cash)
        account.kindRawValue = "crypto"

        XCTAssertEqual(account.kind, .otherAsset)
        XCTAssertFalse(account.kind.isLiability)
    }
}
