import XCTest
@testable import Lilt

final class FocusSessionTests: XCTestCase {
    final class Player: BrainFMControlling {
        var commands: [(BrainFMController.Command, FocusActivity)] = []
        var commandReply: ((Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)?
        var readReply: ((Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)?
        var reads = 0
        func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            commands.append((command, activity)); commandReply = completion
        }
        func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            reads += 1; readReply = completion
        }
    }
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-focus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private var file: URL { folder.appendingPathComponent("focus.json") }

    func testChosenActivityAndDurationPersistWithoutStartingMusic() {
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file)
        focus.configure(activity: .lightWork, minutes: 50)
        let restored = FocusCoordinator(player: player, file: file)
        XCTAssertEqual(restored.session.activity, .lightWork)
        XCTAssertEqual(restored.session.duration, 3000)
        XCTAssertEqual(restored.session.phase, .idle)
        XCTAssertTrue(player.commands.isEmpty)
        focus.configure(activity: .deepWork, minutes: 0)
        XCTAssertEqual(focus.session.duration, 3000)
    }

    func testTimerRequiresConfirmationAndDuplicateAndStaleRepliesAreIgnored() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.request(.start)
        XCTAssertNil(focus.session.deadline)
        focus.request(.start)
        focus.configure(activity: .lightWork, minutes: 50)
        XCTAssertEqual(player.commands.count, 1)
        XCTAssertEqual(focus.session.activity, .deepWork)
        let reply = player.commandReply!
        reply(.success(.playing))
        XCTAssertEqual(focus.session.phase, .running)
        time = time.addingTimeInterval(60)
        XCTAssertEqual(focus.session.seconds(at: time), 1440)
        reply(.success(.paused))
        XCTAssertEqual(focus.session.phase, .running)
        focus.request(.pause)
        player.commandReply?(.success(.paused))
        XCTAssertEqual(focus.session.remaining, 1440)
        time = time.addingTimeInterval(600)
        XCTAssertEqual(focus.session.seconds(at: time), 1440)
    }

    func testExternalPauseAndResumeUseReadOnlyPolling() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.request(.start); player.commandReply?(.success(.playing))
        time = time.addingTimeInterval(30)
        focus.tick(); player.readReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 1470)
        time = time.addingTimeInterval(10)
        focus.tick(); player.readReply?(.success(.playing))
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.seconds(at: time), 1470)
        XCTAssertEqual(player.commands.count, 1)
    }

    func testForeignActivityMakesStateUncertainAndResetDiscardsOnlyLocalSession() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.request(.start); player.commandReply?(.success(.playing))
        time = time.addingTimeInterval(30)
        focus.tick(); player.readReply?(.failure(.activity))
        XCTAssertEqual(focus.session.phase, .uncertain)
        XCTAssertEqual(focus.session.remaining, 1500)
        XCTAssertNil(focus.session.deadline)
        XCTAssertEqual(player.commands.count, 1)
        focus.request(.reset)
        player.commandReply?(.failure(.activity))
        XCTAssertEqual(focus.session.phase, .idle)
        XCTAssertFalse(focus.session.owned)
        XCTAssertNil(focus.error)
        focus.configure(activity: .lightWork, minutes: 15)
        XCTAssertEqual(focus.session.activity, .lightWork)
    }

    func testNativeExpiryPausesWithoutAnyUIBeingPresent() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.configure(activity: .lightWork, minutes: 1)
        focus.request(.start); player.commandReply?(.success(.playing))
        time = time.addingTimeInterval(61)
        focus.tick()
        XCTAssertEqual(focus.pending?.action, .finish)
        XCTAssertEqual(player.commands.last?.0, .pause)
        XCTAssertEqual(player.commands.last?.1, .lightWork)
        player.commandReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .completed)
        XCTAssertEqual(focus.session.remaining, 0)
        XCTAssertFalse(focus.session.owned)
    }

    func testFailedExpiryDoesNotClaimMusicStopped() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.configure(activity: .deepWork, minutes: 1)
        focus.request(.start); player.commandReply?(.success(.playing))
        time = time.addingTimeInterval(61)
        focus.tick(); player.commandReply?(.failure(.timeout))
        XCTAssertEqual(focus.session.phase, .uncertain)
        XCTAssertEqual(focus.retry, .finish)
        XCTAssertEqual(focus.error, .timeout)
        time = time.addingTimeInterval(5)
        focus.tick(); player.readReply?(.success(.playing))
        XCTAssertEqual(focus.session.phase, .uncertain)
        XCTAssertEqual(focus.session.remaining, 0)
        XCTAssertNil(focus.session.deadline)
        XCTAssertEqual(focus.error, .timeout)
        XCTAssertEqual(focus.retry, .finish)
        XCTAssertEqual(player.commands.count, 2)
        time = time.addingTimeInterval(5)
        focus.tick(); player.readReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .completed)
        XCTAssertNil(focus.error)
    }

    func testRestoredRunningSessionWaitsForPlayerAndUsesConservativePauseTime() throws {
        let saved = FocusSession(activity: .lightWork, duration: 1500, remaining: 1500,
                                 deadline: Date(timeIntervalSince1970: 2500), phase: .running,
                                 owned: true, verifiedAt: Date(timeIntervalSince1970: 1060))
        try JSONEncoder().encode(saved).write(to: file)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, now: { Date(timeIntervalSince1970: 2000) })
        XCTAssertTrue(focus.restoring)
        XCTAssertEqual(focus.snapshot["phase"] as? String, "checking")
        XCTAssertTrue(player.commands.isEmpty)
        focus.recheck(); player.readReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 1440)
        XCTAssertTrue(player.commands.isEmpty)
    }

    func testExpiredRestorationPausesOnlyAfterMatchingPlayerRead() throws {
        let saved = FocusSession(activity: .deepWork, duration: 60, remaining: 60,
                                 deadline: Date(timeIntervalSince1970: 1060), phase: .running,
                                 owned: true, verifiedAt: Date(timeIntervalSince1970: 1000))
        try JSONEncoder().encode(saved).write(to: file)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, now: { Date(timeIntervalSince1970: 1200) })
        focus.recheck()
        XCTAssertTrue(player.commands.isEmpty)
        player.readReply?(.success(.playing))
        XCTAssertEqual(focus.pending?.action, .finish)
        player.commandReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .completed)
    }

    func testPollCannotOverwritePendingUserAction() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.request(.start); player.commandReply?(.success(.playing))
        time = time.addingTimeInterval(5)
        focus.tick()
        focus.request(.pause)
        XCTAssertEqual(player.commands.count, 1)
        player.readReply?(.success(.playing))
        XCTAssertEqual(player.commands.count, 2)
        player.commandReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .paused)
    }

    func testOldPlayerReadCannotReplaceNewActivityConfiguration() {
        let player = Player()
        var time = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: player, file: file, now: { time })
        focus.request(.start); player.commandReply?(.success(.playing))
        focus.request(.pause); player.commandReply?(.success(.paused))
        time = time.addingTimeInterval(5)
        focus.tick()
        focus.configure(activity: .lightWork, minutes: 50)
        player.readReply?(.success(.playing))
        XCTAssertEqual(focus.session.activity, .lightWork)
        XCTAssertEqual(focus.session.duration, 3000)
        XCTAssertEqual(focus.session.phase, .idle)
        XCTAssertNil(focus.session.deadline)
        XCTAssertFalse(focus.session.owned)
        XCTAssertEqual(player.commands.count, 2)
    }

    func testStorageFailureRemainsVisibleAfterSuccessfulControl() throws {
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: blocked)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: blocked.appendingPathComponent("focus.json"))
        focus.request(.start); player.commandReply?(.success(.playing))
        XCTAssertEqual(focus.error?.code, "storage")
        focus.recheck(); player.readReply?(.success(.playing))
        XCTAssertEqual(focus.error?.code, "storage")
    }
}
