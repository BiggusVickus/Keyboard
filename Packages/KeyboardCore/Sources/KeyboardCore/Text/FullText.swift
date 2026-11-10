import Foundation

/// What "Is this correct?" and "Improve" work on: the selection if there is one, otherwise the
/// whole text field.
public enum ReviewTarget: Equatable, Sendable {
    case selection(String)
    /// The whole field. After reading it, the cursor is at the end of the text.
    case wholeText(String)

    public var text: String {
        switch self {
        case .selection(let text), .wholeText(let text): text
        }
    }

    public var isSelection: Bool {
        if case .selection = self { return true }
        return false
    }
}

/// Reading and replacing the whole text field. iOS only shows a keyboard a window of text around
/// the cursor (`documentContextBeforeInput` / `AfterInput`), and updates it a moment after the
/// cursor moves. So the reader walks the cursor through the text one window at a time, waiting
/// after each step until iOS shows the new spot, and gives up rather than guess.
@MainActor
public enum FullText {
    /// Longest text it will read (UTF-16 units), to keep the AI request and the editing reasonable.
    public static let maxLength = 20_000

    /// Moves the cursor to the end of the field and returns the whole text, or nil when it can't be
    /// read reliably (too long, or iOS didn't keep up). `settle` waits a moment for iOS.
    public static func read(_ document: TextDocument, maxLength: Int = maxLength,
                            settle: () async -> Void) async -> String? {
        // 1. To the end of the text.
        var steps = 0
        while let after = document.documentContextAfterInput, !after.isEmpty {
            steps += 1
            guard steps <= 200 else { return nil }
            document.adjustTextPosition(byCharacterOffset: after.utf16.count)
            // iOS has caught up once it shows something else after the cursor. (Not "before": some
            // apps show nothing before the cursor right after a sentence end, see below.)
            guard await wait(settle, until: { document.documentContextAfterInput != after }) else { return nil }
        }

        // 2. Back to the start, one piece at a time, collecting the text.
        var text = ""
        var movedBack = 0
        defer { if movedBack > 0 { document.adjustTextPosition(byCharacterOffset: movedBack) } }  // 3. to the end again
        steps = 0
        while true {
            steps += 1
            guard steps <= 2000 else { return nil }
            let before = document.documentContextBeforeInput ?? ""
            if !before.isEmpty {
                text = before + text
                guard text.utf16.count <= maxLength else { return nil }
                document.adjustTextPosition(byCharacterOffset: -before.utf16.count)
                movedBack += before.utf16.count
                let caughtUp = await wait(settle) {
                    let after = document.documentContextAfterInput ?? ""
                    return !after.isEmpty && (after.hasPrefix(before) || before.hasPrefix(after))
                }
                guard caughtUp else { return nil }
                continue
            }
            // Nothing before the cursor: the start of the text, or only the start of a sentence
            // (WhatsApp and others show no further back than that). Step one character back to see:
            // if the text after the cursor changes, there was more.
            let afterHere = document.documentContextAfterInput ?? ""
            document.adjustTextPosition(byCharacterOffset: -1)
            let moved = await wait(settle, until: { (document.documentContextAfterInput ?? "") != afterHere })
            guard moved, let character = document.documentContextAfterInput?.first else { break }  // the start
            text = String(character) + text
            guard text.utf16.count <= maxLength else { return nil }
            movedBack += 1
        }
        return text
    }

    /// Replaces the whole text read by `read` with `replacement`. The cursor must still be at the end
    /// and the text must still end the same way; returns false (and changes nothing) otherwise.
    @discardableResult
    public static func replace(_ original: String, with replacement: String, in document: TextDocument) -> Bool {
        guard (document.documentContextAfterInput ?? "").isEmpty, !original.isEmpty else { return false }
        let before = document.documentContextBeforeInput ?? ""
        // Right after "… . " some apps (WhatsApp) show nothing before the cursor; then only check
        // that the text read also ended in a space or new line.
        let stillTheSame = before.isEmpty ? original.last?.isWhitespace == true : original.hasSuffix(before)
        guard stillTheSame else { return false }
        for _ in 0..<original.count { document.deleteBackward() }
        document.insertText(replacement)
        return true
    }

    /// Replaces the selection, if it is still the same text.
    @discardableResult
    public static func replaceSelection(_ original: String, with replacement: String, in document: TextDocument) -> Bool {
        guard document.selectedText == original else { return false }
        document.insertText(replacement)
        return true
    }

    /// The sentence around `part` in `text` (for the learning log), or `part` if it isn't found.
    public static func sentence(containing part: String, in text: String) -> String {
        guard !part.isEmpty, let range = text.range(of: part) else { return part }
        let upToEnd = String(text[..<range.upperBound])
        let rest = text[range.upperBound...]
        let tail = rest.prefix { !TextEditing.isSentenceEnd($0) && !$0.isNewline }
        let end = rest.dropFirst(tail.count).first.map { TextEditing.isSentenceEnd($0) ? String($0) : "" } ?? ""
        let start = TextEditing.currentSentence(before: upToEnd)?.text ?? part
        return start + tail + end
    }

    /// Calls `settle` until `condition` holds, at most 20 times.
    private static func wait(_ settle: () async -> Void, until condition: () -> Bool) async -> Bool {
        for _ in 0..<20 {
            if condition() { return true }
            await settle()
        }
        return condition()
    }
}
