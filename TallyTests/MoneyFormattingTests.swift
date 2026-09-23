import XCTest
@testable import Tally

final class MoneyFormattingTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let swiss = Locale(identifier: "de_CH")
    private let french = Locale(identifier: "fr_FR")

    // MARK: - Pre-filled amounts survive a round trip

    /// The update-all run pre-fills every field; saving an account untouched
    /// must write back exactly the figure it started with, in every locale.
    func testEditableStringParsesBackToTheSameAmount() throws {
        let amounts = ["4000.5", "4000", "-1234.56", "0.01", "1234567.89"].map { Decimal(string: $0)! }

        for locale in [us, german, swiss, french, Locale(identifier: "ja_JP")] {
            for amount in amounts {
                let text = MoneyFormatting.editableString(amount, locale: locale)
                XCTAssertEqual(
                    MoneyFormatting.parse(text, code: "EUR", locale: locale), amount,
                    "\(amount) pre-filled as \"\(text)\" in \(locale.identifier)"
                )
            }
        }
    }

    /// The bug this guards against: `"\(amount)"` writes a `.`, which German
    /// reads as a grouping separator, so 4000.50 came back as 4000.
    func testEditableStringUsesTheLocaleDecimalSeparator() {
        let amount = Decimal(string: "4000.5")!
        XCTAssertEqual(MoneyFormatting.editableString(amount, locale: german), "4000,5")
        XCTAssertEqual(MoneyFormatting.editableString(amount, locale: us), "4000.5")
    }

    func testEditableStringHasNoGroupingOrSymbol() {
        XCTAssertEqual(MoneyFormatting.editableString(1_234_567, locale: us), "1234567")
    }

    // MARK: - Parsing what people type

    func testParseToleratesGroupingSeparators() {
        XCTAssertEqual(MoneyFormatting.parse("1,234.56", code: "EUR", locale: us), Decimal(string: "1234.56"))
        XCTAssertEqual(MoneyFormatting.parse("1.234,56", code: "EUR", locale: german), Decimal(string: "1234.56"))
    }

    func testParseToleratesACurrencySymbolAndWhitespace() {
        XCTAssertEqual(MoneyFormatting.parse("  €1,250  ", code: "EUR", locale: us), 1_250)
        XCTAssertEqual(MoneyFormatting.parse("1.250 €", code: "EUR", locale: german), 1_250)
    }

    func testParseKeepsTheSign() {
        XCTAssertEqual(MoneyFormatting.parse("-250", code: "EUR", locale: us), -250)
    }

    func testParseRejectsEmptyAndNonNumericText() {
        XCTAssertNil(MoneyFormatting.parse("", code: "EUR", locale: us))
        XCTAssertNil(MoneyFormatting.parse("   ", code: "EUR", locale: us))
        XCTAssertNil(MoneyFormatting.parse("abc", code: "EUR", locale: us))
    }

    // MARK: - Display

    func testStringShowsUpToTwoDecimals() {
        XCTAssertEqual(MoneyFormatting.string(1_234, code: "USD", locale: us), "$1,234")
        XCTAssertEqual(MoneyFormatting.string(Decimal(string: "1234.5")!, code: "USD", locale: us), "$1,234.5")
        XCTAssertEqual(MoneyFormatting.string(Decimal(string: "1234.567")!, code: "USD", locale: us), "$1,234.57")
    }

    func testCompactAbbreviatesLargeFiguresForChartAxes() {
        XCTAssertEqual(MoneyFormatting.compact(1_500_000, code: "EUR", locale: us), "1.5M EUR")
        XCTAssertEqual(MoneyFormatting.compact(340_000, code: "EUR", locale: us), "340k EUR")
        XCTAssertEqual(MoneyFormatting.compact(-120_000, code: "EUR", locale: us), "-120k EUR")
    }

    func testCompactFollowsTheGivenLocale() {
        XCTAssertEqual(MoneyFormatting.compact(1_500_000, code: "EUR", locale: german), "1,5M EUR")
    }

    func testCompactLeavesSmallFiguresInFull() {
        XCTAssertEqual(MoneyFormatting.compact(9_999, code: "EUR", locale: us), "€9,999")
    }

    func testSignedChangeAlwaysCarriesItsSign() {
        XCTAssertEqual(MoneyFormatting.signedChange(250, code: "EUR", locale: us), "+€250")
        XCTAssertEqual(MoneyFormatting.signedChange(-250, code: "EUR", locale: us), "−€250")
        XCTAssertEqual(MoneyFormatting.signedChange(0, code: "EUR", locale: us), "€0")
    }
}
