import UIKit
import os
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
/// A tap is never silently lost: if iOS cancels it, or a busy moment makes it look like a long press,
/// the touch's own timestamps decide (see `KeyRelease`).
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

    /// Keeps the trackpad cursor moving while the finger rests at the screen edge.
    private var edgeScroller: TrackpadEdgeScroller?
    private var edgeVelocity: CGSize = .zero
    private var edgeScrollTask: Task<Void, Never>?
    /// Which edge-scroll task is current, so a stopped one can't clear a newer one when it ends.
    private var edgeScrollRun = 0

    static let longPressDelay: Duration = .seconds(KeyRelease.longPressDelay)
    /// Shows up in Xcode's console (filter on "touch") to see when iOS cancels touches.
    private static let log = Logger(subsystem: "Taalhulp.keyboard", category: "touch")

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
        let startPoint: CGPoint
        /// `UITouch.timestamp` when the finger landed (seconds since the phone started).
        let startTime: TimeInterval
        /// Farthest the finger got from where it landed, in points.
        var travel: CGFloat = 0
        /// The trackpad moved the cursor; lifting then is never a tap on space.
        var movedCursor = false
    }

    init(model: KeyboardViewModel) {
        self.model = model
    }

    // MARK: - Touch events (from KeyboardTouchView)

    func began(_ id: ObjectIdentifier, at point: CGPoint, time: TimeInterval, width: CGFloat) {
        guard let model else { return }
        areaWidth = width
        frames = KeyboardGeometry.frames(for: model.layout, width: width)
        guard let frame = hitTester.frame(at: point, in: frames) else { return }
        commitPendingKeys()

        let key = frame.key
        model.feedback.keyDown(key.kind)
        var touch = TrackedTouch(frame: frame, mode: .key, lastPoint: point, startPoint: point, startTime: time)

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
        touch.travel = max(touch.travel, hypot(point.x - touch.startPoint.x, point.y - touch.startPoint.y))
        defer { touches[id] = touch }

        switch touch.mode {
        case .popup:
            if var current = popup {
                current.selected = Self.option(atX: point.x, in: current.cells)
                if current != popup { popup = current }
            }
        case .trackpad:
            if moveTrackpad(by: CGSize(width: point.x - touch.lastPoint.x, height: point.y - touch.lastPoint.y)) {
                touch.movedCursor = true
            }
            if var scroller = edgeScroller {
                edgeVelocity = scroller.velocity(at: point)
                edgeScroller = scroller
                if edgeVelocity != .zero { startEdgeScroll(for: id) }
            }
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

    /// - Parameter time: `UITouch.timestamp` of the lift or cancel; nil when unknown.
    func ended(_ id: ObjectIdentifier, at time: TimeInterval? = nil, how: KeyRelease.How = .lifted) {
        guard let touch = touches.removeValue(forKey: id), let model else { return }
        touch.longPress?.cancel()
        let key = touch.frame.key
        let duration = time.map { $0 - touch.startTime }
        let travel = Double(touch.travel)
        let milliseconds = Int((duration ?? -0.001) * 1000)

        switch touch.mode {
        case .key:
            let types = KeyRelease.typesKey(how, duration: duration, travel: travel)
            if types { model.tap(key) }
            if how == .cancelledBySystem || how == .lost {
                let what = how == .lost ? "lost" : "cancelled by iOS"
                let result = types ? "typed" : "dropped"
                Self.log.notice("Touch on \(key.id, privacy: .public) \(what, privacy: .public) after \(milliseconds) ms, moved \(Int(travel)) pt: \(result, privacy: .public)")
            }
        case .delete:
            model.deleteReleased()
        case .popup:
            let current = popup
            popup = nil
            if KeyRelease.longPressWasReallyATap(how, duration: duration, travel: travel) {
                // The popup only opened because the lift was still waiting while the keyboard was busy.
                Self.log.notice("Popup on \(key.id, privacy: .public) after only \(milliseconds) ms: typed as a tap")
                model.tap(key)
            } else if how == .lifted, let current, let index = current.selected {
                model.insertAlternate(current.options[index])
            }
        case .trackpad:
            trackpad = nil
            stopEdgeScroll()
            if !touch.movedCursor, KeyRelease.longPressWasReallyATap(how, duration: duration, travel: travel) {
                Self.log.notice("Trackpad after only \(milliseconds) ms: typed a space")
                model.tap(key)
            }
        case .committed:
            break
        }
        updatePressed()
    }

    /// Ends touches iOS no longer knows about. Their lift was never reported (it happens when the key
    /// area is replaced mid-touch); a delete key stuck "down" would keep deleting and a stuck trackpad
    /// would hide the keys. The finger is evidently up, so a plain key press is still typed.
    func forgetTouches(except active: Set<ObjectIdentifier>) {
        for id in touches.keys where !active.contains(id) { ended(id, how: .lost) }
    }

    /// The keyboard disappeared or the layout changed under the finger.
    func reset() {
        for (id, _) in touches { ended(id, how: .discarded) }
        popup = nil
        trackpad = nil
        stopEdgeScroll()
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
                // The screen ends a little below the key area (the padding under the bottom row).
                self.edgeScroller = TrackpadEdgeScroller(
                    start: touch.lastPoint, width: self.areaWidth,
                    bottom: CGFloat(KeyboardMetrics.keyAreaHeight) + KeyboardView.bottomPadding)
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

    /// While the finger rests at the screen edge, keeps moving the cursor about 60 times a second
    /// (see `TrackpadEdgeScroller`). Stops as soon as the finger leaves the edge or lifts.
    private func startEdgeScroll(for id: ObjectIdentifier) {
        guard edgeScrollTask == nil else { return }
        edgeScrollRun += 1
        let run = edgeScrollRun
        edgeScrollTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled, self.trackpad != nil, self.edgeVelocity != .zero else { break }
                let now = clock.now
                let elapsed = now - last
                last = now
                // Capped, so a stall (busy main thread) doesn't make the cursor jump.
                let seconds = min(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 0.05)
                let step = CGSize(width: self.edgeVelocity.width * seconds, height: self.edgeVelocity.height * seconds)
                if self.moveTrackpad(by: step, autoScroll: true) { self.touches[id]?.movedCursor = true }
            }
            if let self, self.edgeScrollRun == run { self.edgeScrollTask = nil }
        }
    }

    private func stopEdgeScroll() {
        edgeScrollTask?.cancel()
        edgeScrollTask = nil
        edgeScroller = nil
        edgeVelocity = .zero
    }

    /// The floating cursor follows the finger 1:1; the app's cursor follows wherever it snaps.
    /// `autoScroll`: moved by the screen edge, not the finger (runs on through line ends).
    /// Returns true when the app's cursor moved.
    private func moveTrackpad(by delta: CGSize, autoScroll: Bool = false) -> Bool {
        guard let model, let trackpad else { return false }
        let offset = autoScroll ? trackpad.autoMove(by: delta) : trackpad.move(by: delta)
        if offset != 0 {
            model.moveCursor(by: offset)
            model.feedback.cursorStep()
        }
        if trackpad.isNearEdge { model.extendTrackpadText(trackpad) }
        return offset != 0
    }
}

/// A transparent view over the key area that receives every touch directly from UIKit.
/// One view for all keys means several fingers can type at once with no gesture delays.
final class KeyboardTouchView: UIView {
    weak var handler: KeyTouchHandler?
    /// The view reaches this far above the top row (over the bottom of the suggestion bar), so a tap
    /// that lands just above Q…P still types. Points are passed on in key-area coordinates.
    var topReach: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // Not .clear: iOS doesn't deliver touches to a keyboard extension where its pixels are fully
        // transparent, so taps in the gaps between keys would never arrive. 1 % white is invisible
        // but counts as "something there".
        backgroundColor = UIColor(white: 1, alpha: 0.01)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func keyAreaPoint(of touch: UITouch) -> CGPoint {
        let point = touch.location(in: self)
        return CGPoint(x: point.x, y: point.y - topReach)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = Set((event?.allTouches ?? touches).map(ObjectIdentifier.init))
        handler?.forgetTouches(except: active)
        // Oldest first, so two fingers landing in the same instant are typed in the right order.
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            handler?.began(ObjectIdentifier(touch), at: keyAreaPoint(of: touch), time: touch.timestamp,
                           width: bounds.width)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handler?.moved(ObjectIdentifier(touch), to: keyAreaPoint(of: touch)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            handler?.ended(ObjectIdentifier(touch), at: touch.timestamp, how: .lifted)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            handler?.ended(ObjectIdentifier(touch), at: touch.timestamp, how: .cancelledBySystem)
        }
    }
}
