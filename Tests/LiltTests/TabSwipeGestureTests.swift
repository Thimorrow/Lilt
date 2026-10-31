import XCTest
@testable import Lilt

final class TabSwipeGestureTests: XCTestCase {
    func testHorizontalAxisStaysLockedWhenFingersDriftVertically() {
        var gesture = TabSwipeGesture()
        XCTAssertNil(gesture.update(phase: .began, deltaX: -15, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertEqual(gesture.update(phase: .changed, deltaX: -35, deltaY: 80, precise: true, momentum: false, blocked: false), 1)
        XCTAssertEqual(gesture.completionDirection, 1)
    }

    func testCompletionUsesFinalDirectionAfterReversal() {
        var gesture = TabSwipeGesture()
        XCTAssertEqual(gesture.update(phase: .began, deltaX: -50, deltaY: 0, precise: true, momentum: false, blocked: false), 1)
        XCTAssertNil(gesture.update(phase: .changed, deltaX: 100, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertEqual(gesture.completionDirection, -1)
    }
    func testBothDirectionsAndOneTransitionPerGesture() {
        var gesture = TabSwipeGesture()
        XCTAssertNil(gesture.update(phase: .began, deltaX: -10, deltaY: 1, precise: true, momentum: false, blocked: false))
        XCTAssertEqual(gesture.update(phase: .changed, deltaX: -35, deltaY: 0, precise: true, momentum: false, blocked: false), 1)
        XCTAssertNil(gesture.update(phase: .changed, deltaX: -100, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .ended, deltaX: 0, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertEqual(gesture.update(phase: .began, deltaX: 45, deltaY: 2, precise: true, momentum: false, blocked: false), -1)
    }

    func testVerticalScrollingStaysVerticalEvenIfGestureTurns() {
        var gesture = TabSwipeGesture()
        XCTAssertNil(gesture.update(phase: .began, deltaX: 2, deltaY: 15, precise: true, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .changed, deltaX: 100, deltaY: 0, precise: true, momentum: false, blocked: false))
    }

    func testMomentumMouseWheelAndDraggingNeverTrigger() {
        var gesture = TabSwipeGesture()
        XCTAssertNil(gesture.update(phase: .began, deltaX: -100, deltaY: 0, precise: false, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .began, deltaX: -100, deltaY: 0, precise: true, momentum: true, blocked: false))
        XCTAssertNil(gesture.update(phase: .began, deltaX: -100, deltaY: 0, precise: true, momentum: false, blocked: true))
        XCTAssertNil(gesture.update(phase: .changed, deltaX: -100, deltaY: 0, precise: true, momentum: false, blocked: false))
    }

    func testThresholdDirectionAndCancellation() {
        var gesture = TabSwipeGesture()
        XCTAssertNil(gesture.update(phase: .began, deltaX: -20, deltaY: 8, precise: true, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .cancelled, deltaX: -50, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .changed, deltaX: -100, deltaY: 0, precise: true, momentum: false, blocked: false))
        XCTAssertNil(gesture.update(phase: .began, deltaX: -25, deltaY: 20, precise: true, momentum: false, blocked: false))
    }
}
