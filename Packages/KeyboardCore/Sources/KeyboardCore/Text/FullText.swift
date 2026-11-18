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
/// the cursor (`documentContextBeforeInput` / `AfterInput`), so the reader walks the cursor through
/// the text one window at a time, and gives up rather than guess.
///
/// Right after the keyboard moves the cursor, iOS first shows its own guess: what it already showed,
/// shifted along by the move. Where that runs out (step back by all it showed before the cursor, and
/// the guess shows nothing there) the app may well have more; its own view arrives a moment later,
/// and may be longer or shorter than the guess. So the reader:
/// - only trusts what it sees once it fits the text read so far (what follows the cursor must be the
///   start of it), never that it merely changed;
/// - doesn't take "nothing there" from a guess as the start or the end of the text: it moves one
///   character further, which iOS can't guess, and sees what the app says.
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
        guard await moveToEnd(document, settled: true, log: log, settle: settle) else { return nil }
        // 2. Back to the start, one piece at a time, collecting the text.
        let (text, fromEnd) = await collectBackwards(document, maxLength: maxLength, log: log, settle: settle)
        // 3. To the end again: in one go when it's clear where the cursor is, else step by step.
        var atEnd = false
        if let fromEnd {
            if fromEnd > 0 { document.adjustTextPosition(byCharacterOffset: fromEnd) }
            if let waited = await wait(settle, until: { isCursor(atEndOf: text, in: document) }) {
                log("to the end, waited \(waited): \(describe(document))")
                atEnd = true
            }
        }
        if !atEnd {
            log("to the end, step by step")
            guard await moveToEnd(document, settled: false, log: log, settle: settle) else { return nil }
        }
        guard let text else { return nil }
        guard isCursor(atEndOf: text, in: document) else {
            log("the end of the field isn't the end of the text read: \(describe(document))")
            return nil
        }
        log("read \(text.count) characters")
        return text
    }

    /// Moves the cursor forward by whatever iOS shows after it, until there is nothing more.
    /// `settled`: nothing moved the cursor just now, so what iOS shows comes from the app, and nothing
    /// after the cursor is the end. After a move it may be the end of iOS's guess instead.
    private static func moveToEnd(_ document: TextDocument, settled: Bool, log: (String) -> Void,
                                  settle: () async -> Void) async -> Bool {
        var moved = !settled
        var steps = 0
        while true {
            steps += 1
            guard steps <= 2000 else {
                log("to end: too many steps")
                return false
            }
            let after = document.documentContextAfterInput ?? ""
            if after.isEmpty {
                guard moved else { return true }
                // The end, or only the end of iOS's guess. One character on makes iOS ask the app: at
                // the end nothing changes.
                document.adjustTextPosition(byCharacterOffset: 1)
                guard let waited = await wait(settle, until: { !(document.documentContextAfterInput ?? "").isEmpty }) else {
                    log("to end: one character on, still nothing after the cursor: the end")
                    return true
                }
                log("to end: one character on there was more, waited \(waited): \(describe(document))")
                continue
            }
            document.adjustTextPosition(byCharacterOffset: after.utf16.count)
            moved = true
            // iOS has caught up once it shows something else after the cursor. (Overshooting is
            // harmless here: the cursor stops at the end.)
            guard let waited = await wait(settle, until: { (document.documentContextAfterInput ?? "") != after }) else {
                log("to end: iOS didn't show the new spot. \(describe(document))")
                return false
            }
            log("to end, step \(steps), waited \(waited): \(describe(document))")
        }
    }

    /// From the end of the text back to its start, collecting the text (nil when it can't be read
    /// reliably). Also says how far the cursor ended up from the end, in UTF-16 units like the moves
    /// (nil when that isn't clear).
    private static func collectBackwards(_ document: TextDocument, maxLength: Int, log: (String) -> Void,
                                         settle: () async -> Void) async -> (text: String?, fromEnd: Int?) {
        var text = ""      // everything from the cursor to the end of the field
        var fromEnd = 0
        var steps = 0
        while true {
            steps += 1
            guard steps <= 2000 else {
                log("back: too many steps")
                return (nil, fromEnd)
            }
            let before = document.documentContextBeforeInput ?? ""
            if !before.isEmpty {
                guard text.utf16.count + before.utf16.count <= maxLength else {
                    log("too long: over \(maxLength) characters")
                    return (nil, fromEnd)
                }
                text = before + text
                fromEnd += before.utf16.count
                document.adjustTextPosition(byCharacterOffset: -before.utf16.count)
                // iOS has caught up once what it shows after the cursor is the start of `text`.
                guard let waited = await wait(settle, until: { [text] in isCursor(before: text, in: document) }) else {
                    log("back \(before.count): iOS didn't show the new spot. \(describe(document))")
                    return (nil, nil)
                }
                log("back \(before.count), waited \(waited): \(describe(document))")
                continue
            }

            // Nothing before the cursor: the start of the text, the end of iOS's guess, or a sentence
            // start (WhatsApp shows no further back than that). One character back tells.
            document.adjustTextPosition(byCharacterOffset: -1)
            guard let waited = await wait(settle, until: { [text] in isCursor(oneBefore: text, in: document) }) else {
                log("start of the text (one character back changed nothing): \(describe(document))")
                return (text, fromEnd)
            }
            let shownBefore = document.documentContextBeforeInput ?? ""
            let shownAfter = document.documentContextAfterInput ?? ""
            if !shownBefore.isEmpty, text.utf16.starts(with: (shownBefore + shownAfter).utf16) {
                // That's the start of `text` again. WhatsApp jumps from the very start of the text to
                // the end of the first sentence; or the text repeats itself ("Haha. Haha."). One
                // character forward tells: after a jump it shows text further on, otherwise the start
                // of `text` again.
                let step = shownAfter.first?.utf16.count ?? 1
                let landing = shownBefore.utf16.count + step   // where the cursor is in `text` after a jump
                let rest = Array(text.utf16.dropFirst(landing))
                let jumped: () -> Bool = {
                    let after = document.documentContextAfterInput ?? ""
                    return rest.isEmpty ? after.isEmpty : !after.isEmpty && rest.starts(with: after.utf16)
                }
                document.adjustTextPosition(byCharacterOffset: step)
                let clear = await wait(settle) { [text] in
                    !(document.documentContextAfterInput ?? "").isEmpty && isCursor(before: text, in: document) != jumped()
                }
                guard clear != nil, isCursor(before: text, in: document) else {
                    log("start of the text (one character back jumped elsewhere: \(describe(document)))")
                    let known = jumped() && !isCursor(before: text, in: document)
                    return (text, known ? text.utf16.count - landing : nil)
                }
                document.adjustTextPosition(byCharacterOffset: -step)
                guard await wait(settle, until: { [text] in isCursor(oneBefore: text, in: document) }) != nil else {
                    log("back 1: iOS didn't show the new spot. \(describe(document))")
                    return (nil, nil)
                }
            }
            guard let character = document.documentContextAfterInput?.first else { return (nil, nil) }
            text = String(character) + text
            fromEnd += character.utf16.count
            guard text.utf16.count <= maxLength else {
                log("too long: over \(maxLength) characters")
                return (nil, fromEnd)
            }
            log("nothing before the cursor, but one character back there was more, waited \(waited): \(describe(document))")
        }
    }

    /// Whether iOS shows the cursor right before `rest` (the text from there to the end of the field):
    /// what it shows after the cursor is the start of `rest`. Compared in UTF-16 units, as a window can
    /// end inside a character (a flag, say).
    private static func isCursor(before rest: String, in document: TextDocument) -> Bool {
        let after = document.documentContextAfterInput ?? ""
        return rest.isEmpty ? after.isEmpty : !after.isEmpty && rest.utf16.starts(with: after.utf16)
    }

    /// Whether iOS shows the cursor one character before `rest`: after the cursor, one character and
    /// then the start of `rest`.
    private static func isCursor(oneBefore rest: String, in document: TextDocument) -> Bool {
        let after = document.documentContextAfterInput ?? ""
        guard let first = after.first, !isCursor(before: rest, in: document) else { return false }
        return rest.utf16.starts(with: after.utf16.dropFirst(first.utf16.count))
    }

    /// Whether iOS shows the cursor at the end of `text`: nothing after it, and the end of `text`
    /// before it (anything, when `text` is nil).
    private static func isCursor(atEndOf text: String?, in document: TextDocument) -> Bool {
        guard (document.documentContextAfterInput ?? "").isEmpty else { return false }
        guard let text else { return true }
        let before = document.documentContextBeforeInput ?? ""
        return text.utf16.reversed().starts(with: before.utf16.reversed())
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

    /// Calls `settle` until `condition` holds, at most 40 times (about 1.2 s in the keyboard). Returns
    /// how many times it waited (for the reading log), or nil when the condition never held.
    private static func wait(_ settle: () async -> Void, until condition: () -> Bool) async -> Int? {
        for waited in 0..<40 {
            if condition() { return waited }
            await settle()
        }
        return condition() ? 40 : nil
    }
}
