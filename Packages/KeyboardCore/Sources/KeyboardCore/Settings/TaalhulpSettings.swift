import Foundation

/// How hard autocorrect should work while typing.
public enum AutocorrectMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// No spelling help at all.
    case off
    /// Show suggestions in the bar, but never change what you typed.
    case suggestOnly
    /// Replace clear typos automatically when you press space (tap "undo" to revert).
    case automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .suggestOnly: "Suggest only"
        case .automatic: "Automatic"
        }
    }

    public var detail: String {
        switch self {
        case .off: "No spelling suggestions."
        case .suggestOnly: "Shows suggestions above the keys, but never changes your text by itself."
        case .automatic: "Fixes clear typos when you press space. Tap the suggestion bar to undo."
        }
    }
}

/// How picky the grammar check should be.
public enum GrammarLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Only things that are actually wrong.
    case errorsOnly
    /// Errors, plus optional "this word is more natural" tips (marked as optional).
    case errorsAndImprovements
    /// Everything above, plus suggestions for more natural, native-sounding phrasing.
    case polish

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .errorsOnly: "Errors only"
        case .errorsAndImprovements: "Errors + optional tips"
        case .polish: "Polish"
        }
    }

    public var detail: String {
        switch self {
        case .errorsOnly:
            "Only flags real mistakes (de/het, word order, verb forms…). Correct sentences are left alone."
        case .errorsAndImprovements:
            "Also suggests a better word now and then, clearly marked as optional: what you wrote is still correct."
        case .polish:
            "Also suggests more natural, native-sounding phrasing. Most suggestions will be optional."
        }
    }

    /// Whether optional improvements (not errors) should be shown at all.
    public var showsImprovements: Bool { self != .errorsOnly }
}

/// Which AI is used for explanations, "Is this correct?" and "Improve sentence".
public enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    /// LanguageTool + dictionaries only. Free, no AI.
    case none
    /// Anthropic's Claude API (needs an API key, pay per use).
    case claude
    /// Your own server, e.g. Ollama or LM Studio on your Mac. Free, needs the Mac to be on.
    case local
    /// Apple's on-device model (experimental: may not be available inside a keyboard).
    case appleOnDevice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .claude: "Claude"
        case .local: "Local LLM"
        case .appleOnDevice: "Apple on-device"
        }
    }
}

/// A Claude model choice offered in Settings. A custom model ID can always be typed instead.
public struct ClaudeModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let note: String

    public static let all: [ClaudeModelOption] = [
        .init(id: "claude-haiku-5-5", name: "Haiku 5.5", note: "Cheapest and fastest (~$0.0004 per check)"),
        .init(id: "claude-sonnet-5-5", name: "Sonnet 5.5", note: "Recommended balance (~$0.007 per check)"),
        .init(id: "claude-opus-5-5", name: "Opus 5.5", note: "Most careful explanations (~$0.014 per check)"),
        .init(id: "claude-fable-5-1", name: "Fable 5.1", note: "Most capable, most expensive"),
    ]

    public static let defaultID = "claude-sonnet-5-5"
}

/// Everything the user can configure. Shared between the app and the keyboard via the App Group.
public struct TaalhulpSettings: Codable, Equatable, Sendable {
    // Languages
    public var enabledLanguages: [KeyboardLanguage] = [.dutch, .english, .german]
    public var currentLanguage: KeyboardLanguage = .dutch

    // Typing
    public var autocorrect: AutocorrectMode = .automatic
    public var autoCapitalize = true
    public var hapticFeedback = true

    // Grammar
    public var grammarLevel: GrammarLevel = .errorsAndImprovements
    public var grammarCheckEnabled = true
    public var languageToolURL = "https://api.languagetool.org/v2/check"

    // AI
    public var aiProvider: AIProviderKind = .claude
    public var claudeModel = ClaudeModelOption.defaultID
    /// Stored in the shared App Group so the keyboard can read it. Fine for personal use.
    public var claudeAPIKey = ""
    /// Base URL of an OpenAI-compatible server, e.g. "http://192.168.1.20:11434/v1" for Ollama.
    public var localBaseURL = "http://192.168.1.20:11434/v1"
    public var localModel = "qwen3:14b"

    public init() {}

    /// The language after `currentLanguage` in the enabled list (wraps around).
    public func nextLanguage() -> KeyboardLanguage {
        let languages = enabledLanguages.isEmpty ? KeyboardLanguage.allCases : enabledLanguages
        guard let index = languages.firstIndex(of: currentLanguage) else { return languages[0] }
        return languages[(index + 1) % languages.count]
    }

    // Decoding fills in defaults for any missing key, so adding a new setting later
    // never wipes the settings that were saved by an older version of the app.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TaalhulpSettings()
        enabledLanguages = try c.decodeIfPresent([KeyboardLanguage].self, forKey: .enabledLanguages) ?? d.enabledLanguages
        currentLanguage = try c.decodeIfPresent(KeyboardLanguage.self, forKey: .currentLanguage) ?? d.currentLanguage
        autocorrect = try c.decodeIfPresent(AutocorrectMode.self, forKey: .autocorrect) ?? d.autocorrect
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? d.autoCapitalize
        hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? d.hapticFeedback
        grammarLevel = try c.decodeIfPresent(GrammarLevel.self, forKey: .grammarLevel) ?? d.grammarLevel
        grammarCheckEnabled = try c.decodeIfPresent(Bool.self, forKey: .grammarCheckEnabled) ?? d.grammarCheckEnabled
        languageToolURL = try c.decodeIfPresent(String.self, forKey: .languageToolURL) ?? d.languageToolURL
        aiProvider = try c.decodeIfPresent(AIProviderKind.self, forKey: .aiProvider) ?? d.aiProvider
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        claudeAPIKey = try c.decodeIfPresent(String.self, forKey: .claudeAPIKey) ?? d.claudeAPIKey
        localBaseURL = try c.decodeIfPresent(String.self, forKey: .localBaseURL) ?? d.localBaseURL
        localModel = try c.decodeIfPresent(String.self, forKey: .localModel) ?? d.localModel
    }

    private enum CodingKeys: String, CodingKey {
        case enabledLanguages, currentLanguage
        case autocorrect, autoCapitalize, hapticFeedback
        case grammarLevel, grammarCheckEnabled, languageToolURL
        case aiProvider, claudeModel, claudeAPIKey, localBaseURL, localModel
    }
}
