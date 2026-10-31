import XCTest
@testable import Lilt

final class DisplaySelectionTests: XCTestCase {
    private let laptop = DisplayCandidate(id: "laptop", name: "MacBook", hasNotch: true, isMain: false)
    private let external = DisplayCandidate(id: "external", name: "Monitor", hasNotch: false, isMain: true)

    func testAutomaticPrefersNotchThenMain() {
        XCTAssertEqual(DisplaySelection.resolve([external, laptop], preferredID: nil)?.display, laptop)
        XCTAssertEqual(DisplaySelection.resolve([external], preferredID: nil)?.display, external)
        XCTAssertNil(DisplaySelection.resolve([], preferredID: nil))
    }

    func testExplicitSelectionOverridesAutomaticAndReturnsAfterReconnect() {
        XCTAssertEqual(DisplaySelection.resolve([external, laptop], preferredID: external.id)?.display, external)
        let disconnected = DisplaySelection.resolve([laptop], preferredID: external.id)
        XCTAssertEqual(disconnected?.display, laptop)
        XCTAssertEqual(disconnected?.preferredUnavailable, true)
        let reconnected = DisplaySelection.resolve([laptop, external], preferredID: external.id)
        XCTAssertEqual(reconnected?.display, external)
        XCTAssertEqual(reconnected?.preferredUnavailable, false)
    }

    func testAmbiguousIdentityFallsBackWithoutClaimingSelection() {
        let duplicate = DisplayCandidate(id: external.id, name: "Second monitor", hasNotch: false, isMain: false)
        let result = DisplaySelection.resolve([external, duplicate, laptop], preferredID: external.id)
        XCTAssertEqual(result?.display, laptop)
        XCTAssertEqual(result?.preferredUnavailable, true)
    }

    func testNoMainUsesFirstAndEmptyPreferenceIsAutomatic() {
        let other = DisplayCandidate(id: "other", name: "Monitor", hasNotch: false, isMain: false)
        let result = DisplaySelection.resolve([other], preferredID: "")
        XCTAssertEqual(result?.display, other)
        XCTAssertEqual(result?.preferredUnavailable, false)
    }
}
