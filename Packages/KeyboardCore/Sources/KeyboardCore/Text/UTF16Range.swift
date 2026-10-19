import Foundation

/// A range in a string, counted in UTF-16 code units. LanguageTool and UIKit both count this way,
/// so ranges from a grammar check can be used to edit the text field directly.
public struct UTF16Range: Hashable, Codable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }

    public func overlaps(_ other: UTF16Range) -> Bool {
        location < other.end && other.location < end
    }

    /// The `String` indices for this range, or nil if it is out of bounds
    /// or cuts a character in half.
    public func indices(in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard location >= 0, length >= 0, end <= utf16.count else { return nil }
        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: location)
        let upperUTF16 = utf16.index(lowerUTF16, offsetBy: length)
        guard let lower = String.Index(lowerUTF16, within: text),
              let upper = String.Index(upperUTF16, within: text)
        else { return nil }
        return lower..<upper
    }

    /// The text this range covers, or nil if it doesn't fit `text`.
    public func substring(in text: String) -> String? {
        indices(in: text).map { String(text[$0]) }
    }
}
