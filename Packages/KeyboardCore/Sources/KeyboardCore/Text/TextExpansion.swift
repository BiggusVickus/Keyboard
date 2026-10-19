import Foundation

/// A shortcut you type that turns into longer text, e.g. "mvg" → "Met vriendelijke groet,".
/// Managed in the app under Settings → Text expansions.
public struct TextExpansion: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Letters and digits only, so it is one "word" for the keyboard. Matched ignoring case.
    public var shortcut: String
    public var expansion: String

    public init(id: UUID = UUID(), shortcut: String, expansion: String) {
        self.id = id
        self.shortcut = shortcut
        self.expansion = expansion
    }
}

public enum TextExpander {
    /// The expansion for the word just typed, if there is one.
    public static func match(_ word: String, in expansions: [TextExpansion]) -> TextExpansion? {
        guard !word.isEmpty else { return nil }
        let lower = word.lowercased()
        return expansions.first { $0.shortcut.lowercased() == lower && !$0.expansion.isEmpty }
    }

    /// The text that replaces `word`. Typing the shortcut with a capital ("Mvg") capitalises the
    /// first letter of the expansion; everything else is kept exactly as you saved it.
    public static func expandedText(for word: String, using expansion: TextExpansion) -> String {
        guard let first = word.first, first.isUppercase, let firstOut = expansion.expansion.first else {
            return expansion.expansion
        }
        return firstOut.uppercased() + expansion.expansion.dropFirst()
    }

    /// Cleans what was typed in Settings: no spaces or punctuation (they would end the word).
    public static func cleanShortcut(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber })
    }

    /// Adds a new expansion, or replaces the one with the same shortcut.
    public static func adding(_ new: TextExpansion, to list: [TextExpansion]) -> [TextExpansion] {
        var result = list.filter { $0.shortcut.lowercased() != new.shortcut.lowercased() }
        result.append(new)
        return result.sorted { $0.shortcut.lowercased() < $1.shortcut.lowercased() }
    }
}
