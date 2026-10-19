import Foundation

/// What the return key should say (mirrors `UIReturnKeyType`).
public enum ReturnKeyStyle: Sendable {
    case `default`, go, search, send, done, next, join, route, `continue`, emergencyCall

    /// Text on the key, in the keyboard's language. Nil means: show the ⏎ symbol.
    public func label(for language: KeyboardLanguage) -> String? {
        switch (self, language) {
        case (.default, _): nil
        case (.go, .english): "Go"
        case (.go, .dutch): "Ga"
        case (.go, .german): "Los"
        case (.search, .english): "Search"
        case (.search, .dutch): "Zoek"
        case (.search, .german): "Suchen"
        case (.send, .english): "Send"
        case (.send, .dutch): "Stuur"
        case (.send, .german): "Senden"
        case (.done, .english): "Done"
        case (.done, .dutch): "Gereed"
        case (.done, .german): "Fertig"
        case (.next, .english): "Next"
        case (.next, .dutch): "Volgende"
        case (.next, .german): "Weiter"
        case (.join, .english): "Join"
        case (.join, .dutch): "Verbind"
        case (.join, .german): "Beitreten"
        case (.route, _): "Route"
        case (.continue, .english): "Continue"
        case (.continue, .dutch): "Ga door"
        case (.continue, .german): "Weiter"
        case (.emergencyCall, .english): "Emergency"
        case (.emergencyCall, .dutch): "Noodoproep"
        case (.emergencyCall, .german): "Notruf"
        }
    }

    /// Shown in blue, like the system keyboard does for actions.
    public var isProminent: Bool {
        switch self {
        case .go, .search, .send, .done, .join, .route, .emergencyCall: true
        case .default, .next, .continue: false
        }
    }
}

/// The kind of text a field expects (a simplified `UIKeyboardType`).
public enum FieldKind: Sendable {
    case text
    case email
    case url
    case webSearch
}

/// What the current text field asks for. Read from `UITextDocumentProxy` each time it changes.
public struct FieldTraits: Equatable, Sendable {
    public var kind: FieldKind
    public var returnKey: ReturnKeyStyle
    public var capitalization: AutocapitalizationMode
    /// False when the app turned autocorrection off for this field (user names, codes…).
    public var allowsAutocorrection: Bool
    /// The return key is grey and does nothing while the field is empty.
    public var enablesReturnKeyAutomatically: Bool

    public init(kind: FieldKind = .text, returnKey: ReturnKeyStyle = .default,
                capitalization: AutocapitalizationMode = .sentences,
                allowsAutocorrection: Bool = true, enablesReturnKeyAutomatically: Bool = false) {
        self.kind = kind
        self.returnKey = returnKey
        self.capitalization = capitalization
        self.allowsAutocorrection = allowsAutocorrection
        self.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically
    }

    /// Autocorrect, grammar chips and the AI tools only make sense for normal text.
    public var wantsLanguageHelp: Bool {
        allowsAutocorrection && (kind == .text || kind == .webSearch)
    }
}
