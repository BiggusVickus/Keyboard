import Foundation

/// The bits of the text field the keyboard can see and change.
/// In the keyboard this wraps `UITextDocumentProxy`; in tests it is a simple fake.
public protocol TextDocument: AnyObject {
    var documentContextBeforeInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
}

public enum ShiftState: Sendable {
    case off
    /// Next letter is uppercase, then shift turns off again.
    case once
    case capsLock
}

/// Typing rules that don't depend on UIKit: shift, auto-capitalisation,
/// double-space-for-period. Kept separate so it can be unit tested.
public final class TypingEngine {
    public private(set) var shift: ShiftState = .off
    public var autoCapitalize = true

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
        shift = Self.shouldCapitalize(after: document.documentContextBeforeInput) ? .once : .off
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
}
