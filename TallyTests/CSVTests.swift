import XCTest

@testable import Tally

final class CSVTests: XCTestCase {
    func testPlainValuesAreWrittenAsTheyAre() {
        XCTAssertEqual(CSV.encode([["a", "b"], ["1", "-2.5"]]), "a,b\r\n1,-2.5\r\n")
    }

    func testCommasQuotesAndLineBreaksAreQuoted() {
        XCTAssertEqual(CSV.escape("Smith, J."), "\"Smith, J.\"")
        XCTAssertEqual(CSV.escape("The \"big\" one"), "\"The \"\"big\"\" one\"")
        XCTAssertEqual(CSV.escape("two\nlines"), "\"two\nlines\"")
    }

    func testWhatIsWrittenReadsBack() throws {
        let rows = [["name", "notes"], ["Smith, J.", "The \"big\" one\r\nsecond line"], ["", "=SUM(A1)"]]

        let records = try CSV.decode(CSV.encode(rows))

        XCTAssertEqual(records.map(\.fields), rows)
    }

    func testAcceptsEveryLineEnding() throws {
        for ending in ["\r\n", "\n", "\r"] {
            let records = try CSV.decode(["a,b", "1,2"].joined(separator: ending))
            XCTAssertEqual(records.map(\.fields), [["a", "b"], ["1", "2"]], "ending \(ending.debugDescription)")
        }
    }

    func testSkipsBlankLinesButNotEmptyValues() throws {
        let records = try CSV.decode("a,b\n\n,\n")

        XCTAssertEqual(records.map(\.fields), [["a", "b"], ["", ""]])
    }

    func testRecordsKnowTheLineTheyStartOn() throws {
        let records = try CSV.decode("a\r\n\"one\r\ntwo\"\r\n\r\nb\r\n")

        XCTAssertEqual(records.map(\.line), [1, 2, 5])
    }

    func testAnUnclosedQuoteIsAnError() {
        XCTAssertThrowsError(try CSV.decode("a\n\"open,\nnever closed")) { error in
            XCTAssertEqual(error as? CSV.UnclosedQuote, CSV.UnclosedQuote(line: 2))
        }
    }
}
