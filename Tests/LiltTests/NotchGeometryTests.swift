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
            leftArea: CGRect(x: 0, y: 0, width: 614, height: 90),
            rightArea: CGRect(x: 1114, y: 0, width: 614, height: 90))
        XCTAssertEqual(geometry.hardwareWidth, 500)
        XCTAssertFalse(geometry.hideHardwareWings)
        XCTAssertEqual(geometry.hardwareHeight, 90)
        let open = geometry.surfaceRect(open: true)
        let folded = geometry.surfaceRect(open: false)
        XCTAssertLessThan(open.width + (open.width - folded.width) * 0.042 + 28, NotchGeometry.panelSize.width)
    }

    func testSpringOvershootFitsPanel() {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     safeTop: 38, leftArea: nil, rightArea: nil)
        let open = geometry.surfaceRect(open: true)
        let folded = geometry.surfaceRect(open: false)
        XCTAssertLessThan(open.width + (open.width - folded.width) * 0.042 + 28, NotchGeometry.panelSize.width)
        XCTAssertLessThan(open.height + (open.height - folded.height) * 0.042, NotchGeometry.panelSize.height)
    }

    func testMissingOrInvalidScreenDataUsesSafeDefaults() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 660, height: 32)
        let right = CGRect(x: 852, y: 950, width: 660, height: 32)
        for (top, lhs, rhs) in [(CGFloat.nan, left, right), (.infinity, left, right),
                                (32, left, nil), (32, nil, right),
                                (32, CGRect(x: 0, y: 0, width: 0, height: 32), right),
                                (32, right, left)] as [(CGFloat, CGRect?, CGRect?)] {
            let geometry = NotchGeometry(screenFrame: frame, safeTop: top, leftArea: lhs, rightArea: rhs)
            XCTAssertEqual(geometry.hardwareWidth, 180)
            XCTAssertTrue(geometry.hardwareHeight.isFinite)
            XCTAssertTrue(geometry.hideHardwareWings)
        }
        let small = NotchGeometry(screenFrame: frame, safeTop: 1, leftArea: left, rightArea: right)
        XCTAssertEqual(small.hardwareHeight, 24)
    }

    func testDifferentNotchDimensionsKeepBothWingsOutsideHardware() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        for (width, height) in [(160.0, 28.0), (192.0, 32.0), (260.0, 38.0), (300.0, 48.0), (400.0, 32.0), (500.0, 38.0)] {
            let left = CGRect(x: 0, y: 0, width: (frame.width - width) / 2, height: height)
            let right = CGRect(x: (frame.width + width) / 2, y: 0, width: left.width, height: height)
            let geometry = NotchGeometry(screenFrame: frame, safeTop: height, leftArea: left, rightArea: right)
            XCTAssertEqual(geometry.hardwareWidth, width)
            XCTAssertEqual(geometry.hardwareHeight, height)
            XCTAssertGreaterThanOrEqual((geometry.surfaceRect(open: false).width - width) / 2, 66)
            XCTAssertGreaterThanOrEqual((geometry.surfaceRect(open: true).width - width) / 2, 74)
            XCTAssertFalse(geometry.hideHardwareWings)
        }
    }

    func testOverwideAndOffCenterGapHideWings() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let left = CGRect(x: 0, y: 0, width: 550, height: 32)
        let right = CGRect(x: 1178, y: 0, width: 550, height: 32)
        let overwide = NotchGeometry(screenFrame: frame, safeTop: 32, leftArea: left, rightArea: right)
        XCTAssertTrue(overwide.hideHardwareWings)
        XCTAssertFalse(overwide.hideNotchContent)
        let offCenter = NotchGeometry(screenFrame: frame, safeTop: 32, leftArea: left,
                                     rightArea: CGRect(x: 750, y: 0, width: 978, height: 32))
        XCTAssertTrue(offCenter.hideHardwareWings)
        let external = NotchGeometry(screenFrame: frame, safeTop: 0, leftArea: nil, rightArea: nil)
        XCTAssertFalse(external.hideHardwareWings)
        let tooTall = NotchGeometry(screenFrame: frame, safeTop: 101, leftArea: left, rightArea: right)
        XCTAssertTrue(tooTall.hideNotchContent)
    }

    func testSmallOffsetIncludesEntirePhysicalGapInProtectedWidth() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let left = CGRect(x: 0, y: 0, width: 780, height: 32)
        let right = CGRect(x: 980, y: 0, width: 748, height: 32)
        let geometry = NotchGeometry(screenFrame: frame, safeTop: 32, leftArea: left, rightArea: right)
        XCTAssertEqual(geometry.hardwareWidth, 232)
        XCTAssertFalse(geometry.hideHardwareWings)
        XCTAssertLessThanOrEqual(frame.midX - geometry.hardwareWidth / 2, left.maxX)
        XCTAssertGreaterThanOrEqual(frame.midX + geometry.hardwareWidth / 2, right.minX)
    }
}
