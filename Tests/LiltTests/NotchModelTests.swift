import XCTest
@testable import Lilt

/// Behavior of the native notch boundary, ported from the former web model tests.
final class NotchModelTests: XCTestCase {
    private func ready(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["availability": "ready", "id": "track", "title": "A song", "artist": "", "album": "", "queueID": "",
         "duration": 120, "elapsed": 15, "playing": false, "buffering": false, "speed": 1,
         "canPlay": true, "canPause": true, "canNext": false, "canPrevious": false, "pending": NSNull(), "error": NSNull()]
            .merging(extra) { $1 }
    }

    func testPlaybackAdvancesOnlyWhileConfirmedPlayingAndClampsToDuration() throws {
        let playing = try XCTUnwrap(MusicState(ready(["playing": true]), now: 1))
        XCTAssertEqual(playing.elapsed(at: 3), 17)
        XCTAssertEqual(playing.elapsed(at: 1000), 120)
        let paused = try XCTUnwrap(MusicState(ready(), now: 1))
        XCTAssertEqual(paused.elapsed(at: 90), 15)
    }

    func testUnknownDurationKeepsCountingAndClockHandlesInvalidValues() throws {
        let music = try XCTUnwrap(MusicState(ready(["duration": 0, "elapsed": 75, "playing": true]), now: 0))
        XCTAssertEqual(music.elapsed(at: 30), 105)
        XCTAssertEqual(liltClock(-5), "0:00")
        XCTAssertEqual(liltClock(.nan), "0:00")
        XCTAssertEqual(liltClock(245), "4:05")
    }

    func testMalformedSnapshotsAndRemoteArtworkAreRejected() {
        XCTAssertNil(MusicState(ready(["elapsed": Double.nan]), now: 0))
        XCTAssertNil(MusicState(ready(["playing": "yes"]), now: 0))
        XCTAssertNil(MusicState(ready(["pending": "delete"]), now: 0))
        XCTAssertNil(MusicState(ready(["error": ["message": "missing code"]]), now: 0))
        XCTAssertNil(MusicState(ready(["availability": "playing"]), now: 0))
        XCTAssertNil(MusicState(ready(["cover": "https://example.com/cover.png"]), now: 0)?.cover)
        XCTAssertEqual(MusicState(ready(["cover": "data:image/jpeg;base64,aGVsbG8="]), now: 0)?.cover, "data:image/jpeg;base64,aGVsbG8=")
    }

    func testOfflineDisablesTransportAndBufferingNeverAdvances() throws {
        let offline = try XCTUnwrap(MusicState(ready(["availability": "offline", "playing": true]), now: 0))
        XCTAssertFalse(offline.playing)
        XCTAssertFalse(offline.canPlay || offline.canPause)
        XCTAssertEqual(offline.elapsed(at: 90), 15)
        let buffering = try XCTUnwrap(MusicState(ready(["buffering": true, "playing": true]), now: 0))
        XCTAssertFalse(buffering.playing)
        XCTAssertEqual(buffering.elapsed(at: 90), 15)
    }

    func testRepeatedPollWithSameContentIsNotAChange() throws {
        let first = try XCTUnwrap(MusicState(ready(), now: 1))
        let second = try XCTUnwrap(MusicState(ready(), now: 5))
        XCTAssertTrue(first.sameContent(as: second))
        XCTAssertFalse(first.sameContent(as: try XCTUnwrap(MusicState(ready(["title": "Other"]), now: 5))))
    }

    func testShelfSelectionSupportsSingleCommandAndShiftRanges() {
        let ids = ["a", "b", "c", "d"]
        var selection = ShelfSelection()
        selection.select("b", in: ids)
        XCTAssertEqual(selection.selected, ["b"])
        selection.select("d", in: ids, toggle: true)
        XCTAssertEqual(selection.selected, ["b", "d"])
        selection.select("b", in: ids, range: true)
        XCTAssertEqual(selection.selected, ["b", "c", "d"])
        selection.select("c", in: ids, toggle: true)
        XCTAssertEqual(selection.selected, ["b", "d"])
        selection.select("missing", in: ids)
        XCTAssertEqual(selection.selected, ["b", "d"])
        selection.retain(["b"])
        XCTAssertEqual(selection.selected, ["b"])
    }

    private func idle(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["activity": "deepWork", "duration": 1500, "remaining": 1500, "deadline": NSNull(), "phase": "idle",
         "owned": false, "restoring": false, "pending": NSNull(), "error": NSNull()].merging(extra) { $1 }
    }

    func testFocusWaitsForNativeStateAndRejectsMalformedValues() {
        XCTAssertTrue(FocusState().locked)
        XCTAssertNil(FocusState(idle(["activity": "sleep"])))
        XCTAssertNil(FocusState(idle(["duration": 0])))
        XCTAssertNil(FocusState(idle(["remaining": Double.nan])))
        XCTAssertNil(FocusState(idle(["phase": "optimistic-playing"])))
        XCTAssertEqual(FocusState(idle(["activity": "lightWork", "duration": 3000]))?.ready, true)
    }

    func testRunningPendingUncertainAndRestoringLockConfiguration() throws {
        XCTAssertFalse(try XCTUnwrap(FocusState(idle())).locked)
        for extra: [String: Any] in [["phase": "running"], ["phase": "uncertain"], ["pending": ["id": "1", "action": "start"]], ["restoring": true]] {
            XCTAssertTrue(try XCTUnwrap(FocusState(idle(extra))).locked, "\(extra)")
        }
    }

    func testFocusActionsFollowNativeStateIncludingRetries() throws {
        XCTAssertEqual(try XCTUnwrap(FocusState(idle())).primaryAction, "start")
        XCTAssertEqual(try XCTUnwrap(FocusState(idle(["phase": "running"]))).primaryAction, "pause")
        let failed = try XCTUnwrap(FocusState(idle(["error": ["code": "x", "message": "Failed", "action": "finish"]])))
        XCTAssertEqual(failed.primaryAction, "finish")
        XCTAssertEqual(try XCTUnwrap(FocusState(idle(["remaining": 1234]))).remaining, 1234)
    }

    func testExtensionFieldsAreValidated() {
        let extended = idle(["phase": "running", "duration": 60, "totalDuration": 360, "remaining": 300, "canExtend": true])
        XCTAssertEqual(FocusState(extended)?.remaining, 300)
        XCTAssertNil(FocusState(extended.merging(["canExtend": "yes"]) { $1 }))
        XCTAssertNil(FocusState(extended.merging(["totalDuration": 10801]) { $1 }))
    }

    func testNotificationBoundaryBoundsPlaintextAndRejectsMalformedValues() throws {
        let fixture: [String: Any] = ["id": "12345678-1234-1234-1234-123456789012", "source": "Synthetic", "title": "<img onerror=alert(1)>", "body": "Plaintext"]
        XCTAssertEqual(NotificationBannerContent(fixture)?.title, "<img onerror=alert(1)>")
        XCTAssertEqual(NotificationBannerContent(fixture.merging(["body": String(repeating: "b", count: 1000)]) { $1 })?.body.count, 360)
        XCTAssertEqual(NotificationBannerContent(fixture.merging(["source": String(repeating: "s", count: 1000)]) { $1 })?.source.count, 80)
        XCTAssertEqual(NotificationBannerContent(fixture.merging(["title": "x\u{0}y"]) { $1 })?.title, "xy")
        for value: Any? in [nil, [String: Any](), fixture.merging(["title": 1]) { $1 }, fixture.merging(["id": "bad"]) { $1 }] {
            XCTAssertNil(NotificationBannerContent(value))
        }
    }

    func testModelPostsValidatedIntentsAndRefusesUnavailableCommands() throws {
        let model = NotchModel()
        var posted: [[String: Any]] = []
        model.post = { posted.append($0) }
        model.receive("receiveMusicSnapshot", ready(["canNext": false]))
        model.musicCommand("next")
        XCTAssertTrue(posted.isEmpty, "next is not allowed by the snapshot")
        model.togglePlayback()
        XCTAssertEqual(posted.last?["command"] as? String, "play")
        model.receive("receiveFocusSnapshot", idle(["phase": "running"]))
        model.configureFocus(minutes: 50)
        XCTAssertNotEqual(posted.last?["action"] as? String, "focusConfigure", "running sessions cannot be reconfigured")
    }

    func testOutsideClickClosesMenuBeforeFoldingAndEscapeUnwindsInOrder() throws {
        let model = NotchModel()
        model.receive("receiveFocusSnapshot", idle())
        model.setOpen(true)
        model.toggleFocusMenu(.duration)
        XCTAssertTrue(model.dismissMenus())
        XCTAssertTrue(model.open)
        XCTAssertFalse(model.dismissMenus())
        model.toggleFocusMenu(.activity)
        model.escape()
        XCTAssertNil(model.focusMenu)
        XCTAssertTrue(model.open)
        model.escape()
        XCTAssertFalse(model.open)
    }

    func testBannerOnlyAppearsWhileClosedAndTakeoverConfirmsOwnership() throws {
        let model = NotchModel()
        var posted: [[String: Any]] = []
        model.post = { posted.append($0) }
        let banner: [String: Any] = ["id": "12345678-1234-1234-1234-123456789012", "source": "S", "title": "T", "body": "B"]
        model.setOpen(true)
        model.receive("receiveNotificationBanner", banner)
        XCTAssertNil(model.banner, "an open panel is never covered by a banner")
        model.setOpen(false)
        model.receive("receiveNotificationBanner", banner)
        XCTAssertNotNil(model.banner)
        XCTAssertTrue(model.open)
        model.setPage(.shelf)
        XCTAssertNil(model.banner)
        XCTAssertTrue(posted.contains { $0["action"] as? String == "notificationTakeover" })
        XCTAssertTrue(posted.contains { $0["action"] as? String == "openChanged" && $0["userOwned"] as? Bool == true })
    }

    func testSwipeCommitsAfterFortyPointsAndRubberBandsAtTheEdges() throws {
        let model = NotchModel()
        var haptics = 0
        model.post = { if $0["action"] as? String == "swipeHaptic" { haptics += 1 } }
        model.receive("configure", ["reducedMotion": false])
        model.setOpen(true)
        let point = CGPoint(x: 340, y: 100)
        model.swipeGesture(phase: "begin", dx: -2, dy: 0, accepted: 0, point: point, time: 1)
        for step in 1...5 { model.swipeGesture(phase: "change", dx: -10, dy: 0, accepted: 0, point: point, time: 1 + Double(step) * 0.016) }
        XCTAssertEqual(try XCTUnwrap(model.swipePosition), 52, accuracy: 0.01, "the strip follows the finger 1:1 between pages")
        XCTAssertEqual(haptics, 1, "one tick when the commit threshold toward an existing page is crossed")
        model.swipeGesture(phase: "end", dx: 0, dy: 0, accepted: 1, point: point, time: 1.1)
        XCTAssertEqual(model.page, .focus)

        model.clearSwipe()
        model.setPage(.music)
        model.swipeGesture(phase: "begin", dx: 2, dy: 0, accepted: 0, point: point, time: 2)
        for step in 1...20 { model.swipeGesture(phase: "change", dx: 20, dy: 0, accepted: 0, point: point, time: 2 + Double(step) * 0.016) }
        let position = try XCTUnwrap(model.swipePosition)
        XCTAssertLessThan(position, 0)
        XCTAssertGreaterThan(position, -model.pageWidth * 0.35, "the rubber band never exceeds 35 % of a page")
        model.swipeGesture(phase: "end", dx: 0, dy: 0, accepted: -1, point: point, time: 2.4)
        XCTAssertEqual(model.page, .music, "there is no page before the first one")
    }

    func testVerticalGesturesAndReducedMotionNeverMoveTheStrip() {
        let model = NotchModel()
        model.setOpen(true)
        let point = CGPoint(x: 340, y: 100)
        model.swipeGesture(phase: "begin", dx: 0, dy: 12, accepted: 0, point: point, time: 1)
        model.swipeGesture(phase: "change", dx: -30, dy: 2, accepted: 0, point: point, time: 1.02)
        XCTAssertNil(model.swipePosition, "a gesture that locked vertically stays vertical")
        model.receive("configure", ["reducedMotion": true])
        model.swipeGesture(phase: "begin", dx: -20, dy: 0, accepted: 0, point: point, time: 2)
        model.swipeGesture(phase: "change", dx: -30, dy: 0, accepted: 0, point: point, time: 2.02)
        XCTAssertNil(model.swipePosition)
        model.swipeGesture(phase: "end", dx: 0, dy: 0, accepted: 1, point: point, time: 2.05)
        XCTAssertEqual(model.page, .focus, "reduced motion still switches, without tracking")
    }

    func testSettleComesToRestAtTheTargetWithoutOvershoot() {
        var tracker = SwipeTracker(width: 464, position: 120)
        tracker.velocity = 900
        tracker.beginSettle(to: 0)
        var now = 0.0, minimum = CGFloat.infinity, done = false
        for _ in 0..<240 where !done {
            now += 1.0 / 120
            done = tracker.step(now: now)
            minimum = min(minimum, tracker.position)
        }
        XCTAssertTrue(done)
        XCTAssertEqual(tracker.position, 0, accuracy: 0.5)
        XCTAssertGreaterThan(minimum, -0.5, "critically damped: no bounce past the target")
    }

    func testSpringCurveMatchesTheStudyKeyframes() {
        XCTAssertEqual(LiltCurve.spring(0), 0)
        XCTAssertEqual(LiltCurve.spring(0.145), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiltCurve.spring(0.46), 1.042, accuracy: 1e-9)
        XCTAssertEqual(LiltCurve.spring(0.25), 0.76 + (0.93 - 0.76) * (0.035 / 0.075), accuracy: 1e-9)
        XCTAssertEqual(LiltCurve.spring(1), 1)
        XCTAssertEqual(LiltCurve.spring(2), 1)
    }

    func testSVGParserHandlesCompactArcAndRelativeSyntax() {
        let file = SVGPath.parse("M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8Z").boundingRect
        XCTAssertEqual(file.minX, 5, accuracy: 0.01)
        XCTAssertEqual(file.maxX, 19, accuracy: 0.01)
        XCTAssertEqual(file.minY, 3, accuracy: 0.01)
        XCTAssertEqual(file.maxY, 21, accuracy: 0.01)
        let play = SVGPath.parse("M8 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5Z").boundingRect
        XCTAssertEqual(play.minX, 8, accuracy: 0.01)
        XCTAssertGreaterThan(play.maxX, 20)
        XCTAssertLessThan(play.maxX, 21)
    }
}
