import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Sizes of the key area. The keyboard and the app's touch trainer use the same numbers,
/// so touches recorded in the app line up with the keys in the keyboard.
public enum KeyboardMetrics {
    public static let keySpacing: Double = 6
    public static let rowSpacing: Double = 11
    public static let keyHeight: Double = 43
    /// Space left and right of the outermost keys.
    public static let horizontalPadding: Double = 3
    /// Four rows of keys.
    public static let keyAreaHeight: Double = 4 * keyHeight + 3 * rowSpacing
}

/// Where one key is drawn, in the key area's coordinates (origin top-left, padding included).
public struct KeyFrame: Equatable, Sendable {
    public let key: Key
    public let rect: CGRect
    public let row: Int
    public let index: Int
    /// Number of keys in the row, so popups on the right half can open towards the left.
    public let rowCount: Int

    public var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    public var isOnTrailingHalf: Bool { index >= rowCount / 2 }
}

public enum KeyboardGeometry {
    /// Frames for every key when the key area is `width` points wide.
    /// Letter keys all get the same width, based on the row with the most letters; special keys
    /// (shift, delete, space…) share what is left, in proportion to their `width`.
    public static func frames(for layout: KeyboardLayout, width: Double) -> [KeyFrame] {
        let spacing = KeyboardMetrics.keySpacing
        let inner = width - 2 * KeyboardMetrics.horizontalPadding
        let maxCharacters = Double(layout.rows.map { $0.filter { $0.character != nil }.count }.max() ?? 10)
        let unit = (inner - spacing * (maxCharacters - 1)) / maxCharacters
        // Before the first layout pass the width is 0; negative key sizes would upset SwiftUI.
        guard width.isFinite, unit > 0 else { return [] }

        var frames: [KeyFrame] = []
        for (rowIndex, row) in layout.rows.enumerated() {
            let widths = keyWidths(for: row, unit: unit, total: inner)
            let rowWidth = widths.reduce(0, +) + spacing * Double(max(0, row.count - 1))
            var x = KeyboardMetrics.horizontalPadding + (inner - rowWidth) / 2
            let y = Double(rowIndex) * (KeyboardMetrics.keyHeight + KeyboardMetrics.rowSpacing)
            for (index, key) in row.enumerated() {
                let rect = CGRect(x: x, y: y, width: widths[index], height: KeyboardMetrics.keyHeight)
                frames.append(KeyFrame(key: key, rect: rect, row: rowIndex, index: index, rowCount: row.count))
                x += widths[index] + spacing
            }
        }
        return frames
    }

    static func keyWidths(for row: [Key], unit: Double, total: Double) -> [Double] {
        let characterCount = row.filter { $0.character != nil }.count
        let specialWeight = row.filter { $0.character == nil }.reduce(0.0) { $0 + $1.width }
        guard specialWeight > 0 else { return row.map { _ in unit } }

        let used = Double(characterCount) * unit + KeyboardMetrics.keySpacing * Double(row.count - 1)
        let perWeight = max(0, total - used) / specialWeight
        return row.map { $0.character != nil ? unit : max(0, perWeight * $0.width) }
    }
}
