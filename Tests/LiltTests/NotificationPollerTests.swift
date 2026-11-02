import XCTest
@testable import Lilt

private final class FixtureNotificationCapture: NotificationCapturing {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    var scans: Int { lock.lock(); defer { lock.unlock() }; return count }

    func scan() -> NotificationCaptureResult {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); count += 1; lock.unlock()
        _ = release.wait(timeout: .now() + 2)
        return .init(status: .active, items: [])
    }
}

final class NotificationPollerTests: XCTestCase {
    func testSerialBackgroundPollingDoesNotOverlapAndCompletesOnMain() {
        let fixture = FixtureNotificationCapture()
        let poller = NotificationPoller(capture: fixture)
        let completed = expectation(description: "one bounded background read")
        DispatchQueue.main.async {
            poller.poll { result in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(result.status, .active)
                XCTAssertEqual(fixture.scans, 1)
                completed.fulfill()
            }
            poller.poll { _ in XCTFail("An overlapping poll must be dropped") }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { fixture.release.signal() }
        wait(for: [completed], timeout: 3)
    }
}
