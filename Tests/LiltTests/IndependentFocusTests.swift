import XCTest
@testable import Lilt

final class IndependentFocusTests: XCTestCase {
    private final class Player: BrainFMControlling {
        var commands = 0
        var reads = 0
        func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            commands += 1
            completion(.failure(.timeout))
        }
        func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            reads += 1
            completion(.failure(.timeout))
        }
    }

    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("focus.json") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-independent-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testStandaloneStartPauseResumeResetNeverTouchesPlayer() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        focus.configure(activity: .lightWork, minutes: 50)
        focus.request(.start)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertNil(focus.pending)
        time = time.addingTimeInterval(75)
        focus.tick()
        focus.recheck()
        focus.request(.pause)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 2925)
        time = time.addingTimeInterval(300)
        focus.request(.start)
        XCTAssertEqual(focus.session.seconds(at: time), 2925)
        time = time.addingTimeInterval(25)
        focus.tick()
        XCTAssertEqual(focus.session.seconds(at: time), 2900)
        focus.request(.reset)
        XCTAssertEqual(focus.session.phase, .idle)
        XCTAssertEqual(focus.session.duration, 3000)
        XCTAssertEqual(focus.session.remaining, 3000)
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testIndependentDeadlineCompletesWithoutWebViewOrPlayer() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        focus.configure(activity: .deepWork, minutes: 1)
        focus.request(.start)
        time = time.addingTimeInterval(61)
        focus.tick()
        XCTAssertEqual(focus.session.phase, .completed)
        XCTAssertEqual(focus.session.remaining, 0)
        XCTAssertNil(focus.session.deadline)
        XCTAssertFalse(focus.session.owned)
        XCTAssertFalse(focus.integrationLocked)
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testRunningIndependentTimerRestoresWallClockDeadline() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        focus.configure(activity: .lightWork, minutes: 25)
        focus.request(.start)
        time = time.addingTimeInterval(60)
        focus.checkpoint()
        time = time.addingTimeInterval(60)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        XCTAssertFalse(restored.restoring)
        XCTAssertEqual(restored.session.phase, .running)
        XCTAssertEqual(restored.session.seconds(at: time), 1380)
        XCTAssertEqual(restored.session.activity, .lightWork)
        restored.startObserving()
        restored.recheck()
        restored.stop()
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testExpiredIndependentSessionRestoresAsCompleted() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        focus.configure(activity: .deepWork, minutes: 1)
        focus.request(.start)
        focus.stop()
        time = time.addingTimeInterval(120)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        XCTAssertEqual(restored.session.phase, .completed)
        XCTAssertNil(restored.session.deadline)
        XCTAssertFalse(restored.restoring)
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testPausedIndependentSessionRestoresWithoutConsumingTime() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        focus.request(.start)
        time = time.addingTimeInterval(60)
        focus.request(.pause)
        time = time.addingTimeInterval(600)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { time })
        XCTAssertEqual(restored.session.phase, .paused)
        XCTAssertEqual(restored.session.remaining, 1440)
        XCTAssertNil(restored.session.deadline)
        XCTAssertTrue(restored.integrationLocked)
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testIntegrationChangesOnlyWhileIdleOrCompleted() {
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false)
        XCTAssertTrue(focus.setBrainFMEnabled(true))
        XCTAssertTrue(focus.brainFMEnabled)
        XCTAssertTrue(focus.setBrainFMEnabled(false))
        focus.request(.start)
        XCTAssertFalse(focus.setBrainFMEnabled(true))
        XCTAssertTrue(focus.setBrainFMEnabled(false))
        focus.request(.pause)
        XCTAssertFalse(focus.setBrainFMEnabled(true))
        focus.request(.finish)
        XCTAssertTrue(focus.setBrainFMEnabled(true))
        XCTAssertEqual(focus.snapshot["brainFMEnabled"] as? Bool, true)
        XCTAssertEqual(focus.snapshot["integrationLocked"] as? Bool, false)
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testLegacyBrainFMSessionDoesNotReadDisabledIntegration() throws {
        let saved = FocusSession(activity: .lightWork, duration: 1500, remaining: 1500,
                                 deadline: Date(timeIntervalSince1970: 2500), phase: .running,
                                 owned: true, verifiedAt: Date(timeIntervalSince1970: 1060))
        let data = try JSONEncoder().encode(saved)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(raw["brainFMEnabled"])
        try data.write(to: file)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { Date(timeIntervalSince1970: 2000) })
        focus.startObserving()
        focus.recheck()
        XCTAssertFalse(focus.brainFMEnabled)
        XCTAssertFalse(focus.restoring)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 1440)
        XCTAssertEqual(focus.error?.code, "integration_changed")
        XCTAssertFalse(focus.session.owned)
        focus.request(.start)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertNil(focus.error)
        focus.stop()
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testEnablingBrainFMOnRestoreDoesNotStartOrAdoptMusic() throws {
        let saved = FocusSession(activity: .deepWork, duration: 1500, remaining: 1500,
                                 deadline: Date(timeIntervalSince1970: 2500), phase: .running,
                                 owned: true, verifiedAt: Date(timeIntervalSince1970: 1000), brainFMEnabled: false)
        try JSONEncoder().encode(saved).write(to: file)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true, now: { Date(timeIntervalSince1970: 1100) })
        focus.startObserving()
        focus.recheck()
        XCTAssertTrue(focus.brainFMEnabled)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 1400)
        XCTAssertFalse(focus.session.owned)
        XCTAssertEqual(focus.error?.code, "integration_changed")
        focus.stop()
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }

    func testIndependentStorageFailureIsVisibleWithoutPlayer() throws {
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: blocked)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: blocked.appendingPathComponent("focus.json"), brainFMEnabled: false)
        focus.request(.start)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.error?.code, "storage")
        XCTAssertEqual(player.commands, 0)
        XCTAssertEqual(player.reads, 0)
    }
}
