import XCTest
@testable import KeyboardCore

/// A tiny dictionary standing in for UITextChecker.
final class FakeSpellChecker: SpellChecking {
    var words: Set<String>
    var guesses: [String: [String]]

    init(words: Set<String>, guesses: [String: [String]] = [:]) {
        self.words = words
        self.guesses = guesses
    }

    func isKnown(_ word: String, language: KeyboardLanguage) -> Bool { words.contains(word) }

    func corrections(for word: String, language: KeyboardLanguage) -> [String] {
        guesses[word.lowercased()] ?? []
    }

    func completions(for prefix: String, language: KeyboardLanguage) -> [String] {
        words.filter { $0.hasPrefix(prefix.lowercased()) && $0 != prefix.lowercased() }.sorted()
    }
}

final class AutocorrectorTests: XCTestCase {
    private func makeCorrector(mode: AutocorrectMode = .automatic) -> Autocorrector {
        let checker = FakeSpellChecker(
            words: ["thuis", "the", "dat", "dag", "huis", "hallo"],
            guesses: ["thuiz": ["thuis"], "teh": ["the"], "dta": ["dat"], "hlalo": ["hallo"],
                      "xyzzyq": ["fizz"], "thuisz": ["thuis z", "thuis"]])
        let corrector = Autocorrector(checker: checker)
        corrector.mode = mode
        corrector.language = .dutch
        return corrector
    }

    func testFixesClearTypo() {
        XCTAssertEqual(makeCorrector().autocorrection(for: "thuiz"), "thuis")
        XCTAssertEqual(makeCorrector().autocorrection(for: "hlalo"), "hallo", "a swap counts as one edit")
    }

    func testLeavesKnownWordsAlone() {
        XCTAssertNil(makeCorrector().autocorrection(for: "thuis"))
        XCTAssertNil(makeCorrector().autocorrection(for: "Thuis"), "known with a capital at sentence start")
    }

    func testKeepsCapitalisation() {
        XCTAssertEqual(makeCorrector().autocorrection(for: "Thuiz"), "Thuis")
    }

    func testIgnoresFarGuessesAndSplits() {
        XCTAssertNil(makeCorrector().autocorrection(for: "xyzzyq"), "guess too different")
        XCTAssertEqual(makeCorrector().autocorrection(for: "thuisz"), "thuis", "skips the split suggestion")
    }

    func testSkipsAcronymsDigitsAndSingleLetters() {
        let corrector = makeCorrector()
        XCTAssertNil(corrector.autocorrection(for: "THUIZ"))
        XCTAssertNil(corrector.autocorrection(for: "thuiz2"))
        XCTAssertNil(corrector.autocorrection(for: "q"))
    }

    func testLearnedWordsAreNeverCorrected() {
        let corrector = makeCorrector()
        corrector.learnedWords = [.dutch: ["thuiz"]]
        XCTAssertNil(corrector.autocorrection(for: "thuiz"))
    }

    func testSuggestOnlyNeverAutocorrects() {
        let corrector = makeCorrector(mode: .suggestOnly)
        XCTAssertNil(corrector.autocorrection(for: "thuiz"))
        let suggestions = corrector.suggestions(for: "thuiz")
        XCTAssertEqual(suggestions.first?.kind, .typed)
        XCTAssertTrue(suggestions.contains { $0.text == "thuis" && !$0.isAutocorrection })
    }

    func testOffShowsNothing() {
        XCTAssertTrue(makeCorrector(mode: .off).suggestions(for: "thuiz").isEmpty)
    }

    func testSuggestionBarForTypo() {
        let suggestions = makeCorrector().suggestions(for: "thuiz")
        XCTAssertEqual(suggestions.map(\.text), ["thuiz", "thuis"])
        XCTAssertEqual(suggestions[1].isAutocorrection, true)
    }

    func testCompletionsForKnownPrefix() {
        let suggestions = makeCorrector().suggestions(for: "hu")
        XCTAssertTrue(suggestions.contains { $0.text == "huis" && $0.kind == .completion })
        XCTAssertLessThanOrEqual(suggestions.count, Autocorrector.maxSuggestions)
    }

    func testUndoOffersOriginal() {
        let last = Autocorrection(original: "thuiz", replacement: "thuis")
        let suggestions = makeCorrector().suggestions(for: "thuis", undoing: last)
        XCTAssertEqual(suggestions.first, Suggestion(text: "thuiz", kind: .revert))
    }

    func testEnglishCommonFixes() {
        let corrector = makeCorrector()
        corrector.language = .english
        XCTAssertEqual(corrector.autocorrection(for: "i"), "I")
        XCTAssertEqual(corrector.autocorrection(for: "dont"), "don't")
        XCTAssertEqual(corrector.autocorrection(for: "Dont"), "Don't")
        XCTAssertNil(corrector.autocorrection(for: "I"))
    }

    func testShortcuts() {
        let corrector = makeCorrector()
        corrector.shortcuts = ["omw": "On my way!"]
        XCTAssertEqual(corrector.autocorrection(for: "omw"), "On my way!")
    }

    func testEditDistance() {
        XCTAssertEqual(EditDistance.between("kitten", "sitting"), 3)
        XCTAssertEqual(EditDistance.between("teh", "the"), 1)
        XCTAssertEqual(EditDistance.between("", "abc"), 3)
        XCTAssertEqual(EditDistance.between("same", "same"), 0)
    }

    func testLearnedWordsStore() {
        let store = LearnedWordsStore(defaults: UserDefaults(suiteName: "LearnedWords-\(UUID())")!)
        store.learn("Piaskowski", language: .dutch)
        XCTAssertEqual(store.load()[.dutch], ["piaskowski"])
        store.forget("piaskowski", language: .dutch)
        XCTAssertEqual(store.load()[.dutch], [])
    }
}
