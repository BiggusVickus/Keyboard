import Foundation

/// A piece of text and where it sits in the text before the cursor.
public struct TextSpan: Equatable, Sendable {
    public let text: String
    public let range: UTF16Range

    public init(text: String, range: UTF16Range) {
        self.text = text
        self.range = range
    }
}

/// Finding words and sentences before the cursor, and replacing text in the field.
public enum TextEditing {
    // MARK: - Words

    static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }

    /// Apostrophes and hyphens belong to a word only between two letters: zo'n, e-mail, don't.
    static func isJoiner(_ c: Character) -> Bool {
        c == "'" || c == "’" || c == "-"
    }

    /// The word directly before the cursor: "Ik ben thu" → "thu". Empty right after a space.
    public static func currentWord(before context: String) -> String {
        let chars = Array(context)
        var start = chars.count
        while start > 0 {
            let c = chars[start - 1]
            if isWordCharacter(c) {
                start -= 1
            } else if isJoiner(c), start < chars.count, start >= 2, isWordCharacter(chars[start - 2]) {
                start -= 1
            } else {
                break
            }
        }
        return String(chars[start...])
    }

    /// True when the cursor is in the middle of a word ("thu|is"). Autocorrect leaves those alone.
    public static func isInsideWord(after context: String?) -> Bool {
        guard let first = context?.first else { return false }
        return isWordCharacter(first)
    }

    // MARK: - Sentences

    static func isSentenceEnd(_ c: Character) -> Bool {
        c == "." || c == "!" || c == "?"
    }

    /// The sentence the cursor is in, or the one just finished.
    /// "Hallo. Ik ben thuis. " → "Ik ben thuis."
    public static func currentSentence(before context: String) -> TextSpan? {
        let chars = Array(context)
        var end = chars.count
        while end > 0, chars[end - 1].isWhitespace { end -= 1 }
        guard end > 0 else { return nil }

        // The last character always belongs to the sentence, even when it is the full stop.
        var start = end - 1
        while start > 0 {
            let previous = chars[start - 1]
            if previous.isNewline { break }
            if previous.isWhitespace, start >= 2, isSentenceEnd(chars[start - 2]) { break }
            start -= 1
        }
        while start < end, chars[start].isWhitespace { start += 1 }

        let text = String(chars[start..<end])
        let location = String(chars[..<start]).utf16.count
        return TextSpan(text: text, range: UTF16Range(location: location, length: text.utf16.count))
    }

    // MARK: - Editing the field

    /// Deletes the last `characterCount` characters before the cursor and types `replacement`.
    public static func replaceLast(_ characterCount: Int, with replacement: String, in document: TextDocument) {
        for _ in 0..<max(0, characterCount) { document.deleteBackward() }
        document.insertText(replacement)
    }

    /// Replaces `range` of `context` (the text before the cursor) with `replacement`,
    /// then moves the cursor back to where it was. Returns false if the range doesn't fit.
    @discardableResult
    public static func replace(_ range: UTF16Range, in context: String, with replacement: String,
                               document: TextDocument) -> Bool {
        guard let indices = range.indices(in: context) else { return false }
        let tailLength = context[indices.upperBound...].utf16.count
        let removedCount = context[indices].count

        if tailLength > 0 { document.adjustTextPosition(byCharacterOffset: -tailLength) }
        replaceLast(removedCount, with: replacement, in: document)
        if tailLength > 0 { document.adjustTextPosition(byCharacterOffset: tailLength) }
        return true
    }

    // MARK: - Case

    /// Gives `replacement` the capitalisation of `original`: "Teh" → "The", "TEH" → "THE".
    /// Never lowercases, so German nouns and names keep their capital.
    public static func matchCase(_ replacement: String, to original: String) -> String {
        if original.count > 1, original == original.uppercased(), original != original.lowercased() {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
