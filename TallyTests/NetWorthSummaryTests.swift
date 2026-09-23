import XCTest
@testable import Tally

final class NetWorthSummaryTests: XCTestCase {
    func testEmptyPortfolioIsZero() {
        let summary = NetWorthSummary(entries: [])
        XCTAssertEqual(summary.assets, 0)
        XCTAssertEqual(summary.liabilities, 0)
        XCTAssertEqual(summary.net, 0)
    }

    func testAssetsAndLiabilitiesAccumulateSeparately() {
        let summary = NetWorthSummary(entries: [
            .init(amount: 12_000, isLiability: false),
            .init(amount: 480_000, isLiability: false),
            .init(amount: 395_000, isLiability: true),
            .init(amount: 2_400, isLiability: true)
        ])

        XCTAssertEqual(summary.assets, 492_000)
        XCTAssertEqual(summary.liabilities, 397_400)
        XCTAssertEqual(summary.net, 94_600)
    }

    func testNetWorthCanBeNegative() {
        let summary = NetWorthSummary(entries: [
            .init(amount: 1_000, isLiability: false),
            .init(amount: 31_000, isLiability: true)
        ])

        XCTAssertEqual(summary.net, -30_000)
    }

    func testDecimalArithmeticDoesNotDriftLikeBinaryFloatingPoint() {
        let summary = NetWorthSummary(entries: (0..<10).map { _ in
            .init(amount: Decimal(string: "0.1")!, isLiability: false)
        })

        XCTAssertEqual(summary.assets, Decimal(string: "1.0"))
    }
}
