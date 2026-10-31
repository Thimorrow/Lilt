import XCTest
@testable import Lilt

final class SettingsStoreTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("settings.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testNewInstallUsesIndependentFocusAndDirectMusicWithoutWriting() {
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.value.musicSource, .spotify)
        XCTAssertFalse(store.value.brainFMEnabled)
        XCTAssertEqual(store.value.focusMinutes, 25)
        XCTAssertEqual(store.value.shelfShortDays, 7)
        XCTAssertEqual(store.value.shelfLongDays, 30)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testShelfRetentionSettingsMigratePersistAndValidate() throws {
        try Data("""
        {"musicSource":"spotify","brainFMEnabled":false,"focusMinutes":25,"focusActivity":"deepWork"}
        """.utf8).write(to: file)
        let store = SettingsStore(file: file)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.value.shelfShortDays, 7)
        XCTAssertEqual(store.value.shelfLongDays, 30)
        let changed = try store.value.applying(["shelfShortDays": 14, "shelfLongDays": 90])
        XCTAssertTrue(store.save(changed))
        XCTAssertEqual(SettingsStore(file: file).value, changed)
        XCTAssertEqual(changed.payload["shelfLongDays"] as? Int, 90)
        for change: [String: Any] in [["shelfShortDays": true], ["shelfLongDays": 0],
                                     ["shelfShortDays": 3651], ["shelfLongDays": 1.5],
                                     ["shelfLongDays": Double.infinity]] {
            XCTAssertThrowsError(try changed.applying(change))
        }
    }

    func testDisplayPreferencePersistsAndOldSettingsDefaultToAutomatic() throws {
        try Data("""
        {"musicSource":"spotify","brainFMEnabled":false,"focusMinutes":25,"focusActivity":"deepWork"}
        """.utf8).write(to: file)
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.value.displayID, "")
        let id = UUID().uuidString
        let selected = try store.value.applying(["displayID": id])
        XCTAssertTrue(store.save(selected))
        XCTAssertEqual(SettingsStore(file: file).value.displayID, id)
        XCTAssertThrowsError(try selected.applying(["displayID": "not-a-uuid"]))
        XCTAssertThrowsError(try selected.applying(["displayID": true]))
        XCTAssertEqual(try selected.applying(["displayID": ""]).displayID, "")
    }

    func testMusicIntegrationAndFocusDefaultsSurviveReopening() throws {
        let store = SettingsStore(file: file)
        let value = try store.value.applying(["musicSource": "appleMusic", "brainFMEnabled": true,
                                             "focusMinutes": 45, "focusActivity": "lightWork"])
        XCTAssertTrue(store.save(value))
        let restored = SettingsStore(file: file)
        XCTAssertEqual(restored.value, value)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.value.payload["sourceName"] as? String, "Apple Music")
    }

    func testPartialChangesPreserveOtherSettingsAndRejectInvalidBridgeValues() throws {
        let value = LiltSettings(musicSource: .meld, brainFMEnabled: true, focusMinutes: 50, focusActivity: .lightWork)
        let updated = try value.applying(["musicSource": "spotify"])
        XCTAssertEqual(updated.focusMinutes, 50)
        XCTAssertTrue(updated.brainFMEnabled)
        XCTAssertEqual(updated.focusActivity, .lightWork)
        for change: [String: Any] in [["musicSource": "other"], ["brainFMEnabled": 1], ["brainFMEnabled": "false"],
                                     ["focusMinutes": true], ["focusMinutes": 0], ["focusMinutes": 181],
                                     ["focusMinutes": 2.5], ["focusMinutes": Double.infinity], ["focusActivity": "sleep"],
                                     ["unknown": false], [:]] {
            XCTAssertThrowsError(try value.applying(change))
        }
    }

    func testFailedWriteRetainsPreviousConfirmedSettings() throws {
        let blocked = directory.appendingPathComponent("blocked")
        try Data("fixture".utf8).write(to: blocked)
        let store = SettingsStore(file: blocked.appendingPathComponent("settings.json"))
        let before = store.value
        var changed = before
        changed.musicSource = .appleMusic
        XCTAssertFalse(store.save(changed))
        XCTAssertEqual(store.value, before)
        XCTAssertEqual(store.error, .storage)
    }

    func testLegacyFocusDefaultsArePreservedWithoutEnablingBrainFM() throws {
        let focusFile = directory.appendingPathComponent("focus.json")
        let session = FocusSession(activity: .lightWork, duration: 3000, remaining: 2800, phase: .paused, owned: true)
        try JSONEncoder().encode(session).write(to: focusFile)
        let original = try Data(contentsOf: focusFile)
        let store = SettingsStore(file: file, focusFile: focusFile)
        XCTAssertEqual(store.value.focusMinutes, 50)
        XCTAssertEqual(store.value.focusActivity, .lightWork)
        XCTAssertFalse(store.value.brainFMEnabled)
        XCTAssertEqual(try Data(contentsOf: focusFile), original)
    }

    func testCorruptedSettingsAreReportedAndCanBeReplacedExplicitly() throws {
        try Data("{\"musicSource\":\"invalid\"}".utf8).write(to: file)
        let store = SettingsStore(file: file)
        XCTAssertEqual(store.error?.code, "settings_read")
        XCTAssertEqual(store.value.musicSource, .spotify)
        var changed = store.value
        changed.focusMinutes = 15
        XCTAssertTrue(store.save(changed))
        XCTAssertNil(store.error)
        XCTAssertEqual(SettingsStore(file: file).value.focusMinutes, 15)
    }
}
