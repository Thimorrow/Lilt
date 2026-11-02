import XCTest
import AppKit
@testable import Lilt

final class EverydaySettingsTests: XCTestCase {
    func testShortcutAndTimerNotificationPreferenceMigrateAndSurviveRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.json")
        try Data("{\"musicSource\":\"spotify\",\"brainFMEnabled\":false,\"focusMinutes\":25,\"focusActivity\":\"deepWork\"}".utf8).write(to: file)
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.value.shortcut, KeyboardShortcut())
        XCTAssertFalse(store.value.focusNotificationsEnabled)
        let updated = try store.value.applying(["shortcut": ["keyCode": 3, "modifiers": 768], "focusNotificationsEnabled": true])
        XCTAssertTrue(store.save(updated))
        XCTAssertEqual(SettingsStore(file: file).value, updated)
        XCTAssertTrue(updated.shortcut.label.hasPrefix("⇧⌘"))
        XCTAssertFalse(updated.shortcut.keyLabel.isEmpty)
    }

    func testShortcutRejectsMalformedKeysAndUnmodifiedText() {
        let settings = LiltSettings()
        for candidate: Any in [
            ["keyCode": 0, "modifiers": 0], ["keyCode": 0, "modifiers": 512],
            ["keyCode": 53, "modifiers": 6144], ["keyCode": 999, "modifiers": 6144],
            ["keyCode": true, "modifiers": 6144], ["keyCode": 1.5, "modifiers": 6144],
            ["keyCode": 37, "modifiers": 1], ["keyCode": 37, "modifiers": -1],
            ["keyCode": 37, "modifiers": Double.infinity], ["keyCode": 37, "modifiers": 6144, "extra": 1],
            NSNull()
        ] { XCTAssertThrowsError(try settings.applying(["shortcut": candidate])) }
        for invalid: Any in [1, "true", NSNull()] {
            XCTAssertThrowsError(try settings.applying(["focusNotificationsEnabled": invalid]))
        }
    }

    func testKeyboardEventCapturesPhysicalKeyAndSupportedModifiers() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift, .capsLock], timestamp: 0,
            windowNumber: 0, context: nil, characters: "F", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        let shortcut = KeyboardShortcut(event: event)
        XCTAssertEqual(shortcut, KeyboardShortcut(keyCode: 3, modifiers: 768))
        XCTAssertEqual(shortcut.eventModifiers, [.command, .shift])
        XCTAssertTrue(shortcut.isValid)
    }

    func testNotificationPlanTracksOnlyRunningDeadlineAndReschedulingAfterExtension() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var session = FocusSession()
        XCTAssertNil(FocusNotificationPlan(session: session))
        session.confirm(.playing, at: now)
        let original = try XCTUnwrap(FocusNotificationPlan(session: session))
        XCTAssertEqual(original.deadline, now.addingTimeInterval(1500))
        session.extend(at: now.addingTimeInterval(10))
        XCTAssertEqual(FocusNotificationPlan(session: session)?.deadline, original.deadline.addingTimeInterval(300))
        session.confirm(.paused, at: now.addingTimeInterval(20))
        XCTAssertNil(FocusNotificationPlan(session: session))
        session.phase = .completed
        XCTAssertNil(FocusNotificationPlan(session: session))
        session.reset()
        XCTAssertNil(FocusNotificationPlan(session: session))
    }

    func testFocusObservationStartsAgainAfterIdleAndPauseWithoutWebViewTicks() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-timer-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let focus = FocusCoordinator(player: DisabledBrainFM(), file: file, brainFMEnabled: false)
        focus.startObserving()
        defer { focus.stop() }
        let first = expectation(description: "native timer completes after idle")
        focus.onComplete = { first.fulfill() }
        focus.request(.start)
        focus.setDiagnosticRemaining(0)
        wait(for: [first], timeout: 2)
        XCTAssertEqual(focus.session.phase, .completed)
        focus.request(.reset)
        focus.request(.start)
        focus.request(.pause)
        let second = expectation(description: "native timer completes after paused resume")
        focus.onComplete = { second.fulfill() }
        focus.request(.start)
        focus.setDiagnosticRemaining(0)
        wait(for: [second], timeout: 2)
        XCTAssertEqual(focus.session.phase, .completed)
    }
}
