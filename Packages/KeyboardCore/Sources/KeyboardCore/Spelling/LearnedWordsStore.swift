import Foundation

/// Words the user has taught the keyboard, by undoing an autocorrection or tapping the
/// "typed" suggestion. Autocorrect never changes these. Shared with the app via the App Group.
public struct LearnedWordsStore {
    static let key = "learnedWords.v1"

    private let defaults: UserDefaults

    public init() {
        self.defaults = UserDefaults(suiteName: SettingsStore.appGroupID) ?? .standard
    }

    /// For tests.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> [KeyboardLanguage: Set<String>] {
        let stored = defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        var result: [KeyboardLanguage: Set<String>] = [:]
        for (code, words) in stored {
            if let language = KeyboardLanguage(rawValue: code) { result[language] = Set(words) }
        }
        return result
    }

    public func learn(_ word: String, language: KeyboardLanguage) {
        var stored = defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        var words = Set(stored[language.rawValue] ?? [])
        words.insert(word.lowercased())
        stored[language.rawValue] = words.sorted()
        defaults.set(stored, forKey: Self.key)
    }

    public func forget(_ word: String, language: KeyboardLanguage) {
        var stored = defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        stored[language.rawValue]?.removeAll { $0 == word.lowercased() }
        defaults.set(stored, forKey: Self.key)
    }
}
