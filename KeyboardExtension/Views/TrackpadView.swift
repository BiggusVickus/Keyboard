import UIKit
import SwiftUI

/// The space-bar trackpad, modelled on Apple's: a floating cursor glides freely under your finger,
/// and the real cursor snaps to the nearest place in the text. A keyboard can't draw inside the
/// app's text, so the text around the cursor is shown in the key area, laid out by TextKit, with
/// both cursors on it. Every time the snapped position changes the app's cursor is moved along.
@MainActor
final class TrackpadSession {
    static let font = UIFont.systemFont(ofSize: 17)
    static let inset = CGPoint(x: 14, y: 10)

    /// Called after every change, so the view can redraw.
    var onChange: (() -> Void)?

    var text: NSString { storage.string as NSString }
    let viewSize: CGSize
    let storage: NSTextStorage
    let layoutManager = NSLayoutManager()
    let container: NSTextContainer

    /// Where the real cursor is, in UTF-16 units (like `adjustTextPosition`).
    private(set) var caret: Int
    /// Centre of the floating cursor, in text coordinates. Moves freely, not in steps.
    private(set) var floating: CGPoint
    /// How far the text is scrolled up inside the view.
    private(set) var scrollY: CGFloat = 0

    init(before: String, after: String, size: CGSize) {
        viewSize = size
        storage = NSTextStorage(string: before + after, attributes: [
            .font: Self.font,
            .foregroundColor: UIColor.label,
        ])
        container = NSTextContainer(size: CGSize(width: max(1, size.width - 2 * Self.inset.x),
                                                 height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        caret = (before as NSString).length
        floating = .zero
        let rect = caretRect(at: caret)
        floating = CGPoint(x: rect.midX, y: rect.midY)
        scrollToFloating(centered: true)
    }

    var lineHeight: CGFloat { Self.font.lineHeight }

    /// Moves the floating cursor with the finger. Returns how far the real cursor moved (0 = same place).
    func move(by delta: CGSize) -> Int {
        let used = layoutManager.usedRect(for: container)
        let maxY = max(used.maxY, lineHeight) - lineHeight / 2
        floating.x = min(max(floating.x + delta.width, 0), container.size.width)
        floating.y = min(max(floating.y + delta.height, lineHeight / 2), maxY)
        scrollToFloating(centered: false)

        let target = index(at: floating)
        let offset = target - caret
        caret = target
        onChange?()
        return offset
    }

    // MARK: - Reading more text

    /// Close to the start or end of the text the keyboard knows about.
    var isNearEdge: Bool {
        caret < Self.edgeDistance || text.length - caret < Self.edgeDistance
    }
    static let edgeDistance = 80

    /// iOS only shows a keyboard part of the text around the cursor. The app's cursor follows the
    /// trackpad, so once it has moved, iOS shows the text around the new spot: add whatever is new
    /// to this copy. `before` / `after` are what iOS reports around the cursor right now. Nothing
    /// happens if they don't line up with this copy (iOS hasn't caught up with the cursor yet).
    /// The floating cursor stays exactly where it is on screen.
    @discardableResult
    func extend(before: String, after: String) -> Bool {
        let known = text
        let knownBefore = known.substring(to: caret)
        let knownAfter = known.substring(from: caret)
        let beforeMatches = before.hasSuffix(knownBefore) || knownBefore.hasSuffix(before)
        let afterMatches = after.hasPrefix(knownAfter) || knownAfter.hasPrefix(after)
        guard beforeMatches, afterMatches else { return false }

        let newBefore = before as NSString, newAfter = after as NSString
        let prefixLength = max(0, newBefore.length - (knownBefore as NSString).length)
        let suffixStart = (knownAfter as NSString).length
        let prefix = prefixLength > 0 ? newBefore.substring(to: prefixLength) : ""
        let suffix = newAfter.length > suffixStart ? newAfter.substring(from: suffixStart) : ""
        guard !prefix.isEmpty || !suffix.isEmpty else { return false }

        let oldRect = caretRect(at: caret)
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: UIColor.label]
        storage.beginEditing()
        if !suffix.isEmpty {
            storage.append(NSAttributedString(string: suffix, attributes: attributes))
        }
        if !prefix.isEmpty {
            storage.insert(NSAttributedString(string: prefix, attributes: attributes), at: 0)
        }
        storage.endEditing()
        layoutManager.ensureLayout(for: container)
        caret += (prefix as NSString).length

        // Text added above pushes everything down; move the view along so nothing jumps.
        let newRect = caretRect(at: caret)
        floating.x += newRect.minX - oldRect.minX
        floating.y += newRect.minY - oldRect.minY
        scrollY += newRect.minY - oldRect.minY
        scrollToFloating(centered: false)
        onChange?()
        return true
    }

    // MARK: - Text geometry

    /// The thin cursor line at a UTF-16 position, in text coordinates.
    func caretRect(at index: Int) -> CGRect {
        guard text.length > 0 else { return CGRect(x: 0, y: 0, width: 2, height: lineHeight) }
        if index >= text.length {
            let extra = layoutManager.extraLineFragmentRect
            if !extra.isEmpty { return CGRect(x: extra.minX, y: extra.minY, width: 2, height: extra.height) }
            let rect = glyphRect(forCharacterAt: text.length - 1)
            return CGRect(x: rect.maxX, y: rect.minY, width: 2, height: rect.height)
        }
        let rect = glyphRect(forCharacterAt: index)
        return CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
    }

    /// The cursor position closest to a point, never inside an emoji or other multi-part character.
    func index(at point: CGPoint) -> Int {
        guard text.length > 0 else { return 0 }
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty, point.y >= extra.minY { return text.length }  // empty line after a final newline

        var fraction: CGFloat = 0
        let hit = layoutManager.characterIndex(for: point, in: container,
                                               fractionOfDistanceBetweenInsertionPoints: &fraction)
        var index = fraction > 0.5 ? hit + 1 : hit
        // Right of a line that ends in a newline: stay on that line, before the newline.
        if hit < text.length, text.character(at: hit) == 0x0A { index = hit }
        index = min(max(index, 0), text.length)
        if index < text.length { index = text.rangeOfComposedCharacterSequence(at: index).location }
        return index
    }

    private func glyphRect(forCharacterAt index: Int) -> CGRect {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
    }

    /// Keeps the floating cursor visible, scrolling the text when it nears the top or bottom.
    private func scrollToFloating(centered: Bool) {
        let visible = viewSize.height - 2 * Self.inset.y
        let used = layoutManager.usedRect(for: container).maxY
        let maxScroll = max(0, max(used, layoutManager.extraLineFragmentRect.maxY) - visible)
        if centered {
            scrollY = floating.y - visible / 2
        } else {
            let margin = lineHeight * 1.2
            if floating.y - scrollY < margin { scrollY = floating.y - margin }
            if floating.y - scrollY > visible - margin { scrollY = floating.y - visible + margin }
        }
        scrollY = min(max(scrollY, 0), maxScroll)
    }
}

/// Draws a trackpad session: the text, a grey "landing" cursor, and the blue floating cursor.
final class TrackpadTextView: UIView {
    var session: TrackpadSession? {
        didSet {
            session?.onChange = { [weak self] in self?.setNeedsDisplay() }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let session, let context = UIGraphicsGetCurrentContext() else { return }
        context.clip(to: bounds)
        let origin = CGPoint(x: TrackpadSession.inset.x, y: TrackpadSession.inset.y - session.scrollY)

        // UIColor.label resolves here, so the text follows light and dark mode.
        let glyphs = session.layoutManager.glyphRange(for: session.container)
        session.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)

        // Where the cursor lands when you let go (the real cursor in the app is here too).
        let landing = session.caretRect(at: session.caret).offsetBy(dx: origin.x, dy: origin.y)
        UIColor.secondaryLabel.withAlphaComponent(0.5).setFill()
        UIBezierPath(roundedRect: landing, cornerRadius: 1).fill()

        // The floating cursor under your finger, like Apple's: a bold blue bar.
        let height = session.lineHeight * 1.15
        let floating = CGRect(x: session.floating.x + origin.x - 1.5,
                              y: session.floating.y + origin.y - height / 2,
                              width: 3, height: height)
        UIColor.systemBlue.setFill()
        UIBezierPath(roundedRect: floating, cornerRadius: 1.5).fill()
    }
}

struct TrackpadPanel: UIViewRepresentable {
    let session: TrackpadSession

    func makeUIView(context: Context) -> TrackpadTextView {
        let view = TrackpadTextView()
        view.session = session
        return view
    }

    func updateUIView(_ view: TrackpadTextView, context: Context) {
        if view.session !== session { view.session = session }
    }
}
