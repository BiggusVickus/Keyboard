import Foundation

/// Keeps the trackpad cursor moving while the finger rests at the edge of the screen, where it
/// can't move any further: left and right, and the bottom (moving up has the whole app above it).
/// The closer to the edge, the faster. An edge only starts once the finger has been outside its
/// zone, so a finger that starts on the space bar (close to the bottom) doesn't scroll by itself.
public struct TrackpadEdgeScroller: Sendable {
    public enum Edge: CaseIterable, Sendable { case left, right, bottom }

    /// How close to each edge (points) the finger must be.
    public static let sideZone: CGFloat = 28
    public static let bottomZone: CGFloat = 12
    /// Points per second at the inner border of a zone, and right at the edge.
    public static let minSpeed: CGFloat = 120
    public static let maxSpeed: CGFloat = 900
    /// Lines are taller than letters are wide: go up and down more slowly.
    public static let verticalFactor: CGFloat = 0.4

    /// The key area's width, and where the screen ends below it (in key-area coordinates).
    public let width: CGFloat
    public let bottom: CGFloat
    private var armed: Set<Edge> = []

    public init(start: CGPoint, width: CGFloat, bottom: CGFloat) {
        self.width = width
        self.bottom = bottom
        armed = Set(Edge.allCases.filter { depth(of: start, at: $0) == nil })
    }

    /// How fast the cursor should keep moving (points per second); zero outside the edge zones.
    public mutating func velocity(at point: CGPoint) -> CGSize {
        var velocity = CGSize.zero
        for edge in Edge.allCases {
            guard let depth = depth(of: point, at: edge) else {
                armed.insert(edge)
                continue
            }
            guard armed.contains(edge) else { continue }
            let speed = Self.speed(depth)
            switch edge {
            case .left: velocity.width = -speed
            case .right: velocity.width = speed
            case .bottom: velocity.height = speed * Self.verticalFactor
            }
        }
        return velocity
    }

    /// 0 at the inner border of the zone, 1 at the edge or beyond; nil outside the zone.
    func depth(of point: CGPoint, at edge: Edge) -> CGFloat? {
        let distance: CGFloat
        let zone: CGFloat
        switch edge {
        case .left: (distance, zone) = (point.x, Self.sideZone)
        case .right: (distance, zone) = (width - point.x, Self.sideZone)
        case .bottom: (distance, zone) = (bottom - point.y, Self.bottomZone)
        }
        guard distance < zone else { return nil }
        return min(max(1 - distance / zone, 0), 1)
    }

    /// Starts slow so a finger that only just reaches the zone has control, then speeds up.
    static func speed(_ depth: CGFloat) -> CGFloat {
        minSpeed + (maxSpeed - minSpeed) * depth * depth
    }
}
