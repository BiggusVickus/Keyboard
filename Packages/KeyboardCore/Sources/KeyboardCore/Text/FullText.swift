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
                            log: (String) -> Void = { _ in },
                            settle: () async -> Void) async -> String? {
        log("start: \(describe(document))")
        // 1. To the end of the text.
        guard await moveToEnd(document, log: log, settle: settle) else { return nil }
        // 2. Back to the start, one piece at a time, collecting the text.
        let text = await collectBackwards(document, maxLength: maxLength, log: log, settle: settle)
        // 3. To the end again (read forward rather than jump back by a count: at the start, some
        //    apps put the cursor somewhere unexpected, so the count can't be trusted).
        guard await moveToEnd(document, log: log, settle: settle), let text else { return nil }
        log("read \(text.count) characters")
        return text
    }

    /// Moves the cursor forward by whatever the app shows after it, until nothing is left.
    private static func moveToEnd(_ document: TextDocument, log: (String) -> Void,
                                  settle: () async -> Void) async -> Bool {
        var steps = 0
        while let after = document.documentContextAfterInput, !after.isEmpty {
            steps += 1
            guard steps <= 300 else {
                log("to end: too many steps")
                return false
            }
            document.adjustTextPosition(byCharacterOffset: after.utf16.count)
            // iOS has caught up once it shows something else after the cursor. (Not "before": some
            // apps show nothing before the cursor right after a sentence end.)
            guard await wait(settle, until: { document.documentContextAfterInput != after }) else {
                log("to end: iOS didn't show the new spot. \(describe(document))")
                return false
            }
            log("to end, step \(steps): \(describe(document))")
        }
        return true
    }

    /// From the end of the text back to its start, collecting what the app shows before the cursor.
    /// Nil when it can't be read reliably. Leaves the cursor somewhere in the text.
    private static func collectBackwards(_ document: TextDocument, maxLength: Int, log: (String) -> Void,
                                         settle: () async -> Void) async -> String? {
        var text = ""
        var steps = 0
        while true {
            steps += 1
            guard steps <= 600 else {
                log("back: too many steps")
                return nil
            }
            let before = document.documentContextBeforeInput ?? ""
            if !before.isEmpty {
                text = before + text
                guard text.utf16.count <= maxLength else {
                    log("too long: over \(maxLength) characters")
                    return nil
                }
                document.adjustTextPosition(byCharacterOffset: -before.utf16.count)
                let caughtUp = await wait(settle) {
                    let after = document.documentContextAfterInput ?? ""
                    return !after.isEmpty && (after.hasPrefix(before) || before.hasPrefix(after))
                }
                guard caughtUp else {
                    log("back \(before.count): iOS didn't show the new spot. \(describe(document))")
                    return nil
                }
                log("back \(before.count): \(describe(document))")
                continue
            }

            // Nothing before the cursor: the start of the text, or only the start of a sentence
            // (WhatsApp shows no further back than that). Step one character back to see.
            let afterHere = document.documentContextAfterInput ?? ""
            document.adjustTextPosition(byCharacterOffset: -1)
            guard await wait(settle, until: { (document.documentContextAfterInput ?? "") != afterHere }) else {
                log("start of the text (one character back changed nothing)")
                return text
            }
            // Did it really move one character? One character forward must show exactly what was
            // after the cursor before. At the very start WhatsApp instead jumps to the end of the
            // first sentence; then this check fails, and this was the start.
            let afterOneBack = document.documentContextAfterInput ?? ""
            document.adjustTextPosition(byCharacterOffset: 1)
            guard await wait(settle, until: { (document.documentContextAfterInput ?? "") == afterHere }) else {
                log("start of the text (one character back jumped elsewhere: \(describe(document)))")
                return text
            }
            document.adjustTextPosition(byCharacterOffset: -1)
            guard await wait(settle, until: { (document.documentContextAfterInput ?? "") == afterOneBack }),
                  let character = afterOneBack.first
            else {
                log("back 1: iOS didn't show the new spot. \(describe(document))")
                return nil
            }
            log("nothing before the cursor, but one character back there was more: \(describe(document))")
            text = String(character) + text
            guard text.utf16.count <= maxLength else {
                log("too long: over \(maxLength) characters")
                return nil
            }
        }
    }

    /// What to work on: the selection, or the whole field when nothing is selected. When the
    /// selection is the whole field (nothing before or after it), the whole-text reader is used
    /// instead, since apps don't always pass a long selection on in full. Nil: couldn't be read.
    public static func readTarget(_ document: TextDocument, log: (String) -> Void = { _ in },
                                  settle: () async -> Void) async -> ReviewTarget? {
        if let selected = document.selectedText, selected.contains(where: \.isLetter) {
            let before = document.documentContextBeforeInput ?? ""
            let after = document.documentContextAfterInput ?? ""
            log("selection: \(describe(selected)), \(describe(document))")
            guard before.isEmpty, after.isEmpty else { return .selection(selected) }
            // Everything is selected: put the cursor at the end (moving by the selection's length
            // ends there whether iOS counts from its start or its end) and read the whole field.
            document.adjustTextPosition(byCharacterOffset: selected.utf16.count)
            _ = await wait(settle, until: { (document.selectedText ?? "").isEmpty })
            log("whole field was selected: reading it instead")
        }
        return await read(document, log: log, settle: settle).map(ReviewTarget.wholeText)
    }

    /// A short picture of a piece of text for the reading log: its length, start and end.
    static func describe(_ text: String) -> String {
        let flat = { (part: Substring) in part.replacingOccurrences(of: "\n", with: "⏎") }
        guard text.count > 36 else { return "[\(text.count)] \"\(flat(Substring(text)))\"" }
        return "[\(text.count)] \"\(flat(text.prefix(16)))…\(flat(text.suffix(16)))\""
    }

    static func describe(_ document: TextDocument) -> String {
        "before \(describe(document.documentContextBeforeInput ?? "")), after \(describe(document.documentContextAfterInput ?? ""))"
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

    /// Calls `settle` until `condition` holds, at most 40 times (about 1.2 s in the keyboard).
    private static func wait(_ settle: () async -> Void, until condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            await settle()
        }
        return condition()
    }
}
