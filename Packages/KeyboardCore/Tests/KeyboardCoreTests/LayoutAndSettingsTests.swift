import XCTest
@testable import KeyboardCore

final class LayoutTests: XCTestCase {
    private func characters(_ layout: KeyboardLayout) -> [String] {
        layout.rows.flatMap { $0 }.compactMap {
            if case .character(let c) = $0.kind { return c }
            return nil
        }
    }

    func testGermanHasUmlautsAndQwertz() {
        let layout = KeyboardLayout.make(language: .german, page: .letters, showsGlobe: false)
        let chars = characters(layout)
        XCTAssertTrue(chars.contains("ü"))
        XCTAssertTrue(chars.contains("ö"))
        XCTAssertTrue(chars.contains("ä"))
        XCTAssertEqual(chars[5], "z", "QWERTZ: z is the 6th key")
    }

    func testDutchIsQwertyWithAccentsOnLongPress() {
        let layout = KeyboardLayout.make(language: .dutch, page: .letters, showsGlobe: false)
        XCTAssertEqual(characters(layout)[5], "y")
        let e = layout.rows[0].first { $0.kind == .character("e") }
        XCTAssertEqual(e?.alternates.first, "é")
        XCTAssertTrue(e?.alternates.contains("ë") ?? false)
    }

    func testGlobeKeyOnlyWhenNeeded() {
        let without = KeyboardLayout.make(language: .english, page: .letters, showsGlobe: false)
        let with = KeyboardLayout.make(language: .english, page: .letters, showsGlobe: true)
        XCTAssertFalse(without.rows.last!.contains { $0.kind == .globe })
        XCTAssertTrue(with.rows.last!.contains { $0.kind == .globe })
    }

    func testEveryPageHasDeleteSpaceAndReturn() {
        for language in KeyboardLanguage.allCases {
            for page in [KeyboardPage.letters, .numbers, .symbols] {
                let kinds = KeyboardLayout.make(language: language, page: page, showsGlobe: true)
                    .rows.flatMap { $0 }.map(\.kind)
                XCTAssertTrue(kinds.contains(.delete))
                XCTAssertTrue(kinds.contains(.space))
                XCTAssertTrue(kinds.contains(.returnKey))
                XCTAssertTrue(kinds.contains(.languageSwitch))
            }
        }
    }

    func testKeyIDsAreUnique() {
        let layout = KeyboardLayout.make(language: .dutch, page: .numbers, showsGlobe: true)
        let ids = layout.rows.flatMap { $0 }.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTrip() {
        let defaults = UserDefaults(suiteName: "SettingsTests-\(UUID())")!
        let store = SettingsStore(defaults: defaults)

        var settings = TaalhulpSettings()
        settings.grammarLevel = .polish
        settings.aiProvider = .local
        settings.claudeModel = "claude-haiku-5-5"
        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testMissingKeysUseDefaults() throws {
        // Settings saved by an older version that only knew two keys.
        let json = #"{"currentLanguage":"de","autocorrect":"off"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(TaalhulpSettings.self, from: json)
        XCTAssertEqual(settings.currentLanguage, .german)
        XCTAssertEqual(settings.autocorrect, .off)
        XCTAssertEqual(settings.claudeModel, ClaudeModelOption.defaultID)
        XCTAssertEqual(settings.grammarLevel, .errorsAndImprovements)
    }

    func testNextLanguageWrapsAround() {
        var settings = TaalhulpSettings()
        settings.enabledLanguages = [.dutch, .german]
        settings.currentLanguage = .dutch
        XCTAssertEqual(settings.nextLanguage(), .german)
        settings.currentLanguage = .german
        XCTAssertEqual(settings.nextLanguage(), .dutch)
    }
}
