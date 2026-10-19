import Foundation

/// A simple in-memory text field with a cursor. The translator panel types into one
/// (instead of into the app), and the unit tests use it as a stand-in for the real text field.
public final class TextBuffer: TextDocument {
    public private(set) var beforeCursor: String
    public private(set) var afterCursor = ""

    public init(_ text: String = "") {
        beforeCursor = text
    }

    /// The whole text. Setting it puts the cursor at the end.
    public var text: String {
        get { beforeCursor + afterCursor }
        set {
            beforeCursor = newValue
            afterCursor = ""
        }
    }

    public var documentContextBeforeInput: String? { beforeCursor }
    public var documentContextAfterInput: String? { afterCursor }

    public func insertText(_ text: String) {
        beforeCursor += text
    }

    public func deleteBackward() {
        if !beforeCursor.isEmpty { beforeCursor.removeLast() }
    }

    public func adjustTextPosition(byCharacterOffset offset: Int) {
        var remaining = abs(offset)
        if offset < 0 {
            while remaining > 0, let last = beforeCursor.last {
                beforeCursor.removeLast()
                afterCursor.insert(last, at: afterCursor.startIndex)
                remaining -= last.utf16.count
            }
        } else {
            while remaining > 0, let first = afterCursor.first {
                afterCursor.removeFirst()
                beforeCursor.append(first)
                remaining -= first.utf16.count
            }
        }
    }
}
