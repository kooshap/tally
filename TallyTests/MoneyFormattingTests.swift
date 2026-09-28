import XCTest

@testable import Tally

final class MoneyFormattingTests: XCTestCase {
    private let american = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let swiss = Locale(identifier: "de_CH")
    private let french = Locale(identifier: "fr_FR")

    // MARK: - Pre-filled amounts survive a round trip

    /// The update-all run pre-fills every field; saving an account untouched
    /// must write back exactly the figure it started with, in every locale.
    func testEditableStringParsesBackToTheSameAmount() throws {
        let amounts = ["4000.5", "4000", "-1234.56", "0.01", "1234567.89"].map { Decimal(string: $0)! }

        for locale in [american, german, swiss, french, Locale(identifier: "ja_JP")] {
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
        XCTAssertEqual(MoneyFormatting.editableString(amount, locale: german), "4.000,5")
        XCTAssertEqual(MoneyFormatting.editableString(amount, locale: american), "4,000.5")
    }

    func testEditableStringIsGroupedWithoutASymbol() {
        XCTAssertEqual(MoneyFormatting.editableString(1_234_567, locale: american), "1,234,567")
        XCTAssertEqual(MoneyFormatting.editableString(1_234_567, locale: german), "1.234.567")
    }

    // MARK: - Grouping while typing

    private func regrouped(_ text: String, caret: Int? = nil, locale: Locale) -> (text: String, caret: Int) {
        MoneyFormatting.regroupedForTyping(text, caret: caret ?? text.count, locale: locale)
    }

    func testTypingGroupsTheWholeNumber() {
        XCTAssertEqual(regrouped("1234567", locale: american).text, "1,234,567")
        XCTAssertEqual(regrouped("1234567", locale: german).text, "1.234.567")
        XCTAssertEqual(regrouped("123", locale: american).text, "123")
    }

    func testTypingRegroupsAfterADeletion() {
        XCTAssertEqual(regrouped("1,23", locale: american).text, "123")
        XCTAssertEqual(regrouped("12,3456", locale: american).text, "123,456")
    }

    func testTypingKeepsTheSignAndWhatFollowsTheDecimalSeparator() {
        XCTAssertEqual(regrouped("-12345", locale: american).text, "-12,345")
        XCTAssertEqual(regrouped("-", locale: american).text, "-")
        XCTAssertEqual(regrouped("12345.", locale: american).text, "12,345.")
        XCTAssertEqual(regrouped("12345.50", locale: american).text, "12,345.50")
        XCTAssertEqual(regrouped("12345,5", locale: german).text, "12.345,5")
        XCTAssertEqual(regrouped(".5", locale: american).text, ".5")
    }

    func testTypingLeavesAnythingElseAlone() {
        XCTAssertEqual(regrouped("€1250", locale: american).text, "€1250")
        XCTAssertEqual(regrouped("1.2.3", locale: american).text, "1.2.3")
        XCTAssertEqual(regrouped("abc", locale: american).text, "abc")
    }

    func testTypedAmountsStillParse() {
        for (text, locale) in [
            ("1234567.89", american), ("1234567,89", german), ("1234567,89", french), ("1234567.89", swiss),
        ] {
            let typed = regrouped(text, locale: locale).text
            XCTAssertEqual(
                MoneyFormatting.parse(typed, code: "EUR", locale: locale), Decimal(string: "1234567.89"),
                "\"\(typed)\" in \(locale.identifier)"
            )
        }
    }

    func testTheCaretStaysAfterTheDigitItFollowed() {
        // Typing a 5 after the 3 of "123,4": "1235,4" with the caret after the 5.
        XCTAssertEqual(regrouped("1235,4", caret: 4, locale: american).caret, 5)  // "12,35|4"
        // At the end, it stays at the end.
        XCTAssertEqual(regrouped("1234", locale: american).caret, 5)
        // Deleting the 4 of "1,234": "1,23" with the caret at the end.
        XCTAssertEqual(regrouped("1,23", locale: american).caret, 3)
        // At the start, it stays at the start.
        XCTAssertEqual(regrouped("91234", caret: 0, locale: american).caret, 0)
    }

    // MARK: - Parsing what people type

    func testParseToleratesGroupingSeparators() {
        XCTAssertEqual(MoneyFormatting.parse("1,234.56", code: "EUR", locale: american), Decimal(string: "1234.56"))
        XCTAssertEqual(MoneyFormatting.parse("1.234,56", code: "EUR", locale: german), Decimal(string: "1234.56"))
    }

    func testParseToleratesACurrencySymbolAndWhitespace() {
        XCTAssertEqual(MoneyFormatting.parse("  €1,250  ", code: "EUR", locale: american), 1_250)
        XCTAssertEqual(MoneyFormatting.parse("1.250 €", code: "EUR", locale: german), 1_250)
    }

    func testParseKeepsTheSign() {
        XCTAssertEqual(MoneyFormatting.parse("-250", code: "EUR", locale: american), -250)
    }

    func testParseRejectsEmptyAndNonNumericText() {
        XCTAssertNil(MoneyFormatting.parse("", code: "EUR", locale: american))
        XCTAssertNil(MoneyFormatting.parse("   ", code: "EUR", locale: american))
        XCTAssertNil(MoneyFormatting.parse("abc", code: "EUR", locale: american))
    }

    // MARK: - One keystroke at a time

    private func edit(_ text: String, _ range: Range<Int>, _ replacement: String) -> (text: String, caret: Int) {
        MoneyFormatting.applyingEdit(to: text, replacing: range, with: replacement, locale: american)
    }

    func testTypingADigitRegroups() {
        XCTAssertTrue(edit("1,234", 5..<5, "5") == ("12,345", 6))
        XCTAssertTrue(edit("1,234", 1..<1, "9") == ("19,234", 2), "typed after the 1, the caret stays after the 9")
    }

    /// The race the UIKit field exists to avoid: every delete must land.
    func testDeletingEveryCharacterEmptiesTheField() {
        var state = (text: "4,000", caret: 5)
        for _ in 0..<5 where state.caret > 0 {
            state = edit(state.text, (state.caret - 1)..<state.caret, "")
        }
        XCTAssertEqual(state.text, "")
    }

    func testDeletingAGroupingMarkDeletesTheDigitBeforeIt() {
        XCTAssertTrue(edit("1,234", 1..<2, "") == ("234", 0))
        XCTAssertTrue(edit("12,345", 2..<3, "") == ("1,345", 1))
    }

    func testPastingReplacesTheSelection() {
        XCTAssertTrue(edit("1,234", 0..<5, "9876543") == ("9,876,543", 9))
    }

    func testAnEditOutsideTheTextIsClamped() {
        XCTAssertTrue(edit("12", 5..<9, "3") == ("123", 3))
    }

    // MARK: - Display

    func testStringShowsUpToTwoDecimals() {
        XCTAssertEqual(MoneyFormatting.string(1_234, code: "USD", locale: american), "$1,234")
        XCTAssertEqual(MoneyFormatting.string(Decimal(string: "1234.5")!, code: "USD", locale: american), "$1,234.5")
        XCTAssertEqual(MoneyFormatting.string(Decimal(string: "1234.567")!, code: "USD", locale: american), "$1,234.57")
    }

    func testCompactAbbreviatesLargeFiguresForChartAxes() {
        XCTAssertEqual(MoneyFormatting.compact(1_500_000, code: "EUR", locale: american), "1.5M EUR")
        XCTAssertEqual(MoneyFormatting.compact(340_000, code: "EUR", locale: american), "340k EUR")
        XCTAssertEqual(MoneyFormatting.compact(-120_000, code: "EUR", locale: american), "-120k EUR")
    }

    func testCompactFollowsTheGivenLocale() {
        XCTAssertEqual(MoneyFormatting.compact(1_500_000, code: "EUR", locale: german), "1,5M EUR")
    }

    func testCompactLeavesSmallFiguresInFull() {
        XCTAssertEqual(MoneyFormatting.compact(9_999, code: "EUR", locale: american), "€9,999")
    }

    func testSignedChangeAlwaysCarriesItsSign() {
        XCTAssertEqual(MoneyFormatting.signedChange(250, code: "EUR", locale: american), "+€250")
        XCTAssertEqual(MoneyFormatting.signedChange(-250, code: "EUR", locale: american), "−€250")
        XCTAssertEqual(MoneyFormatting.signedChange(0, code: "EUR", locale: american), "€0")
    }
}
