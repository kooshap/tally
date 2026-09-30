import XCTest

@testable import Tally

final class AxisTicksTests: XCTestCase {
    private let american = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    // MARK: - Ticks

    func testTicksAreRoundStepsInsideTheRange() {
        let ticks = AxisTicks(from: 171_500, to: 312_900)

        XCTAssertEqual(ticks.step, 50_000)
        XCTAssertEqual(ticks.values, [200_000, 250_000, 300_000])
    }

    func testANarrowRangeGetsASmallStep() {
        let ticks = AxisTicks(from: 15_050, to: 15_600)

        XCTAssertEqual(ticks.step, 200)
        XCTAssertEqual(ticks.values, [15_200, 15_400, 15_600])
    }

    func testStepsCanBeTwoAndAHalfTimesAPowerOfTen() {
        let ticks = AxisTicks(from: 0, to: 9_000)

        XCTAssertEqual(ticks.step, 2_500)
        XCTAssertEqual(ticks.values, [0, 2_500, 5_000, 7_500])
    }

    func testNegativeRangesStartAtTheFirstTickInside() {
        let ticks = AxisTicks(from: -1_300, to: 1_700)

        XCTAssertEqual(ticks.step, 1_000)
        XCTAssertEqual(ticks.values, [-1_000, 0, 1_000])
    }

    func testFractionalRanges() {
        let ticks = AxisTicks(from: decimal("0.95"), to: decimal("1.15"))

        XCTAssertEqual(ticks.step, decimal("0.05"))
        XCTAssertEqual(ticks.values.first, decimal("0.95"))
        XCTAssertEqual(ticks.values.last, decimal("1.15"))
    }

    func testAnEmptyRangeIsOneTick() {
        let ticks = AxisTicks(from: 500, to: 500)

        XCTAssertEqual(ticks.values, [500])
        XCTAssertEqual(ticks.step, 0)
    }

    // MARK: - Labels

    private func labels(from low: Decimal, to high: Decimal, locale: Locale) -> [String] {
        MoneyFormatting.axisLabels(AxisTicks(from: low, to: high), code: "EUR", locale: locale)
    }

    func testLargeAmountsAreInThousands() {
        XCTAssertEqual(
            labels(from: 171_500, to: 312_900, locale: american), ["200k EUR", "250k EUR", "300k EUR"])
        XCTAssertEqual(
            labels(from: 171_500, to: 312_900, locale: german), ["200k EUR", "250k EUR", "300k EUR"])
    }

    /// The reason the labels need the step: rounded to whole thousands,
    /// these would all read "15k EUR".
    func testNeighbouringLabelsNeverReadAlike() {
        let shown = labels(from: 15_050, to: 15_600, locale: american)

        XCTAssertEqual(shown, ["15.2k EUR", "15.4k EUR", "15.6k EUR"])
        XCTAssertEqual(Set(shown).count, shown.count)
    }

    func testAHalfStepGetsOneDecimalInTheLocalesSeparator() {
        XCTAssertEqual(
            labels(from: 261_000, to: 268_000, locale: german), ["262k EUR", "264k EUR", "266k EUR", "268k EUR"])
        XCTAssertEqual(
            labels(from: 260_000, to: 270_000, locale: german).dropFirst().first, "262,5k EUR")
    }

    func testMillionsOnlyWhenTheStepIsLargeEnough() {
        XCTAssertEqual(
            labels(from: 900_000, to: 1_700_000, locale: american), ["1.0M EUR", "1.2M EUR", "1.4M EUR", "1.6M EUR"])
        XCTAssertEqual(labels(from: 1_010_000, to: 1_040_000, locale: american).first, "1,010k EUR")
    }

    func testSmallAmountsAreWrittenOut() {
        XCTAssertEqual(
            labels(from: 3_100, to: 6_700, locale: american), ["€4,000", "€5,000", "€6,000"])
        XCTAssertEqual(
            labels(from: 3_100, to: 6_700, locale: german), ["4.000\u{A0}€", "5.000\u{A0}€", "6.000\u{A0}€"])
    }

    func testZeroCarriesNoUnit() {
        XCTAssertEqual(
            labels(from: -130_000, to: 170_000, locale: american), ["-100k EUR", "0 EUR", "100k EUR"])
    }
}
