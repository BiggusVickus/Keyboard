import Foundation

/// The bits of the text field the keyboard can see and change.
/// In the keyboard this wraps `UITextDocumentProxy`; in the translator and in tests it is a `TextBuffer`.
public protocol TextDocument: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    func insertText(_ text: String)
    /// Deletes one character (grapheme) before the cursor.
    func deleteBackward()
    /// Moves the cursor. Like UIKit, the offset counts UTF-16 code units.
    func adjustTextPosition(byCharacterOffset offset: Int)
}

public enum ShiftState: Sendable {
    case off
    /// Next letter is uppercase, then shift turns off again.
    case once
    case capsLock
}

/// What the text field asks for (mirrors `UITextAutocapitalizationType`).
public enum AutocapitalizationMode: Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

/// Typing rules that don't depend on UIKit: shift, auto-capitalisation,
/// double-space-for-period. Kept separate so it can be unit tested.
public final class TypingEngine {
    public private(set) var shift: ShiftState = .off
    /// The user's setting (Settings → Typing).
    public var autoCapitalize = true
    /// What the current text field wants. Only used when `autoCapitalize` is on.
    public var capitalizationMode: AutocapitalizationMode = .sentences

    private let document: TextDocument
    private let now: () -> Date
    private var lastShiftTap: Date?
    private var lastKeyWasSpace = false

    /// Two shift taps closer together than this turn on caps lock.
    static let doubleTapInterval: TimeInterval = 0.35

    public init(document: TextDocument, now: @escaping () -> Date = Date.init) {
        self.document = document
        self.now = now
    }

    // MARK: - Keys

    public func type(_ character: String) {
        let text = shift == .off ? character : character.uppercased()
        document.insertText(text)
        lastKeyWasSpace = false
        if shift == .once { shift = .off }
        updateAutoCapitalization()
    }

    /// Inserts text exactly as given, ignoring shift (".com" stays lowercase). Shift-once is used up.
    public func insertLiteral(_ text: String) {
        document.insertText(text)
        lastKeyWasSpace = false
        if shift == .once { shift = .off }
        updateAutoCapitalization()
    }

    public func space() {
        // Double space after a word becomes ". " like the system keyboard.
        if lastKeyWasSpace, let before = document.documentContextBeforeInput,
           before.hasSuffix(" "), let previous = before.dropLast().last,
           previous.isLetter || previous.isNumber {
            document.deleteBackward()
            document.insertText(". ")
            lastKeyWasSpace = false
        } else {
            document.insertText(" ")
            lastKeyWasSpace = true
        }
        updateAutoCapitalization()
    }

    public func newline() {
        document.insertText("\n")
        lastKeyWasSpace = false
        updateAutoCapitalization()
    }

    public func deleteBackward() {
        document.deleteBackward()
        lastKeyWasSpace = false
        updateAutoCapitalization()
    }

    /// Call after the keyboard changed the text without going through the keys
    /// (a suggestion, a grammar fix, a translation…).
    public func noteExternalEdit() {
        lastKeyWasSpace = false
        updateAutoCapitalization()
    }

    public func shiftTapped() {
        let time = now()
        defer { lastShiftTap = time }

        switch shift {
        case .capsLock:
            shift = .off
        case .once:
            if let last = lastShiftTap, time.timeIntervalSince(last) < Self.doubleTapInterval {
                shift = .capsLock
            } else {
                shift = .off
            }
        case .off:
            shift = .once
        }
    }

    // MARK: - Auto-capitalisation

    /// Call this whenever the text or cursor may have changed (e.g. `textDidChange`).
    public func updateAutoCapitalization() {
        guard shift != .capsLock else { return }
        guard autoCapitalize else {
            shift = .off
            return
        }
        let context = document.documentContextBeforeInput
        let capitalize: Bool
        switch capitalizationMode {
        case .none: capitalize = false
        case .sentences: capitalize = Self.shouldCapitalize(after: context)
        case .words: capitalize = Self.isAtWordStart(context)
        case .allCharacters: capitalize = true
        }
        shift = capitalize ? .once : .off
    }

    /// True at the start of the text, after a newline, or after ". ", "! ", "? ".
    static func shouldCapitalize(after context: String?) -> Bool {
        guard let context, !context.isEmpty else { return true }
        guard let last = context.last else { return true }
        if last == "\n" { return true }
        guard last == " " else { return false }

        let trimmed = context.trimmingCharacters(in: .whitespaces)
        guard let lastNonSpace = trimmed.last else { return true }
        return lastNonSpace == "." || lastNonSpace == "!" || lastNonSpace == "?" || lastNonSpace == "\n"
    }

    /// True at the start of the text or right after a space or newline.
    static func isAtWordStart(_ context: String?) -> Bool {
        guard let last = context?.last else { return true }
        return last.isWhitespace
    }
}
