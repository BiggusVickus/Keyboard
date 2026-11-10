import XCTest
@testable import KeyboardCore

final class TrackpadEdgeTests: XCTestCase {
    private let width: CGFloat = 390
    private let bottom: CGFloat = 220

    func testMiddleDoesNothing() {
        var scroller = TrackpadEdgeScroller(start: CGPoint(x: 195, y: 150), width: width, bottom: bottom)
        XCTAssertEqual(scroller.velocity(at: CGPoint(x: 200, y: 100)), .zero)
    }

    func testRightEdgeMovesRightFasterCloserToTheEdge() {
        var scroller = TrackpadEdgeScroller(start: CGPoint(x: 195, y: 150), width: width, bottom: bottom)
        let near = scroller.velocity(at: CGPoint(x: width - 25, y: 150))
        let atEdge = scroller.velocity(at: CGPoint(x: width - 1, y: 150))
        XCTAssertGreaterThan(near.width, 0)
        XCTAssertGreaterThan(atEdge.width, near.width)
        XCTAssertEqual(atEdge.height, 0)
        XCTAssertLessThanOrEqual(atEdge.width, TrackpadEdgeScroller.maxSpeed)
    }

    func testLeftEdgeMovesLeftEvenPastTheEdge() {
        var scroller = TrackpadEdgeScroller(start: CGPoint(x: 195, y: 150), width: width, bottom: bottom)
        XCTAssertEqual(scroller.velocity(at: CGPoint(x: -10, y: 150)).width, -TrackpadEdgeScroller.maxSpeed)
    }

    func testStartingNearTheBottomDoesNotScrollUntilTheFingerLeavesTheZone() {
        // The space bar is close to the bottom: holding it must not move the cursor down by itself.
        var scroller = TrackpadEdgeScroller(start: CGPoint(x: 195, y: bottom - 5), width: width, bottom: bottom)
        XCTAssertEqual(scroller.velocity(at: CGPoint(x: 195, y: bottom - 4)), .zero)
        _ = scroller.velocity(at: CGPoint(x: 195, y: bottom - 40))      // up, out of the zone
        XCTAssertGreaterThan(scroller.velocity(at: CGPoint(x: 195, y: bottom - 2)).height, 0)
    }

    func testCornerMovesBothWays() {
        var scroller = TrackpadEdgeScroller(start: CGPoint(x: 195, y: 100), width: width, bottom: bottom)
        let velocity = scroller.velocity(at: CGPoint(x: 2, y: bottom - 1))
        XCTAssertLessThan(velocity.width, 0)
        XCTAssertGreaterThan(velocity.height, 0)
    }
}
