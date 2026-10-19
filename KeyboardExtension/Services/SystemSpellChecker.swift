import UIKit
import KeyboardCore

/// Apple's built-in spell checker (the one the system keyboard uses), plus names from Contacts.
final class SystemSpellChecker: SpellChecking {
    private let checker = UITextChecker()
    /// Lowercased names from the supplementary lexicon (contacts, etc.). Always counted as correct.
    var extraWords: Set<String> = []
    private var languageCodes: [KeyboardLanguage: String?] = [:]

    func isKnown(_ word: String, language: KeyboardLanguage) -> Bool {
        if extraWords.contains(word.lowercased()) { return true }
        // Without a dictionary for this language, never call anything a typo.
        guard let code = code(for: language) else { return true }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                       wrap: false, language: code)
        return misspelled.location == NSNotFound
    }

    func corrections(for word: String, language: KeyboardLanguage) -> [String] {
        guard let code = code(for: language) else { return [] }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.guesses(forWordRange: range, in: word, language: code) ?? []
    }

    func completions(for prefix: String, language: KeyboardLanguage) -> [String] {
        guard let code = code(for: language) else { return [] }
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        return checker.completions(forPartialWordRange: range, in: prefix, language: code) ?? []
    }

    /// UITextChecker's code for the language ("nl_NL"), or the closest one it has ("nl").
    private func code(for language: KeyboardLanguage) -> String? {
        if let cached = languageCodes[language] { return cached }
        let available = UITextChecker.availableLanguages
        let wanted = language.spellCheckerCode
        let code = available.first { $0 == wanted }
            ?? available.first { $0.hasPrefix(String(wanted.prefix(2))) }
        languageCodes[language] = .some(code)
        return code
    }
}
