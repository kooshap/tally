import XCTest
@testable import Tally

final class CurrencyFormatTests: XCTestCase {
    func testParsesAPlainNumber() {
        XCTAssertEqual(CurrencyFormat.parse("1200.50"), Decimal(string: "1200.50"))
    }

    func testParsesAGroupedNumber() {
        XCTAssertEqual(CurrencyFormat.parse("1,200"), 1_200)
    }

    func testRejectsEmptyAndNonNumericInput() {
        XCTAssertNil(CurrencyFormat.parse(""))
        XCTAssertNil(CurrencyFormat.parse("   "))
        XCTAssertNil(CurrencyFormat.parse("abc"))
    }

    func testFormatsWithAnExplicitCurrencyCode() {
        let formatted = CurrencyFormat.string(1_234, code: "USD")
        XCTAssertTrue(formatted.contains("1,234") || formatted.contains("1234"))
    }
}
