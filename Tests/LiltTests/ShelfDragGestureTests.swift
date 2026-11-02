import XCTest
@testable import Lilt

final class ShelfDragGestureTests: XCTestCase {
    private let urls = [URL(fileURLWithPath: "/tmp/first.txt"), URL(fileURLWithPath: "/tmp/folder")]
    private let frame = CGRect(x: 10, y: 20, width: 200, height: 40)

    func testDragStartsOnlyAfterMovementAndKeepsEntirePreparedSelection() {
        var drag = ShelfDragGesture()
        drag.mouseDown(at: CGPoint(x: 30, y: 35))
        drag.prepare(urls: urls, ids: ["a", "b"], frame: frame)
        XCTAssertNil(drag.drag(at: CGPoint(x: 32, y: 36)))
        let started = drag.drag(at: CGPoint(x: 40, y: 36))
        XCTAssertEqual(started?.urls, urls)
        XCTAssertEqual(started?.ids, ["a", "b"])
        XCTAssertEqual(started?.origin, CGPoint(x: 30, y: 35))
        XCTAssertNil(drag.drag(at: CGPoint(x: 60, y: 35)))
    }

    func testReleaseBeforeAsynchronousPreparationCannotStartAStaleDrag() {
        var drag = ShelfDragGesture()
        drag.mouseDown(at: CGPoint(x: 30, y: 35))
        drag.reset()
        drag.prepare(urls: urls, ids: ["a", "b"], frame: frame)
        XCTAssertNil(drag.drag(at: CGPoint(x: 60, y: 35)))
    }

    func testDifferentRowOrNewMouseSequenceCannotReusePreviousFiles() {
        var drag = ShelfDragGesture()
        drag.mouseDown(at: CGPoint(x: 30, y: 35))
        drag.prepare(urls: urls, ids: ["a", "b"], frame: frame)
        drag.mouseDown(at: CGPoint(x: 30, y: 100))
        drag.prepare(urls: urls, ids: ["a", "b"], frame: frame)
        XCTAssertNil(drag.drag(at: CGPoint(x: 60, y: 100)))
        drag.mouseDown(at: CGPoint(x: 30, y: 35))
        drag.prepare(urls: urls, ids: ["a"], frame: frame)
        XCTAssertNil(drag.drag(at: CGPoint(x: 60, y: 35)))
    }
}
