import Foundation

/// RFC 4180 comma-separated values: the container of the backup file.
enum CSV {
    struct Record: Equatable {
        /// The line the record starts on, counting from 1, which is the row
        /// number a spreadsheet shows when no value spans lines.
        let line: Int
        let fields: [String]
    }

    /// A quoted value runs to the end of the file.
    struct UnclosedQuote: Error, Equatable {
        let line: Int
    }

    /// One line per row, each ending in CRLF as the RFC asks.
    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") + "\r\n" }.joined()
    }

    /// Quotes a value only when it needs it: one holding a comma, a quote or
    /// a line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Splits `text` into records. Accepts CRLF, LF or CR line endings, and
    /// skips blank lines.
    static func decode(_ text: String) throws(UnclosedQuote) -> [Record] {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        while !parser.isAtEnd {
            parser.step()
        }
        if parser.isQuoted {
            throw UnclosedQuote(line: parser.recordLine)
        }
        parser.endRecord()
        return parser.records
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        private(set) var records: [Record] = []
        private(set) var recordLine = 1
        private(set) var isQuoted = false
        private var index = 0
        private var line = 1
        private var fields: [String] = []
        private var field = String.UnicodeScalarView()

        init(scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        var isAtEnd: Bool { index >= scalars.count }

        private var next: Unicode.Scalar? {
            index + 1 < scalars.count ? scalars[index + 1] : nil
        }

        mutating func step() {
            if isQuoted {
                stepQuoted()
            } else {
                stepUnquoted()
            }
            index += 1
        }

        private mutating func stepQuoted() {
            let scalar = scalars[index]
            if scalar == "\"" {
                if next == "\"" {
                    field.append(scalar)
                    index += 1
                } else {
                    isQuoted = false
                }
                return
            }
            // A CRLF is one line break, counted at its LF.
            if scalar == "\n" || (scalar == "\r" && next != "\n") {
                line += 1
            }
            field.append(scalar)
        }

        private mutating func stepUnquoted() {
            let scalar = scalars[index]
            switch scalar {
            case "\"" where field.isEmpty:
                isQuoted = true
            case ",":
                endField()
            case "\r", "\n":
                if scalar == "\r", next == "\n" {
                    index += 1
                }
                endRecord()
                line += 1
                recordLine = line
            default:
                field.append(scalar)
            }
        }

        private mutating func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }

        mutating func endRecord() {
            endField()
            if fields != [""] {
                records.append(Record(line: recordLine, fields: fields))
            }
            fields = []
        }
    }
}
