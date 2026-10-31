import XCTest
@testable import Lilt

final class BrainFMControllerTests: XCTestCase {
    typealias Controller = BrainFMController
    func testAlreadyPlayingDoesNotToggle() {
        let snapshot = Controller.Snapshot(pause: 1, previous: 1, next: 1, activity: "Deep Work")
        XCTAssertEqual(Controller.decide(.play, snapshot: snapshot), .confirmed(.playing))
        XCTAssertEqual(Controller.decide(.pause, snapshot: snapshot), .press("Pause"))
    }
    func testLightWorkResumesOnlyItsOwnPlayer() {
        let snapshot = Controller.Snapshot(play: 1, previous: 1, next: 1, activity: "Light Work", start: 1)
        XCTAssertEqual(Controller.decide(.play, activity: .lightWork, snapshot: snapshot), .press("Play"))
        XCTAssertEqual(Controller.decide(.pause, activity: .lightWork, snapshot: snapshot), .confirmed(.paused))
        XCTAssertEqual(Controller.decide(.play, activity: .deepWork, snapshot: snapshot), .press("START"))
        XCTAssertEqual(Controller.decide(.pause, activity: .deepWork, snapshot: snapshot), .failure(.activity))
    }
    func testHomeStartsChosenActivityButDoesNotProvePause() {
        let snapshot = Controller.Snapshot(deepWork: 1, lightWork: 1, start: 1)
        XCTAssertEqual(Controller.decide(.play, activity: .deepWork, snapshot: snapshot), .press("Go to Deep Work session"))
        XCTAssertEqual(Controller.decide(.play, activity: .lightWork, snapshot: snapshot), .press("Go to Light Work session"))
        XCTAssertEqual(Controller.decide(.pause, snapshot: snapshot), .failure(.unavailable))
    }
    func testOtherPlayerCanOnlyBeChangedByExplicitPlay() {
        let snapshot = Controller.Snapshot(pause: 1, previous: 1, next: 1, activity: "Sleep", start: 1)
        XCTAssertEqual(Controller.decide(.play, snapshot: snapshot), .press("START"))
        XCTAssertEqual(Controller.decide(.pause, snapshot: snapshot), .failure(.activity))
        XCTAssertEqual(Controller.decide(.pause, activity: .lightWork, snapshot: snapshot), .failure(.activity))
    }
    func testActivityPickerAndMissingControlsNeverClaimPlayback() {
        XCTAssertEqual(Controller.decide(.play, snapshot: .init()), .failure(.unavailable))
        XCTAssertEqual(Controller.decide(.pause, snapshot: .init(play: 1)), .failure(.unavailable))
        XCTAssertEqual(Controller.decide(.play, snapshot: .init(play: 1, previous: 1, next: 1, activity: "Deep Work", activityPicker: true)), .failure(.unavailable))
    }
    func testAmbiguousPlayerIsNotClicked() {
        XCTAssertEqual(Controller.decide(.play, snapshot: .init(play: 1, pause: 1, previous: 1, next: 1, activity: "Deep Work")), .failure(.ambiguous))
        XCTAssertEqual(Controller.decide(.play, snapshot: .init(deepWork: 2)), .failure(.ambiguous))
        XCTAssertEqual(Controller.decide(.play, snapshot: .init(lightWork: 2)), .failure(.ambiguous))
    }
}
