import Foundation

/// One thing the grammar check found.
public struct GrammarIssue: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Wrong: shown red.
        case error
        /// Optional: what you wrote is also correct. Shown blue.
        case tip
    }

    public enum Source: String, Codable, Sendable {
        case languageTool
        /// Taalhulp's own de/het dictionary (works offline).
        case articles
    }

    /// Where the issue is, in UTF-16 offsets of the checked text.
    public let range: UTF16Range
    /// The words the issue is about, e.g. "het auto".
    public let text: String
    /// The checker's own message. For LanguageTool this is in the language of the text.
    public let message: String
    public let shortMessage: String
    /// Possible fixes for `text`, best first.
    public let replacements: [String]
    public let ruleID: String
    public let kind: Kind
    public let source: Source
    public let topic: GrammarTopic
    /// A specific English explanation when one is known (e.g. "auto is a de-word").
    public let explanation: String?
    /// The sentence the issue is in, for "Explain" and the learning log.
    public let sentence: String

    public init(range: UTF16Range, text: String, message: String, shortMessage: String = "",
                replacements: [String], ruleID: String, kind: Kind, source: Source,
                topic: GrammarTopic, explanation: String? = nil, sentence: String) {
        self.range = range
        self.text = text
        self.message = message
        self.shortMessage = shortMessage
        self.replacements = replacements
        self.ruleID = ruleID
        self.kind = kind
        self.source = source
        self.topic = topic
        self.explanation = explanation
        self.sentence = sentence
    }

    public var id: String { "\(source.rawValue)|\(ruleID)|\(range.location)|\(range.length)" }

    /// "Ignore" hides every issue with the same rule and text until the keyboard closes.
    public var ignoreKey: String { "\(ruleID)|\(text)" }

    /// English explanation for the user: the specific one if we have it, otherwise the general rule.
    public func englishExplanation(language: KeyboardLanguage) -> String {
        explanation ?? topic.explanation(for: language)
    }
}

/// The outcome of checking one piece of text.
public struct GrammarResult: Equatable, Sendable {
    public let text: String
    public let language: KeyboardLanguage
    public let issues: [GrammarIssue]
    /// Set when LanguageTool couldn't be used; the offline de/het check still ran.
    public let warning: String?

    public init(text: String, language: KeyboardLanguage, issues: [GrammarIssue], warning: String? = nil) {
        self.text = text
        self.language = language
        self.issues = issues
        self.warning = warning
    }

    /// The issues that still fit `context` (the text before the cursor now), so chips never point
    /// at text that has since changed.
    public func liveIssues(in context: String, ignoring ignored: Set<String> = []) -> [GrammarIssue] {
        let currentWord = TextEditing.currentWord(before: context)
        let wordStart = context.utf16.count - currentWord.utf16.count
        return issues.filter { issue in
            guard !ignored.contains(issue.ignoreKey) else { return false }
            guard issue.range.substring(in: context) == issue.text else { return false }
            // Don't nag about the word that is still being typed.
            if !currentWord.isEmpty, issue.range.end > wordStart { return false }
            return true
        }
    }
}
