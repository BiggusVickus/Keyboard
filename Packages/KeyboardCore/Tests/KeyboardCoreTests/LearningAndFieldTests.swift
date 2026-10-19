import XCTest
@testable import KeyboardCore

final class LearningLogTests: XCTestCase {
    private func makeStore() -> LearningLogStore {
        LearningLogStore(defaults: UserDefaults(suiteName: "LearningLog-\(UUID())")!)
    }

    private func entry(_ topic: GrammarTopic, _ original: String, minutesAgo: Double = 0) -> LearningEntry {
        LearningEntry(date: Date(timeIntervalSinceNow: -minutesAgo * 60), language: .dutch, topic: topic,
                      original: original, corrected: "fixed \(original)", explanation: "", sentence: "")
    }

    func testAddLoadNewestFirst() {
        let store = makeStore()
        store.add(entry(.articles, "het auto", minutesAgo: 10))
        store.add(entry(.wordOrder, "ik ga morgen"))
        XCTAssertEqual(store.load().map(\.original), ["ik ga morgen", "het auto"])
    }

    func testSameFixTwiceInARowCountsOnce() {
        let store = makeStore()
        store.add(entry(.articles, "het auto"))
        store.add(entry(.articles, "het auto"))
        XCTAssertEqual(store.load().count, 1)
    }

    func testRemoveAndClear() {
        let store = makeStore()
        let first = entry(.articles, "a", minutesAgo: 5)
        store.add(first)
        store.add(entry(.articles, "b"))
        store.remove(ids: [first.id])
        XCTAssertEqual(store.load().map(\.original), ["b"])
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testSummaryCountsPerTopic() {
        let entries = [entry(.articles, "a"), entry(.articles, "b"), entry(.wordOrder, "c")]
        let summary = LearningLogStore.summary(of: entries)
        XCTAssertEqual(summary.map(\.topic), [.articles, .wordOrder])
        XCTAssertEqual(summary.first?.count, 2)
    }

    func testOldSettingsGetNewDefaults() throws {
        let settings = try JSONDecoder().decode(TaalhulpSettings.self, from: Data(#"{"currentLanguage":"de"}"#.utf8))
        XCTAssertTrue(settings.keepLearningLog)
        XCTAssertEqual(settings.translateFrom, .english)
        XCTAssertEqual(settings.translateTo, .dutch)
    }
}

final class FieldTraitsTests: XCTestCase {
    func testEmailFieldsGetAtAndDot() {
        let layout = KeyboardLayout.make(language: .dutch, page: .letters, showsGlobe: false, field: .email)
        let bottom = layout.rows.last!.compactMap(\.character)
        XCTAssertEqual(bottom, ["@", "."])
        let ids = layout.rows.flatMap { $0 }.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testTextFieldsOnlyGetAPeriod() {
        let layout = KeyboardLayout.make(language: .dutch, page: .letters, showsGlobe: false)
        XCTAssertEqual(layout.rows.last!.compactMap(\.character), ["."])
    }

    func testReturnKeyLabels() {
        XCTAssertNil(ReturnKeyStyle.default.label(for: .dutch))
        XCTAssertEqual(ReturnKeyStyle.send.label(for: .dutch), "Stuur")
        XCTAssertEqual(ReturnKeyStyle.search.label(for: .german), "Suchen")
        XCTAssertTrue(ReturnKeyStyle.send.isProminent)
        XCTAssertFalse(ReturnKeyStyle.next.isProminent)
    }

    func testLanguageHelpOnlyForText() {
        XCTAssertTrue(FieldTraits().wantsLanguageHelp)
        XCTAssertFalse(FieldTraits(kind: .email).wantsLanguageHelp)
        XCTAssertFalse(FieldTraits(kind: .url).wantsLanguageHelp)
        XCTAssertFalse(FieldTraits(allowsAutocorrection: false).wantsLanguageHelp)
    }
}
