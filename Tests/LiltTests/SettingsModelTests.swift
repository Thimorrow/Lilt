import XCTest
@testable import Lilt

/// Behavior of the native settings boundary, ported from the former settings-state and notification web tests.
final class SettingsModelTests: XCTestCase {
    private func snapshot(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["musicSource": "spotify", "sourceName": "Spotify", "brainFMEnabled": false, "notificationBannersEnabled": false,
         "notificationCaptureStatus": "disabled", "notificationCaptureMessage": "Off. No other apps are read.",
         "focusMinutes": 25, "focusActivity": "deepWork", "shelfShortDays": 7, "shelfLongDays": 30, "displayID": "",
         "displays": [Any](), "focusSound": true, "focusNotificationsEnabled": false, "focusNotificationStatus": "off",
         "shortcutEnabled": true, "openAtLogin": false, "shortcutLabel": "⌃⌥L", "shortcutConflict": false,
         "displayUnavailable": false, "musicBusy": false, "focusLocked": false, "providers": [Any](),
         "brainFM": ["installed": false, "permission": false], "error": NSNull(), "saved": true]
            .merging(extra) { $1 }
    }

    private func makeModel(_ extra: [String: Any] = [:]) -> (SettingsModel, () -> [[String: Any]]) {
        let model = SettingsModel()
        var posted: [[String: Any]] = []
        model.post = { posted.append($0) }
        model.receive("receiveSnapshot", snapshot(extra))
        return (model, { posted })
    }

    func testSnapshotsRejectInvalidNativeConfigurationAndKeepConfirmedValues() throws {
        let invalid: [[String: Any]] = [["musicSource": "global"], ["brainFMEnabled": "false"], ["brainFMEnabled": 0],
                                        ["focusMinutes": 0], ["focusMinutes": 181], ["focusMinutes": 1.5],
                                        ["focusActivity": "sleep"], ["focusLocked": NSNull()], ["brainFM": [String: Any]()],
                                        ["error": ["message": "no code"]]]
        for extra in invalid { XCTAssertNil(SettingsSnapshot(snapshot(extra)), "\(extra)") }
        var missingError = snapshot()
        missingError["error"] = nil
        XCTAssertNil(SettingsSnapshot(missingError))
        let confirmed = try XCTUnwrap(SettingsSnapshot(snapshot(["musicSource": "appleMusic", "focusMinutes": 180])))
        XCTAssertEqual(confirmed.musicSource, "appleMusic")
        XCTAssertEqual(confirmed.focusMinutes, 180)
        XCTAssertTrue(confirmed.ready)
        XCTAssertFalse(SettingsSnapshot().ready)
    }

    func testProviderStatesExposeTheMatchingRecoveryActions() {
        let provider = { (installed: Bool, running: Bool, availability: String) in
            SettingsProvider(id: "spotify", installed: installed, running: running, availability: availability, message: "")
        }
        XCTAssertEqual(ProviderState(provider(false, true, "ready")), ProviderState(status: "missing", label: "Not installed", connect: false, open: false))
        XCTAssertEqual(ProviderState(provider(true, false, "ready")), ProviderState(status: "offline", label: "Not running", connect: false, open: true))
        XCTAssertTrue(ProviderState(provider(true, true, "permission")).connect)
        XCTAssertEqual(ProviderState(provider(true, true, "empty")).status, "ready")
        XCTAssertFalse(ProviderState(provider(true, true, "disabled")).open)
        XCTAssertEqual(ProviderState(provider(true, true, "invented")).label, "Connection unavailable")
        XCTAssertFalse(ProviderState(nil).connect)
    }

    func testMalformedProvidersAndDisplaysAreDropped() throws {
        let value = try XCTUnwrap(SettingsSnapshot(snapshot([
            "providers": [["id": "spotify", "installed": true, "running": false, "availability": "offline"],
                          ["id": "unknown", "installed": true, "running": true, "availability": "ready"],
                          ["id": "appleMusic", "installed": "yes", "running": true, "availability": "ready"]],
            "displayID": "a", "displayUnavailable": true, "displays": [["id": "a", "name": "Monitor"], ["id": 12, "name": "Invalid"]]
        ])))
        XCTAssertEqual(value.providers.map(\.id), ["spotify"])
        XCTAssertEqual(value.displays, [SettingsDisplay(id: "a", name: "Monitor")])
        XCTAssertTrue(value.displayUnavailable)
        XCTAssertNil(SettingsSnapshot(snapshot(["displayID": false])))
        XCTAssertNil(SettingsSnapshot(snapshot(["displays": NSNull()])))
    }

    func testDurationAndRetentionAcceptOnlyWholeNumbersInRange() {
        for raw in ["", " ", "0", "-1", "181", "1.2", "NaN", "Infinity", "twenty"] { XCTAssertNil(SettingsValues.duration(raw), raw) }
        XCTAssertEqual(SettingsValues.duration("1"), 1)
        XCTAssertEqual(SettingsValues.duration("180"), 180)
        XCTAssertEqual(SettingsValues.duration(" 25 "), 25)
        for raw in ["", "0", "-1", "3651", "1.2", "NaN", "Infinity"] { XCTAssertNil(SettingsValues.retention(raw), raw) }
        XCTAssertEqual(SettingsValues.retention("3650"), 3650)
        XCTAssertEqual(SettingsValues.retention(" 30 "), 30)
        for invalid: Any in [0, 3651, 1.5, "7", NSNull()] {
            XCTAssertNil(SettingsSnapshot(snapshot(["shelfShortDays": invalid])))
            XCTAssertNil(SettingsSnapshot(snapshot(["shelfLongDays": invalid])))
        }
    }

    func testMenusKeepCustomAndDisconnectedValuesSelectable() throws {
        let state = try XCTUnwrap(SettingsSnapshot(snapshot(["shelfShortDays": 45, "displayID": "gone", "displays": [["id": "a", "name": "Monitor"]]])))
        XCTAssertEqual(SettingsValues.menuOptions("shelfShortDays", state).map(\.value), ["1", "3", "7", "14", "30", "45"])
        XCTAssertEqual(SettingsValues.menuOptions("shelfLongDays", state).filter { $0.value == "30" }.count, 1)
        XCTAssertEqual(SettingsValues.menuOptions("displayID", state).map(\.label), ["Automatic", "Monitor", "Disconnected display"])
        XCTAssertEqual(SettingsValues.daysLabel(1), "1 day")
        let (model, _) = makeModel()
        XCTAssertEqual(model.menuItems("shelfLongDays").last?.value, "custom")
        XCTAssertFalse(model.menuItems("displayID").contains { $0.value == "custom" })
    }

    func testSwitchesShortcutAndTimerNotificationFieldsAreStrict() throws {
        for key in ["focusSound", "shortcutEnabled", "openAtLogin", "shortcutConflict"] {
            XCTAssertNil(SettingsSnapshot(snapshot([key: "true"])))
            XCTAssertNotNil(SettingsSnapshot(snapshot([key: true])))
        }
        XCTAssertNil(SettingsSnapshot(snapshot(["shortcutLabel": NSNull()])))
        let value = snapshot(["shortcut": ["keyCode": 3, "modifiers": 768], "focusNotificationsEnabled": true,
                              "focusNotificationStatus": "allowed", "focusNotificationRequesting": false])
        XCTAssertEqual(try XCTUnwrap(SettingsSnapshot(value)).shortcut?.keyCode, 3)
        XCTAssertNil(SettingsSnapshot(value.merging(["shortcut": ["keyCode": true, "modifiers": 768]]) { $1 }))
        XCTAssertNil(SettingsSnapshot(value.merging(["shortcut": ["keyCode": 3, "modifiers": 512]]) { $1 }))
        XCTAssertNil(SettingsSnapshot(value.merging(["focusNotificationsEnabled": 1]) { $1 }))
        XCTAssertNil(SettingsSnapshot(value.merging(["focusNotificationStatus": "invented"]) { $1 }))
        XCTAssertNil(SettingsSnapshot(value.merging(["focusNotificationRequesting": 1]) { $1 }))
    }

    func testNotificationBannersDefaultOffAndOlderSnapshotsStillParse() throws {
        XCTAssertFalse(SettingsSnapshot().notificationBannersEnabled)
        var older = snapshot()
        for key in ["notificationBannersEnabled", "notificationCaptureStatus", "notificationCaptureMessage"] { older[key] = nil }
        XCTAssertFalse(try XCTUnwrap(SettingsSnapshot(older)).notificationBannersEnabled)
        XCTAssertNil(SettingsSnapshot(snapshot(["notificationBannersEnabled": 1])))
        XCTAssertNil(SettingsSnapshot(snapshot(["notificationCaptureStatus": "ready"])))
        XCTAssertNil(SettingsSnapshot(snapshot(["notificationCaptureMessage": [String: Any]()])))
    }

    func testRequestsShowOptimisticallyUntilNativeConfirmsOrRefuses() throws {
        let (model, posted) = makeModel()
        model.toggle("openAtLogin")
        XCTAssertEqual(posted().last?["action"] as? String, "settingsUpdate")
        XCTAssertTrue(model.shownBool("openAtLogin"))
        XCTAssertEqual(model.saveStatus, "pending")
        model.toggle("focusSound")
        XCTAssertEqual(posted().count, 1, "a second change waits for the first confirmation")
        model.receive("receiveSnapshot", snapshot(["error": ["code": "login_item", "message": "Failed."]]))
        XCTAssertNil(model.requested)
        XCTAssertFalse(model.shownBool("openAtLogin"), "a refused request rolls back")
        XCTAssertEqual(model.saveStatus, "error")
        model.toggle("openAtLogin")
        model.receive("receiveSnapshot", snapshot(["openAtLogin": true]))
        XCTAssertNil(model.requested)
        XCTAssertEqual(model.saveLabel, "Saved")
    }

    func testUnconfirmedRequestTimesOutWithAnError() {
        let (model, _) = makeModel()
        model.requestTimeout = 0.05
        model.toggle("focusSound")
        let expectation = expectation(description: "timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
        XCTAssertNil(model.requested)
        XCTAssertEqual(model.localError, "Lilt did not confirm the change. Try again.")
    }

    func testLocksRefusePlayerAndFocusChangesWithoutPosting() {
        let (busy, busyPosted) = makeModel(["musicBusy": true])
        busy.selectSource("appleMusic")
        XCTAssertTrue(busyPosted().isEmpty)
        let (locked, lockedPosted) = makeModel(["focusLocked": true])
        locked.choosePreset(50)
        locked.selectActivity("lightWork")
        locked.toggle("brainFMEnabled")
        XCTAssertTrue(lockedPosted().isEmpty)
        locked.toggle("openAtLogin")
        XCTAssertEqual(lockedPosted().count, 1, "unrelated settings stay available")
    }

    func testDurationEditorValidatesBeforePosting() {
        let (model, posted) = makeModel()
        model.editDuration("0")
        model.commitDuration()
        XCTAssertEqual(model.durationError, "Choose a whole number from 1 to 180.")
        XCTAssertTrue(posted().isEmpty)
        model.editDuration("0")
        XCTAssertNotNil(model.durationError, "an unchanged text echo keeps the error")
        model.editDuration("25")
        model.commitDuration()
        XCTAssertNil(model.durationDraft, "the confirmed value needs no request")
        model.editDuration("50")
        model.commitDuration()
        XCTAssertEqual((posted().last?["changes"] as? [String: Any])?["focusMinutes"] as? Int, 50)
        model.receive("receiveSnapshot", snapshot(["focusMinutes": 50]))
        XCTAssertNil(model.durationDraft)
    }

    func testRetentionCustomEntryAndMenuKeyboard() {
        let (model, posted) = makeModel()
        model.toggleMenu("shelfLongDays")
        XCTAssertEqual(model.menuItems("shelfLongDays")[model.menuHighlight ?? -1].value, "30")
        XCTAssertTrue(model.menuKey("end"))
        XCTAssertTrue(model.menuKey("return"))
        XCTAssertTrue(model.retentionCustom.contains("shelfLongDays"))
        model.editRetention("shelfLongDays", "3651")
        model.commitRetention("shelfLongDays")
        XCTAssertNotNil(model.retentionErrors["shelfLongDays"])
        XCTAssertTrue(posted().isEmpty)
        model.editRetention("shelfLongDays", "45")
        model.commitRetention("shelfLongDays")
        model.receive("receiveSnapshot", snapshot(["shelfLongDays": 45]))
        XCTAssertFalse(model.retentionCustom.contains("shelfLongDays"))
        XCTAssertEqual(model.menuLabel("shelfLongDays"), "45 days")
    }

    func testEscapeClosesTheInnermostStateBeforeTheWindow() {
        let (model, posted) = makeModel()
        model.toggleMenu("displayID")
        model.escape()
        XCTAssertNil(model.openMenu)
        XCTAssertTrue(posted().isEmpty)
        model.escape()
        XCTAssertEqual(posted().last?["action"] as? String, "settingsClose")
    }

    func testTimerNotificationOptInAsksNativeAndShortcutRecordingIsNativeDriven() {
        let (model, posted) = makeModel()
        model.toggleFocusNotifications()
        XCTAssertEqual(posted().last?["action"] as? String, "focusNotificationPermission")
        model.toggleShortcutRecording()
        XCTAssertEqual(posted().last?["action"] as? String, "shortcutRecord")
        model.receive("receiveShortcutRecording", ["recording": true, "error": "Choose a key."])
        XCTAssertTrue(model.recordingShortcut)
        model.setSection(.music)
        XCTAssertEqual(posted().last?["action"] as? String, "shortcutCancelRecording", "leaving the section cancels recording")
        model.receive("configure", ["reducedMotion": true])
        XCTAssertTrue(model.reducedMotion)
    }
}
