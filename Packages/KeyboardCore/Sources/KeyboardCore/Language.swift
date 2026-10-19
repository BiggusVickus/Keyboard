import Foundation

/// The languages the keyboard can type in.
public enum KeyboardLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case german = "de"
    case dutch = "nl"

    public var id: String { rawValue }

    /// Name shown in the app's settings.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .dutch: "Nederlands"
        }
    }

    /// English name, for the translator and AI prompts.
    public var englishName: String {
        switch self {
        case .english: "English"
        case .german: "German"
        case .dutch: "Dutch"
        }
    }

    /// Short label shown on the language switch key.
    public var shortLabel: String { rawValue.uppercased() }

    /// Text shown on the space bar, like the system keyboard does.
    public var spaceBarLabel: String { displayName }

    /// Language code LanguageTool expects.
    public var languageToolCode: String {
        switch self {
        case .english: "en-US"
        case .german: "de-DE"
        case .dutch: "nl"
        }
    }

    /// Language code for Apple's spell checker (UITextChecker).
    public var spellCheckerCode: String {
        switch self {
        case .english: "en_US"
        case .german: "de_DE"
        case .dutch: "nl_NL"
        }
    }

    /// Whether grammar explanations should be given (English is the native language).
    public var wantsExplanations: Bool { self != .english }
}
