import XCTest
@testable import Lilt

final class FocusIntervalsTests: XCTestCase {
    private final class Player: BrainFMControlling {
        var commands: [BrainFMController.Command] = []
        func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            commands.append(command)
            completion(.success(command == .play ? .playing : .paused))
        }
        func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) { completion(.success(.playing)) }
    }
    private final class DeferredPlayer: BrainFMControlling {
        var read: ((Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)?
        func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
            completion(.success(command == .play ? .playing : .paused))
        }
        func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) { read = completion }
    }
    func testRequiresValidDurations() {
        XCTAssertNil(FocusIntervals(workMinutes: 0, restMinutes: 5))
        XCTAssertNil(FocusIntervals(workMinutes: 25, restMinutes: 181))
        XCTAssertNotNil(FocusIntervals(workMinutes: 25, restMinutes: 5))
    }

    func testCompletionWaitsForExplicitNextPhaseAndStart() {
        var plan = FocusIntervals(workMinutes: 25, restMinutes: 5)!
        plan.started()
        plan.completed()
        plan.completed()
        XCTAssertEqual(plan.state, .awaitingNext)
        XCTAssertEqual(plan.phase, .work)
        XCTAssertEqual(plan.completedWorkPeriods, 1)
        plan.prepareNext()
        XCTAssertEqual(plan.phase, .rest)
        XCTAssertEqual(plan.currentMinutes, 5)
        XCTAssertEqual(plan.state, .ready)
        plan.started()
        plan.completed()
        plan.prepareNext()
        XCTAssertEqual(plan.phase, .work)
        XCTAssertEqual(plan.currentMinutes, 25)
        XCTAssertEqual(plan.completedWorkPeriods, 1)
    }

    func testRestorationDoesNotStartOrAdvance() throws {
        var plan = FocusIntervals(workMinutes: 50, restMinutes: 10)!
        plan.started()
        plan.completed()
        let data = try JSONEncoder().encode(plan)
        let restored = try JSONDecoder().decode(FocusIntervals.self, from: data)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored.state, .awaitingNext)
    }

    func testStoppedPlanCannotRestartOrAdvance() {
        var plan = FocusIntervals(workMinutes: 25, restMinutes: 5)!
        plan.started()
        plan.stop()
        plan.completed()
        plan.prepareNext()
        plan.started()
        XCTAssertEqual(plan.state, .stopped)
        XCTAssertEqual(plan.phase, .work)
    }

    func testIndependentSequencePersistsAndWaitsAfterExpiry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("focus.json")
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 2)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        XCTAssertEqual(focus.session.intervals?.state, .awaitingNext)
        focus.request(.start)
        XCTAssertEqual(focus.session.phase, .completed)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        XCTAssertEqual(restored.session.intervals?.state, .awaitingNext)
        restored.nextInterval()
        XCTAssertEqual(restored.session.intervals?.phase, .rest)
        XCTAssertEqual(restored.session.phase, .running)
        XCTAssertEqual(restored.session.duration, 120)
        restored.request(.pause)
        XCTAssertEqual(restored.session.phase, .paused)
        restored.request(.start)
        now.addTimeInterval(121)
        restored.tick()
        XCTAssertEqual(restored.session.intervals?.state, .awaitingNext)
        XCTAssertTrue(player.commands.isEmpty)
    }

    func testBrainFMIsPausedAtWorkEndAndNotStartedInBreak() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: dir.appendingPathComponent("focus.json"), brainFMEnabled: true, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 1)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        XCTAssertEqual(player.commands.count, 2)
        XCTAssertEqual(focus.session.intervals?.state, .awaitingNext)
        focus.nextInterval()
        XCTAssertEqual(focus.session.intervals?.phase, .rest)
        focus.request(.pause)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        XCTAssertEqual(player.commands.count, 2)
        XCTAssertEqual(focus.session.intervals?.state, .awaitingNext)
    }

    func testExpiredBreakRestoresWithoutStartingBrainFM() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("focus.json")
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: true, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 1)
        focus.request(.start)
        now.addTimeInterval(61)
        focus.tick()
        focus.nextInterval()
        now.addTimeInterval(61)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: true, now: { now })
        XCTAssertEqual(restored.session.phase, .completed)
        XCTAssertEqual(restored.session.intervals?.phase, .rest)
        XCTAssertEqual(restored.session.intervals?.state, .awaitingNext)
        XCTAssertEqual(player.commands.count, 2)
    }

    func testActivityChangePreservesConfiguredPausedAndCompletedIntervals() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("focus.json")
        var now = Date(timeIntervalSince1970: 1000)
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false, now: { now })
        focus.configureIntervals(workMinutes: 50, restMinutes: 5)
        focus.configure(activity: .lightWork, minutes: 50)
        XCTAssertEqual(focus.session.intervals?.state, .ready)
        XCTAssertEqual(focus.session.activity, .lightWork)
        focus.request(.start)
        now.addTimeInterval(60)
        focus.request(.pause)
        focus.configure(activity: .deepWork, minutes: 50)
        XCTAssertEqual(focus.session.intervals?.state, .active)
        XCTAssertEqual(focus.session.phase, .paused)
        XCTAssertEqual(focus.session.remaining, 2940)
        focus.request(.start)
        now.addTimeInterval(2941)
        focus.tick()
        focus.configure(activity: .lightWork, minutes: 50)
        XCTAssertEqual(focus.session.intervals?.state, .awaitingNext)
        XCTAssertEqual(focus.session.phase, .completed)
        XCTAssertEqual(focus.session.activity, .lightWork)
        focus.nextInterval()
        XCTAssertEqual(focus.session.intervals?.phase, .rest)
    }

    func testExternalPauseReplyAfterDeadlineAwaitsNextPhase() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var now = Date(timeIntervalSince1970: 1000)
        let player = DeferredPlayer()
        let focus = FocusCoordinator(player: player, file: dir.appendingPathComponent("focus.json"), brainFMEnabled: true, now: { now })
        focus.configureIntervals(workMinutes: 1, restMinutes: 1)
        focus.request(.start)
        now.addTimeInterval(5)
        focus.tick()
        XCTAssertNotNil(player.read)
        now.addTimeInterval(56)
        player.read?(.success(.paused))
        XCTAssertEqual(focus.session.phase, .completed)
        XCTAssertEqual(focus.session.intervals?.state, .awaitingNext)
        focus.nextInterval()
        XCTAssertEqual(focus.session.intervals?.phase, .rest)
        XCTAssertEqual(focus.session.phase, .running)
    }

    func testIdleConfiguredIntervalIsNotReplacedByDefaultsAfterReload() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("focus.json")
        let player = Player()
        let focus = FocusCoordinator(player: player, file: file, brainFMEnabled: false)
        XCTAssertTrue(focus.canApplyDefaults)
        focus.configureIntervals(workMinutes: 50, restMinutes: 5)
        let restored = FocusCoordinator(player: player, file: file, brainFMEnabled: false)
        XCTAssertEqual(restored.session.phase, .idle)
        XCTAssertFalse(restored.canApplyDefaults)
        XCTAssertEqual(restored.session.intervals?.workMinutes, 50)
        XCTAssertEqual(restored.session.intervals?.restMinutes, 5)
    }
}
