import Foundation

/// One slot in the suggestion bar.
public struct Suggestion: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Keep exactly what you typed (shown in quotes).
        case typed
        case correction
        case completion
        /// Go back to what you typed before autocorrect changed it.
        case revert
    }

    public let text: String
    public let kind: Kind
    /// Pressing space will put this word in automatically (shown highlighted).
    public let isAutocorrection: Bool

    public init(text: String, kind: Kind, isAutocorrection: Bool = false) {
        self.text = text
        self.kind = kind
        self.isAutocorrection = isAutocorrection
    }

    public var id: String { "\(kind)-\(text)" }
}

/// The last word autocorrect changed, so it can be undone.
public struct Autocorrection: Equatable, Sendable {
    public let original: String
    public let replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}

/// Decides what goes in the suggestion bar and which typos are fixed when you press space.
public final class Autocorrector {
    public var mode: AutocorrectMode = .automatic
    public var language: KeyboardLanguage = .dutch
    /// Words the user taught the keyboard (lowercased). Never corrected.
    public var learnedWords: [KeyboardLanguage: Set<String>] = [:]
    /// Text replacements from iOS Settings → General → Keyboard (e.g. "omw" → "On my way!"), keyed lowercased.
    public var shortcuts: [String: String] = [:]

    public static let maxSuggestions = 3

    private let checker: SpellChecking

    public init(checker: SpellChecking) {
        self.checker = checker
    }

    public func isKnown(_ word: String) -> Bool {
        let lower = word.lowercased()
        if learnedWords[language]?.contains(lower) == true { return true }
        return checker.isKnown(word, language: language) || checker.isKnown(lower, language: language)
    }

    /// What `word` should become when space is pressed, or nil to leave it alone.
    public func autocorrection(for word: String) -> String? {
        guard mode == .automatic else { return nil }
        return bestCorrection(for: word)
    }

    /// The suggestion bar for the word being typed.
    /// - Parameter last: the previous autocorrection; if the user went back into that word, offer to undo it.
    public func suggestions(for word: String, undoing last: Autocorrection? = nil) -> [Suggestion] {
        guard mode != .off, !word.isEmpty else { return [] }

        var result: [Suggestion] = []
        func add(_ text: String, _ kind: Suggestion.Kind, isAutocorrection: Bool = false) {
            guard result.count < Self.maxSuggestions,
                  !result.contains(where: { $0.text.lowercased() == text.lowercased() })
            else { return }
            result.append(Suggestion(text: text, kind: kind, isAutocorrection: isAutocorrection))
        }

        let isUndoing = last?.replacement == word
        if isUndoing, let last { add(last.original, .revert) }

        let known = isKnown(word)
        let best = isUndoing ? nil : bestCorrection(for: word)
        let automatic = mode == .automatic ? best : nil

        if !known || best != nil { add(word, .typed) }
        if let best { add(best, .correction, isAutocorrection: automatic != nil) }

        let completions = checker.completions(for: word, language: language)
            .filter { $0.lowercased() != word.lowercased() }
            .map { TextEditing.matchCase($0, to: word) }
        let corrections = known ? [] : checker.corrections(for: word, language: language)
            .filter { !$0.contains(" ") }
            .map { TextEditing.matchCase($0, to: word) }

        // Mix the two: a partly typed word usually wants a completion, a typo a correction.
        for c in completions.prefix(1) { add(c, .completion) }
        for c in corrections.prefix(1) { add(c, .correction) }
        for c in completions.dropFirst() { add(c, .completion) }
        for c in corrections.dropFirst() { add(c, .correction) }
        return result
    }

    // MARK: - Rules

    /// The correction we are confident about, or nil.
    func bestCorrection(for word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let lower = word.lowercased()
        if learnedWords[language]?.contains(lower) == true { return nil }

        if let shortcut = shortcuts[lower], shortcut != word { return shortcut }
        if let fix = Self.commonFixes[language]?[lower] {
            let fixed = TextEditing.matchCase(fix, to: word)
            return fixed == word ? nil : fixed
        }

        guard Self.isCorrectable(word), !isKnown(word) else { return nil }
        // Short words get only one edit; otherwise "dat" could become "dag" and change the meaning.
        let maxDistance = word.count <= 4 ? 1 : 2
        for guess in checker.corrections(for: word, language: language).prefix(3) {
            // UITextChecker sometimes suggests splitting a word ("thuis" → "thu is"); never auto-apply those.
            guard !guess.isEmpty, !guess.contains(" ") else { continue }
            if EditDistance.between(lower, guess.lowercased()) <= maxDistance {
                let fixed = TextEditing.matchCase(guess, to: word)
                return fixed == word ? nil : fixed
            }
        }
        return nil
    }

    /// Single letters, words with digits and ALL-CAPS words (acronyms, AMC) are left alone.
    static func isCorrectable(_ word: String) -> Bool {
        guard word.count >= 2 else { return false }
        guard !word.contains(where: \.isNumber) else { return false }
        let isAllCaps = word == word.uppercased() && word != word.lowercased()
        return !isAllCaps
    }

    /// Fixes the system keyboard also makes, which the spell checker doesn't offer.
    static let commonFixes: [KeyboardLanguage: [String: String]] = [
        .english: [
            "i": "I", "im": "I'm", "ive": "I've",
            "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
            "cant": "can't", "wont": "won't", "isnt": "isn't", "arent": "aren't",
            "wasnt": "wasn't", "werent": "weren't", "havent": "haven't", "hasnt": "hasn't",
            "hadnt": "hadn't", "couldnt": "couldn't", "shouldnt": "shouldn't", "wouldnt": "wouldn't",
            "youre": "you're", "theyre": "they're", "thats": "that's", "whats": "what's",
            "theres": "there's", "youve": "you've", "weve": "we've", "theyve": "they've",
            "youll": "you'll", "theyll": "they'll",
        ],
    ]
}
