import XCTest
@testable import Lilt

final class FocusExtensionTests: XCTestCase {
    private final class Player: BrainFMControlling {
        var commands: [BrainFMController.Command] = []
        var commandReply: ((Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)?
        var readReply: ((Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)?
        var reads = 0
        func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            commands.append(command)
            commandReply = completion
        }
        func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            reads += 1
            readReply = completion
        }
    }

    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("focus.json") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testCompletedStandaloneExtensionRunsForFiveMinutesAndRestores() {
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        focus.configure(activity: .deepWork, minutes: 1)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        XCTAssertEqual(focus.session.phase, .completed)
        focus.request(.extend)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.seconds(at: now), 300)
        XCTAssertEqual(focus.session.duration, 60)
        XCTAssertEqual(focus.session.totalDuration, 360)
        now.addTimeInterval(30)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        XCTAssertEqual(restored.session.seconds(at: now), 270)
        XCTAssertEqual(restored.session.totalDuration, 360)
        XCTAssertEqual(restored.session.phase, .running)
        XCTAssertTrue(player.commands.isEmpty)
        XCTAssertEqual(player.reads, 0)
    }

    func testRunningExtensionAddsExactlyFiveMinutesAndPreservesSubsecondDeadline() throws {
        var now = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: Player(), file: file, brainFMEnabled: false, now: { now })
        focus.request(.start)
        let deadline = try XCTUnwrap(focus.session.deadline)
        now.addTimeInterval(10.5)
        focus.request(.extend)
        XCTAssertEqual(focus.session.deadline, deadline.addingTimeInterval(300))
        XCTAssertEqual(focus.session.seconds(at: now), 1790)
        XCTAssertEqual(focus.session.phase, .running)
    }

    func testPausedExtensionStaysPausedAcrossRestartAndResetRestoresPreset() {
        var now = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: Player(), file: file, brainFMEnabled: false, now: { now })
        focus.request(.start)
        now.addTimeInterval(30)
        focus.request(.pause)
        focus.request(.extend)
        now.addTimeInterval(1000)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 1770)
        XCTAssertNil(focus.session.deadline)
        let restored = FocusCoordinator(player: Player(), file: file, brainFMEnabled: false, now: { now })
        XCTAssertEqual(restored.session.phase, .paused)
        XCTAssertEqual(restored.session.remaining, 1770)
        restored.request(.reset)
        XCTAssertEqual(restored.session.duration, 1500)
        XCTAssertEqual(restored.session.totalDuration, 1500)
        XCTAssertEqual(restored.session.remaining, 1500)
    }

    func testIdleAndMaximumDurationRejectExtension() {
        let focus = FocusCoordinator(player: Player(), file: file, brainFMEnabled: false)
        focus.request(.extend)
        XCTAssertEqual(focus.session.phase, .idle)
        XCTAssertEqual(focus.session.totalDuration, 1500)
        focus.configure(activity: .deepWork, minutes: 175)
        focus.request(.start)
        XCTAssertTrue(focus.canExtend)
        focus.request(.extend)
        XCTAssertEqual(focus.session.totalDuration, 10800)
        XCTAssertFalse(focus.canExtend)
        let session = focus.session
        focus.request(.extend)
        XCTAssertEqual(focus.session, session)
    }

    func testStartingAnotherStandaloneSessionClearsPreviousExtension() {
        var now = Date(timeIntervalSince1970: 1000)
        let focus = FocusCoordinator(player: Player(), file: file, brainFMEnabled: false, now: { now })
        focus.configure(activity: .deepWork, minutes: 1)
        focus.request(.start)
        focus.request(.extend)
        now.addTimeInterval(361)
        focus.tick()
        XCTAssertEqual(focus.session.phase, .completed)
        focus.request(.start)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.seconds(at: now), 60)
        XCTAssertEqual(focus.session.totalDuration, 60)
        XCTAssertNil(focus.session.extensionSeconds)
    }

    func testCompletedBrainFMExtensionWaitsForConfirmedPlayAndIgnoresDuplicateReplies() {
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true)
        focus.request(.start)
        player.commandReply?(.success(.playing))
        focus.request(.finish)
        player.commandReply?(.success(.paused))
        let completed = focus.session
        focus.request(.extend)
        XCTAssertEqual(focus.pending?.action, .extend)
        XCTAssertEqual(player.commands.last, .play)
        XCTAssertEqual(focus.session, completed)
        focus.request(.extend)
        XCTAssertEqual(player.commands.count, 3)
        let reply = player.commandReply
        reply?(.success(.playing))
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.remaining, 300)
        XCTAssertEqual(focus.session.extensionSeconds, 300)
        reply?(.success(.playing))
        XCTAssertEqual(focus.session.extensionSeconds, 300)
    }

    func testFailedBrainFMExtensionKeepsCompletedIntervalAndCanRetry() {
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true)
        focus.configureIntervals(workMinutes: 25, restMinutes: 5)
        focus.request(.start)
        player.commandReply?(.success(.playing))
        focus.request(.finish)
        player.commandReply?(.success(.paused))
        let completed = focus.session
        focus.request(.extend)
        player.commandReply?(.failure(.timeout))
        XCTAssertEqual(focus.session, completed)
        XCTAssertEqual(focus.retry, .extend)
        XCTAssertEqual(focus.error, .timeout)
        XCTAssertEqual(focus.session.intervals?.completedWorkPeriods, 1)
        focus.request(.extend)
        player.commandReply?(.success(.paused))
        XCTAssertEqual(focus.session, completed)
        XCTAssertEqual(focus.retry, .extend)
        focus.request(.extend)
        player.commandReply?(.success(.playing))
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.intervals?.phase, .work)
        XCTAssertEqual(focus.session.intervals?.state, .active)
        XCTAssertEqual(focus.session.intervals?.completedWorkPeriods, 0)
    }

    func testActiveBrainFMExtensionNeverSendsTransportAndStaleReadCannotUndoIt() {
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true, now: { now })
        focus.request(.start)
        player.commandReply?(.success(.playing))
        now.addTimeInterval(5)
        focus.tick()
        XCTAssertEqual(player.reads, 1)
        focus.request(.extend)
        let deadline = focus.session.deadline
        player.readReply?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.deadline, deadline)
        XCTAssertEqual(player.commands.count, 1)
        focus.request(.pause)
        player.commandReply?(.success(.paused))
        focus.request(.extend)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 2095)
        XCTAssertEqual(player.commands.count, 2)
    }

    func testCompletedIntervalExtensionCountsWorkOnceAndNextPhaseKeepsPreset() {
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 2)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        focus.request(.extend)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        XCTAssertEqual(restored.session.intervals?.workMinutes, 1)
        XCTAssertEqual(restored.session.intervals?.restMinutes, 2)
        XCTAssertEqual(restored.session.intervals?.state, .active)
        now.addTimeInterval(301)
        restored.tick()
        XCTAssertEqual(restored.session.intervals?.completedWorkPeriods, 1)
        XCTAssertEqual(restored.session.intervals?.phase, .work)
        XCTAssertEqual(restored.session.intervals?.state, .awaitingNext)
        restored.tick()
        XCTAssertEqual(restored.session.intervals?.completedWorkPeriods, 1)
        restored.nextInterval()
        XCTAssertEqual(restored.session.intervals?.phase, .rest)
        XCTAssertEqual(restored.session.duration, 120)
        XCTAssertEqual(restored.session.totalDuration, 120)
        XCTAssertEqual(restored.session.seconds(at: now), 120)
    }

    func testCompletedRestExtensionNeverStartsBrainFM() {
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 1)
        focus.request(.start)
        player.commandReply?(.success(.playing))
        focus.request(.finish)
        player.commandReply?(.success(.paused))
        focus.nextInterval()
        now.addTimeInterval(61)
        focus.tick()
        XCTAssertEqual(focus.session.intervals?.phase, .rest)
        XCTAssertEqual(focus.session.phase, .completed)
        focus.request(.extend)
        XCTAssertEqual(focus.session.phase, .running)
        XCTAssertEqual(focus.session.seconds(at: now), 300)
        XCTAssertEqual(focus.session.intervals?.completedWorkPeriods, 1)
        XCTAssertEqual(player.commands.count, 2)
    }

    func testExtensionRejectedWhileCommandPendingOrConfirmationUncertain() {
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true)
        focus.request(.start)
        focus.request(.extend)
        XCTAssertEqual(player.commands.count, 1)
        XCTAssertNil(focus.session.extensionSeconds)
        player.commandReply?(.success(.playing))
        focus.request(.pause)
        player.commandReply?(.failure(.timeout))
        XCTAssertEqual(focus.session.phase, .uncertain)
        XCTAssertFalse(focus.canExtend)
        focus.request(.extend)
        XCTAssertEqual(player.commands.count, 2)
        XCTAssertNil(focus.session.extensionSeconds)
    }
}
