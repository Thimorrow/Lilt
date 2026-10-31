import XCTest
@testable import Lilt

final class NotchGeometryTests: XCTestCase {
    func testBuiltInCameraGapAndTopEdge() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(screenFrame: frame, safeTop: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32))
        XCTAssertEqual(geometry.hardwareWidth, 192)
        XCTAssertEqual(geometry.hardwareHeight, 32)
        XCTAssertEqual(geometry.panelFrame.maxY, frame.maxY)
        XCTAssertEqual(geometry.panelFrame.midX, frame.midX)
        XCTAssertEqual(geometry.surfaceRect(open: true).height, 192)
        XCTAssertEqual(geometry.surfaceRect(open: false).width, 324)
    }

    func testExternalDisplayWithNonzeroOrigin() {
        let frame = CGRect(x: -2560, y: 300, width: 2560, height: 1440)
        let geometry = NotchGeometry(screenFrame: frame, safeTop: 0, leftArea: nil, rightArea: nil)
        XCTAssertEqual(geometry.hardwareWidth, 180)
        XCTAssertEqual(geometry.panelFrame.midX, -1280)
        XCTAssertEqual(geometry.panelFrame.maxY, 1740)
        XCTAssertEqual(geometry.surfaceRect(open: false).height, 32)
    }

    func testUnusualGeometryStaysWithinRenderingBounds() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeTop: 90,
            leftArea: CGRect(x: 0, y: 0, width: 600, height: 90),
            rightArea: CGRect(x: 1100, y: 0, width: 628, height: 90))
        XCTAssertEqual(geometry.hardwareWidth, 300)
        XCTAssertEqual(geometry.hardwareHeight, 64)
        XCTAssertLessThan(geometry.surfaceRect(open: true).width * 1.042 + 28, NotchGeometry.panelSize.width)
    }

    func testSpringOvershootFitsPanel() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     safeTop: 38, leftArea: nil, rightArea: nil)
        let open = geometry.surfaceRect(open: true)
        let folded = geometry.surfaceRect(open: false)
        XCTAssertLessThan(open.width + (open.width - folded.width) * 0.042 + 28, NotchGeometry.panelSize.width)
        XCTAssertLessThan(open.height + (open.height - folded.height) * 0.042, NotchGeometry.panelSize.height)
    }
}
