import UIKit
import KeyboardCore

/// The long-press popup (accents, ¡ ¿ °, other currencies, .com / .nl …).
struct AlternatesPopup: Equatable {
    let keyID: String
    /// In the order they are drawn, left to right.
    let options: [String]
    /// One rectangle per option, in key-area coordinates.
    let cells: [CGRect]
    /// The background behind the cells.
    let frame: CGRect
    var selected: Int?
}

/// Turns raw touches on the key area into key presses. Every touch goes to the key the hit tester
/// picks (so taps between keys still count, and the trained touch map is used), feedback plays on
/// touch down, and a new finger landing commits the previous key at once for fast, rolling typing.
@MainActor
final class KeyTouchHandler: ObservableObject {
    @Published private(set) var pressedKeyIDs: Set<String> = []
    @Published private(set) var popup: AlternatesPopup?
    @Published private(set) var isTrackpadActive = false

    /// Set by the view whenever the layout or size changes.
    var frames: [KeyFrame] = []
    var areaWidth: CGFloat = 0
    var hitTester = KeyHitTester(kind: .normal)

    private weak var model: KeyboardViewModel?
    private var touches: [ObjectIdentifier: TrackedTouch] = [:]

    static let longPressDelay: Duration = .milliseconds(380)
    /// Finger travel per cursor step on the trackpad. Like a crane: the trolley (left/right) and the
    /// winch (up/down) each move steadily on their own, one character or one line per step.
    static let trackpadStepX: CGFloat = 8
    static let trackpadStepY: CGFloat = 30

    private enum Mode {
        case key
        case delete
        case popup
        case trackpad
        /// Already typed because another finger came down; lifting it does nothing.
        case committed
    }

    private struct TrackedTouch {
        var frame: KeyFrame
        var mode: Mode
        var longPress: Task<Void, Never>?
        var lastPoint: CGPoint
        var trackpadX: CGFloat = 0
        var trackpadY: CGFloat = 0
    }

    init(model: KeyboardViewModel) {
        self.model = model
    }

    // MARK: - Touch events (from KeyboardTouchView)

    func began(_ id: ObjectIdentifier, at point: CGPoint) {
        guard let model, let frame = hitTester.frame(at: point, in: frames) else { return }
        commitPendingKeys()

        let key = frame.key
        model.feedback.keyDown(key.kind)
        var touch = TrackedTouch(frame: frame, mode: .key, lastPoint: point)

        switch key.kind {
        case .delete:
            touch.mode = .delete
            model.deletePressed()
        case .shift:
            // Shift reacts on touch down, so a quick shift + letter never comes out lowercase.
            model.tap(key)
            touch.mode = .committed
        default:
            touch.longPress = scheduleLongPress(for: id, key: key)
        }
        touches[id] = touch
        updatePressed()
    }

    func moved(_ id: ObjectIdentifier, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        defer { touches[id] = touch }

        switch touch.mode {
        case .popup:
            if var current = popup {
                current.selected = Self.option(atX: point.x, in: current.cells)
                if current != popup { popup = current }
            }
        case .trackpad:
            moveTrackpad(&touch, to: point)
        case .key:
            // Sliding onto another key before lifting types that key instead, like iOS.
            // The space bar is left alone so a slightly sliding thumb doesn't jump keys.
            guard touch.frame.key.kind != .space,
                  let frame = hitTester.frame(at: point, in: frames),
                  frame.key.id != touch.frame.key.id
            else { return }
            touch.longPress?.cancel()
            touch.frame = frame
            touch.longPress = scheduleLongPress(for: id, key: frame.key)
            touches[id] = touch
            updatePressed()
        case .delete, .committed:
            break
        }
        touch.lastPoint = point
    }

    func ended(_ id: ObjectIdentifier, cancelled: Bool = false) {
        guard let touch = touches.removeValue(forKey: id), let model else { return }
        touch.longPress?.cancel()

        switch touch.mode {
        case .key:
            if !cancelled { model.tap(touch.frame.key) }
        case .delete:
            model.deleteReleased()
        case .popup:
            if !cancelled, let current = popup, let index = current.selected {
                model.insertAlternate(current.options[index])
            }
            popup = nil
        case .trackpad:
            model.trackpadEnded()
            isTrackpadActive = false
        case .committed:
            break
        }
        updatePressed()
    }

    /// The keyboard disappeared or the layout changed under the finger.
    func reset() {
        for (id, _) in touches { ended(id, cancelled: true) }
        popup = nil
        isTrackpadActive = false
    }

    // MARK: - Long press

    private func scheduleLongPress(for id: ObjectIdentifier, key: Key) -> Task<Void, Never>? {
        let wantsTrackpad = key.kind == .space && (model?.trackpadAvailable ?? false)
        guard !key.alternates.isEmpty || wantsTrackpad else { return nil }
        return Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.longPressDelay)
            guard !Task.isCancelled, let self, var touch = self.touches[id], touch.mode == .key,
                  touch.frame.key.id == key.id
            else { return }
            if wantsTrackpad {
                touch.mode = .trackpad
                self.model?.trackpadBegan()
                self.isTrackpadActive = true
                self.model?.feedback.trackpadStarted()
            } else {
                touch.mode = .popup
                self.popup = self.makePopup(for: touch.frame)
            }
            self.touches[id] = touch
        }
    }

    /// When a new finger lands, keys still held by other fingers are typed right away.
    private func commitPendingKeys() {
        for (id, var touch) in touches where touch.mode == .key
            && (touch.frame.key.character != nil || touch.frame.key.kind == .space) {
            touch.longPress?.cancel()
            touch.longPress = nil
            touch.mode = .committed
            touches[id] = touch
            model?.tap(touch.frame.key)
        }
    }

    private func updatePressed() {
        let ids = Set(touches.values.filter { $0.mode != .committed || $0.frame.key.kind == .shift }
            .map(\.frame.key.id))
        if ids != pressedKeyIDs { pressedKeyIDs = ids }
    }

    // MARK: - Popup

    private func makePopup(for frame: KeyFrame) -> AlternatesPopup {
        let key = frame.key
        let opensLeft = frame.isOnTrailingHalf
        let shifted = model?.shift != .off
        // Closest to the finger first: on the right half the popup grows to the left, so reverse it.
        let raw = key.alternates.map { $0.hasPrefix(".") || !shifted ? $0 : $0.uppercased() }
        let options = opensLeft ? Array(raw.reversed()) : raw

        let padding: CGFloat = 4
        let height = frame.rect.height
        let widths = options.map { max(frame.rect.width, CGFloat($0.count) * 12 + 14) }
        let totalWidth = widths.reduce(0, +) + 2 * padding
        var x = opensLeft ? frame.rect.maxX - totalWidth : frame.rect.minX
        x = min(max(x, 0), max(0, areaWidth - totalWidth))
        let top = frame.rect.minY - height + 4

        var cells: [CGRect] = []
        var cellX = x + padding
        for width in widths {
            cells.append(CGRect(x: cellX, y: top + padding, width: width, height: height - 2 * padding))
            cellX += width
        }
        let selected = opensLeft ? options.count - 1 : 0
        return AlternatesPopup(keyID: key.id, options: options, cells: cells,
                               frame: CGRect(x: x, y: top, width: totalWidth, height: height),
                               selected: selected)
    }

    static func option(atX x: CGFloat, in cells: [CGRect]) -> Int? {
        guard let first = cells.first, let last = cells.last else { return nil }
        if x < first.minX { return 0 }
        if x >= last.maxX { return cells.count - 1 }
        return cells.firstIndex { x >= $0.minX && x < $0.maxX }
    }

    // MARK: - Trackpad

    private func moveTrackpad(_ touch: inout TrackedTouch, to point: CGPoint) {
        guard let model else { return }
        let dx = point.x - touch.lastPoint.x
        let dy = point.y - touch.lastPoint.y
        touch.trackpadX += dx
        touch.trackpadY += dy
        // A sideways drag with a little wobble shouldn't change lines (and the other way round):
        // movement along one axis slowly drains what was gathered on the other.
        if abs(dx) > 2 * abs(dy) { touch.trackpadY *= 0.9 }
        if abs(dy) > 2 * abs(dx) { touch.trackpadX *= 0.9 }
        let lineLength = max(20, Int(areaWidth / 9))

        while abs(touch.trackpadX) >= Self.trackpadStepX {
            let right = touch.trackpadX > 0
            touch.trackpadX -= right ? Self.trackpadStepX : -Self.trackpadStepX
            if model.moveCursor(right ? .right : .left, lineLength: lineLength) { model.feedback.cursorStep() }
        }
        while abs(touch.trackpadY) >= Self.trackpadStepY {
            let down = touch.trackpadY > 0
            touch.trackpadY -= down ? Self.trackpadStepY : -Self.trackpadStepY
            if model.moveCursor(down ? .down : .up, lineLength: lineLength) { model.feedback.cursorStep() }
        }
    }
}

/// A transparent view over the key area that receives every touch directly from UIKit.
/// One view for all keys means several fingers can type at once with no gesture delays.
final class KeyboardTouchView: UIView {
    weak var handler: KeyTouchHandler?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handler?.began(ObjectIdentifier(touch), at: touch.location(in: self)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handler?.moved(ObjectIdentifier(touch), to: touch.location(in: self)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handler?.ended(ObjectIdentifier(touch)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handler?.ended(ObjectIdentifier(touch), cancelled: true) }
    }
}
