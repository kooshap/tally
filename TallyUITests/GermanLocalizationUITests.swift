import XCTest

/// Walks the app in German and fails if any screen shows a string the catalog
/// translates in its English form: the sign that SwiftUI looked up a key the
/// catalog doesn't have — an interpolation that formats as `%@` where the
/// catalog says `%lld`, say — and fell back to the source text.
@MainActor
final class GermanLocalizationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingReset", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    func testUpdateAllCountsAccountsInGerman() throws {
        app.tabBars.buttons["Konten"].tap()
        app.buttons["Alle Kontostände aktualisieren"].tap()

        XCTAssertTrue(app.staticTexts["Konto 1 von 2"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "update all, first account")

        app.buttons["updateAll.nextButton"].tap()
        XCTAssertTrue(app.staticTexts["Konto 2 von 2"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "update all, second account")

        app.buttons["updateAll.nextButton"].tap()
        XCTAssertTrue(app.buttons["updateAll.saveButton"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "update all, review")
    }

    func testNoScreenFallsBackToEnglish() throws {
        XCTAssertTrue(app.tabBars.buttons["Vermögen"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "dashboard")

        app.tabBars.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "settings")

        app.tabBars.buttons["Konten"].tap()
        XCTAssertTrue(app.buttons["Alle Kontostände aktualisieren"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "accounts")

        app.staticTexts["Current account"].tap()
        let delete = app.buttons["Konto löschen"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "account detail")

        app.buttons["Bearbeiten"].tap()
        let lockedFooter = app.staticTexts["account.lockedFooter"]
        XCTAssertTrue(lockedFooter.waitForExistence(timeout: 5))
        XCTAssertTrue(lockedFooter.label.hasPrefix("Währung und Art"), "locked footer reads \"\(lockedFooter.label)\"")
        try assertNoEnglishFallback(on: "edit account")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(lockedFooter.waitForNonExistence(timeout: 5))

        delete.tap()
        XCTAssertTrue(app.staticTexts["Dieses Konto löschen?"].waitForExistence(timeout: 5))
        try assertNoEnglishFallback(on: "delete confirmation")
    }

    // MARK: - Checking a screen

    private func assertNoEnglishFallback(
        on screen: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let patterns = try Self.englishPatterns()
        var fallbacks: [String] = []
        for text in try Self.texts(in: app.snapshot()) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = patterns.first(where: { $0.regex.firstMatch(in: text, range: range) != nil }) {
                fallbacks.append("\"\(text)\" (key \"\(match.key)\")")
            }
        }
        XCTAssertTrue(
            fallbacks.isEmpty, "English on the \(screen) screen: \(fallbacks.joined(separator: ", "))",
            file: file, line: line)
    }

    private static func texts(in snapshot: XCUIElementSnapshot) -> [String] {
        let own = [snapshot.label, snapshot.title, snapshot.placeholderValue ?? "", snapshot.value as? String ?? ""]
        return own.filter { !$0.isEmpty } + snapshot.children.flatMap(texts(in:))
    }

    // MARK: - The catalog

    /// Each source string with a German translation that differs from it, as a
    /// whole-label pattern where every placeholder or inflected phrase matches
    /// anything.
    private static func englishPatterns() throws -> [(key: String, regex: NSRegularExpression)] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings should be copied into the UI test bundle")
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))

        let hole = "\u{E000}"
        let placeholders = try NSRegularExpression(pattern: #"\^\[[^\]]*\]\(inflect: true\)|%(\d+\$)?(lld|ld|d|@)"#)
        return try catalog.strings.compactMap { key, entry in
            guard let german = entry.localizations?["de"]?.stringUnit?.value, german != key else { return nil }
            let holed = placeholders.stringByReplacingMatches(
                in: key, range: NSRange(key.startIndex..., in: key), withTemplate: hole)
            let pattern = NSRegularExpression.escapedPattern(for: holed).replacingOccurrences(of: hole, with: ".+")
            return (key, try NSRegularExpression(pattern: "^\(pattern)$"))
        }
    }
}

/// The parts of `Localizable.xcstrings` the check reads.
private struct StringCatalog: Decodable {
    struct Entry: Decodable {
        let localizations: [String: Localization]?
    }
    struct Localization: Decodable {
        let stringUnit: StringUnit?
    }
    struct StringUnit: Decodable {
        let value: String
    }
    let strings: [String: Entry]
}
