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
    /// The space bar is being used as a trackpad (see `TrackpadSession`).
    @Published private(set) var trackpad: TrackpadSession?
    var isTrackpadActive: Bool { trackpad != nil }

    /// Worked out on every touch from the current layout and the touch view's real width, so they
    /// are never missing or out of date (e.g. right after the keyboard appears).
    private(set) var frames: [KeyFrame] = []
    private(set) var areaWidth: CGFloat = 0
    var hitTester = KeyHitTester(kind: .normal)

    private weak var model: KeyboardViewModel?
    private var touches: [ObjectIdentifier: TrackedTouch] = [:]

    static let longPressDelay: Duration = .milliseconds(380)

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
    }

    init(model: KeyboardViewModel) {
        self.model = model
    }

    // MARK: - Touch events (from KeyboardTouchView)

    func began(_ id: ObjectIdentifier, at point: CGPoint, width: CGFloat) {
        guard let model else { return }
        areaWidth = width
        frames = KeyboardGeometry.frames(for: model.layout, width: width)
        guard let frame = hitTester.frame(at: point, in: frames) else { return }
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
            moveTrackpad(by: CGSize(width: point.x - touch.lastPoint.x, height: point.y - touch.lastPoint.y))
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
            trackpad = nil
        case .committed:
            break
        }
        updatePressed()
    }

    /// Forgets touches iOS no longer knows about. When the key area is replaced mid-touch (a panel
    /// opens, the keyboard hides), the lift is never reported; a delete key stuck "down" would keep
    /// deleting and a stuck trackpad would hide the keys.
    func forgetTouches(except active: Set<ObjectIdentifier>) {
        for id in touches.keys where !active.contains(id) { ended(id, cancelled: true) }
    }

    /// The keyboard disappeared or the layout changed under the finger.
    func reset() {
        for (id, _) in touches { ended(id, cancelled: true) }
        popup = nil
        trackpad = nil
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
                guard let session = self.model?.makeTrackpadSession(
                    size: CGSize(width: self.areaWidth, height: CGFloat(KeyboardMetrics.keyAreaHeight)))
                else { return }
                touch.mode = .trackpad
                self.trackpad = session
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

    /// The floating cursor follows the finger 1:1; the app's cursor follows wherever it snaps.
    private func moveTrackpad(by delta: CGSize) {
        guard let model, let trackpad else { return }
        let offset = trackpad.move(by: delta)
        if offset != 0 {
            model.moveCursor(by: offset)
            model.feedback.cursorStep()
        }
        if trackpad.isNearEdge { model.extendTrackpadText(trackpad) }
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
        let active = Set((event?.allTouches ?? touches).map(ObjectIdentifier.init))
        handler?.forgetTouches(except: active)
        for touch in touches {
            handler?.began(ObjectIdentifier(touch), at: touch.location(in: self), width: bounds.width)
        }
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
