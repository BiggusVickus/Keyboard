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
    /// iOS key click sounds (letters, delete and modifier keys each have their own).
    public var keySounds = true
    /// How touches are matched to keys (normal, larger letters, or trained on your own typing).
    public var touchModel: TouchModelKind = .normal
    /// While the space bar is a trackpad, show the text and a floating cursor in the keyboard.
    /// Off: the keyboard goes blank like Apple's, and you follow the cursor in the text box.
    public var trackpadShowsText = true
    /// Your own shortcuts that expand into longer text (shown above the keys first, with ✕ to keep the shortcut).
    public var textExpansions: [TextExpansion] = []

    // Grammar
    public var grammarLevel: GrammarLevel = .errorsAndImprovements
    public var grammarCheckEnabled = true
    /// Your own LanguageTool server, e.g. "http://192.168.1.20:8010/v2/check". Empty = none.
    /// It is tried first; the free public server is always the backup.
    public var languageToolURL = ""

    /// The free public server: used when you have no server of your own, or yours can't be reached.
    public static let publicLanguageToolURL = "https://api.languagetool.org/v2/check"

    /// Your own server, if one is set (the public server typed in here doesn't count).
    public var ownLanguageToolURL: String? {
        let url = languageToolURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty || url == Self.publicLanguageToolURL ? nil : url
    }
    /// Save fixed mistakes so the app can show what you get wrong most.
    public var keepLearningLog = true

    // Translator
    public var translateFrom: KeyboardLanguage = .english
    public var translateTo: KeyboardLanguage = .dutch

    // AI
    public var aiProvider: AIProviderKind = .claude
    public var claudeModel = ClaudeModelOption.defaultID
    /// Stored in the shared App Group so the keyboard can read it. Fine for personal use.
    public var claudeAPIKey = ""
    /// Base URL of an OpenAI-compatible server, e.g. "http://192.168.1.20:11434/v1" for Ollama.
    public var localBaseURL = "http://192.168.1.20:11434/v1"
    public var localModel = "qwen3:14b"
    /// A second OpenAI-compatible server (e.g. Ollama on a Raspberry Pi), used when the first
    /// one doesn't answer (PC switched off). Empty = no backup.
    public var localBackupBaseURL = ""
    public var localBackupModel = ""
    /// Models you added (by hand or from the servers), offered in the Model dropdowns.
    public var localModels: [String] = []
    /// Let reasoning models (Qwen…) think before answering: sometimes more careful, but minutes
    /// instead of seconds on a big model. Off by default.
    public var localThinking = false

    /// What the Model dropdowns offer: your list, plus whatever is selected now (so it always shows).
    public var localModelChoices: [String] {
        var seen = Set<String>()
        return (localModels + [localModel, localBackupModel])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // Your own translation servers (Tools/server/translate_server.py with the trained NL↔EN models).
    // Tried in order for Dutch ↔ English; the AI helper translates everything else, or when both are off.
    public var translatorURL = ""
    public var translatorBackupURL = ""

    /// The translation servers that are filled in, main first.
    public var translatorURLs: [String] {
        [translatorURL, translatorBackupURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

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
        keySounds = try c.decodeIfPresent(Bool.self, forKey: .keySounds) ?? d.keySounds
        touchModel = try c.decodeIfPresent(TouchModelKind.self, forKey: .touchModel) ?? d.touchModel
        trackpadShowsText = try c.decodeIfPresent(Bool.self, forKey: .trackpadShowsText) ?? d.trackpadShowsText
        textExpansions = try c.decodeIfPresent([TextExpansion].self, forKey: .textExpansions) ?? d.textExpansions
        grammarLevel = try c.decodeIfPresent(GrammarLevel.self, forKey: .grammarLevel) ?? d.grammarLevel
        grammarCheckEnabled = try c.decodeIfPresent(Bool.self, forKey: .grammarCheckEnabled) ?? d.grammarCheckEnabled
        languageToolURL = try c.decodeIfPresent(String.self, forKey: .languageToolURL) ?? d.languageToolURL
        // Older versions stored the public server here; it is the built-in backup now.
        if languageToolURL == Self.publicLanguageToolURL { languageToolURL = "" }
        keepLearningLog = try c.decodeIfPresent(Bool.self, forKey: .keepLearningLog) ?? d.keepLearningLog
        translateFrom = try c.decodeIfPresent(KeyboardLanguage.self, forKey: .translateFrom) ?? d.translateFrom
        translateTo = try c.decodeIfPresent(KeyboardLanguage.self, forKey: .translateTo) ?? d.translateTo
        aiProvider = try c.decodeIfPresent(AIProviderKind.self, forKey: .aiProvider) ?? d.aiProvider
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        claudeAPIKey = try c.decodeIfPresent(String.self, forKey: .claudeAPIKey) ?? d.claudeAPIKey
        localBaseURL = try c.decodeIfPresent(String.self, forKey: .localBaseURL) ?? d.localBaseURL
        localModel = try c.decodeIfPresent(String.self, forKey: .localModel) ?? d.localModel
        localBackupBaseURL = try c.decodeIfPresent(String.self, forKey: .localBackupBaseURL) ?? d.localBackupBaseURL
        localBackupModel = try c.decodeIfPresent(String.self, forKey: .localBackupModel) ?? d.localBackupModel
        localModels = try c.decodeIfPresent([String].self, forKey: .localModels) ?? d.localModels
        localThinking = try c.decodeIfPresent(Bool.self, forKey: .localThinking) ?? d.localThinking
        translatorURL = try c.decodeIfPresent(String.self, forKey: .translatorURL) ?? d.translatorURL
        translatorBackupURL = try c.decodeIfPresent(String.self, forKey: .translatorBackupURL) ?? d.translatorBackupURL
    }

    private enum CodingKeys: String, CodingKey {
        case enabledLanguages, currentLanguage
        case autocorrect, autoCapitalize, hapticFeedback, keySounds, touchModel, textExpansions, trackpadShowsText
        case grammarLevel, grammarCheckEnabled, languageToolURL, keepLearningLog
        case translateFrom, translateTo
        case aiProvider, claudeModel, claudeAPIKey, localBaseURL, localModel, localBackupBaseURL, localBackupModel, localModels, localThinking
        case translatorURL, translatorBackupURL
    }
}
