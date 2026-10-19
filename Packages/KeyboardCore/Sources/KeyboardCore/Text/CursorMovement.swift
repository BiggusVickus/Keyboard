import Foundation

/// Cursor steps for the space-bar trackpad. A keyboard can only move the cursor by a number of
/// characters, so moving up or down is worked out from the text around the cursor: newlines mark
/// real lines, and long paragraphs are split into lines of about `lineLength` characters
/// (an estimate, since the keyboard can't see how the app wraps its text).
/// All offsets are UTF-16 code units, like `adjustTextPosition(byCharacterOffset:)`.
public enum CursorMovement {
    /// One character left; 0 at the start of the text.
    public static func left(before: String) -> Int {
        guard let last = before.last else { return 0 }
        return -last.utf16.count
    }

    /// One character right; 0 at the end of the text.
    public static func right(after: String) -> Int {
        guard let first = after.first else { return 0 }
        return first.utf16.count
    }

    /// One line up: the same column on the line above; 0 on the first line (no jump to the start).
    public static func up(before: String, lineLength: Int) -> Int {
        let width = max(lineLength, 1)
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false)
        let current = lines.last.map(String.init) ?? ""
        let column = current.utf16.count

        // Inside a wrapped paragraph: one visual line back.
        if column >= width { return -width }

        guard lines.count >= 2 else { return 0 }  // first line: stay put
        let previous = String(lines[lines.count - 2]).utf16.count
        // Last visual line of the previous paragraph, same column if it's long enough.
        let lastLineStart = (previous / width) * width
        let target = min(lastLineStart + column, previous)
        return -(column + 1 + (previous - target))
    }

    /// One line down: the same column on the line below; 0 on the last line (no jump to the end).
    public static func down(before: String, after: String, lineLength: Int) -> Int {
        let width = max(lineLength, 1)
        let column = (before.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? "")
            .utf16.count
        let lines = after.split(separator: "\n", omittingEmptySubsequences: false)
        let restOfLine = (lines.first.map(String.init) ?? "").utf16.count
        let visualColumn = column % width

        // The paragraph continues on another visual line.
        if column / width < (column + restOfLine) / width { return min(width, restOfLine) }

        guard lines.count >= 2 else { return 0 }  // last line: stay put
        let next = String(lines[1]).utf16.count
        return restOfLine + 1 + min(visualColumn, next)
    }
}

/// The cursor during one space-bar drag. It keeps its own copy of the text around the cursor and
/// moves it along with every step, because the app's copy (`documentContextBeforeInput`) is
/// updated a moment later; working from that stale copy made the cursor jump to odd places.
public final class TrackpadCursor {
    private let buffer: TextBuffer

    public init(before: String, after: String) {
        // Put all the text in, then move the cursor back over the part that comes after it.
        buffer = TextBuffer(before + after)
        buffer.adjustTextPosition(byCharacterOffset: -after.utf16.count)
    }

    public var before: String { buffer.beforeCursor }
    public var after: String { buffer.afterCursor }

    /// Offset to send to the text field for one step, already applied to this copy. 0 = can't move.
    public func step(_ direction: CursorDirection, lineLength: Int) -> Int {
        let offset = switch direction {
        case .left: CursorMovement.left(before: before)
        case .right: CursorMovement.right(after: after)
        case .up: CursorMovement.up(before: before, lineLength: lineLength)
        case .down: CursorMovement.down(before: before, after: after, lineLength: lineLength)
        }
        if offset != 0 { buffer.adjustTextPosition(byCharacterOffset: offset) }
        return offset
    }
}

public enum CursorDirection: Sendable {
    case left, right, up, down
}
