import XCTest
@testable import KeyboardCore

final class KeyReleaseTests: XCTestCase {
    func testNormalLiftAlwaysTypes() {
        XCTAssertTrue(KeyRelease.typesKey(.lifted, duration: 0.08, travel: 0))
        XCTAssertTrue(KeyRelease.typesKey(.lifted, duration: 2, travel: 40), "slid onto the key and held")
    }

    func testSystemCancelledQuickTapStillTypes() {
        XCTAssertTrue(KeyRelease.typesKey(.cancelledBySystem, duration: 0.09, travel: 2))
    }

    func testSystemCancelledSwipeOrHoldDoesNot() {
        XCTAssertFalse(KeyRelease.typesKey(.cancelledBySystem, duration: 0.15, travel: 60), "a swipe home")
        XCTAssertFalse(KeyRelease.typesKey(.cancelledBySystem, duration: 0.9, travel: 0), "held, then taken over")
        XCTAssertFalse(KeyRelease.typesKey(.cancelledBySystem, duration: nil, travel: 0))
    }

    func testLostLiftTypesAndDiscardedDoesNot() {
        XCTAssertTrue(KeyRelease.typesKey(.lost, duration: nil, travel: 0))
        XCTAssertFalse(KeyRelease.typesKey(.discarded, duration: 0.05, travel: 0))
    }

    func testLongPressThatWasReallyATap() {
        // The popup opened only because the lift was still waiting in the queue.
        XCTAssertTrue(KeyRelease.longPressWasReallyATap(.lifted, duration: 0.12, travel: 3))
        // A real long press.
        XCTAssertFalse(KeyRelease.longPressWasReallyATap(.lifted, duration: 0.6, travel: 3))
        XCTAssertFalse(KeyRelease.longPressWasReallyATap(.lifted, duration: 0.2, travel: 30), "slid to an accent")
        XCTAssertFalse(KeyRelease.longPressWasReallyATap(.discarded, duration: 0.1, travel: 0))
    }
}
