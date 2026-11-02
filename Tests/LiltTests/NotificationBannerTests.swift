import XCTest
import ApplicationServices
@testable import Lilt

final class NotificationBannerTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1000)
    func item(_ key: String) -> CapturedNotification {
        .init(key: key, banner: .init(source: "Fixture", title: key, body: "Synthetic"))
    }

    func testBaselineDedupDropsAndNoBacklog() {
        let owner = NotificationBannerOwner()
        owner.configure(enabled: true, active: true)
        let generation = owner.generation
        owner.receive([item("existing")], generation: generation, blocked: false, now: time)
        XCTAssertNil(owner.visible)
        owner.receive([item("existing"), item("busy")], generation: generation, blocked: true, now: time)
        owner.receive([item("busy")], generation: generation, blocked: false, now: time)
        XCTAssertNil(owner.visible)
        owner.receive([item("one"), item("two")], generation: generation, blocked: false, now: time)
        XCTAssertEqual(owner.visible?.title, "one")
        owner.clear()
        owner.receive([item("two")], generation: generation, blocked: false, now: time)
        XCTAssertNil(owner.visible)
    }

    func testExpiryIdentityAndUserTakeover() {
        let owner = NotificationBannerOwner()
        let first = item("one").banner
        XCTAssertTrue(owner.present(first, blocked: false, now: time))
        owner.clear(id: UUID())
        XCTAssertEqual(owner.visible?.id, first.id)
        owner.expire(now: time.addingTimeInterval(7.9))
        XCTAssertNotNil(owner.visible)
        owner.expire(now: time.addingTimeInterval(8))
        XCTAssertNil(owner.visible)
        var clears = 0
        owner.onChange = { banner, _ in if banner == nil { clears += 1 } }
        XCTAssertTrue(owner.present(first, blocked: false, now: time))
        owner.clear()
        owner.expire(now: time.addingTimeInterval(9))
        XCTAssertEqual(clears, 1)
        let second = item("two").banner
        XCTAssertTrue(owner.present(second, blocked: false, now: time.addingTimeInterval(10)))
        owner.clear(id: first.id)
        XCTAssertEqual(owner.visible?.id, second.id)
    }

    func testDisableSuspendPermissionInvalidationAndStaleCompletions() {
        let owner = NotificationBannerOwner()
        owner.configure(enabled: true, active: true)
        let old = owner.generation
        owner.receive([], generation: old, blocked: false, now: time)
        owner.receive([item("one")], generation: old, blocked: false, now: time)
        XCTAssertNotNil(owner.visible)
        owner.configure(enabled: false, active: true)
        XCTAssertNil(owner.visible)
        owner.receive([item("stale")], generation: old, blocked: false, now: time)
        XCTAssertNil(owner.visible)
        owner.configure(enabled: true, active: false)
        XCTAssertFalse(owner.present(item("suspended").banner, blocked: false))
        owner.configure(enabled: true, active: true)
        owner.receive([item("resume baseline")], generation: owner.generation, blocked: false, now: time)
        XCTAssertNil(owner.visible)
        owner.receive([item("new")], generation: owner.generation, blocked: false, now: time)
        owner.invalidate()
        XCTAssertNil(owner.visible)
        owner.receive([item("permission baseline")], generation: owner.generation, blocked: false, now: time)
        XCTAssertNil(owner.visible)
    }

    func testContentBoundsAndBlockedPresentation() {
        let owner = NotificationBannerOwner()
        XCTAssertFalse(owner.present(item("blocked").banner, blocked: true))
        let banner = NotificationBanner(source: String(repeating: "s", count: 100), title: "<script>\u{0}" + String(repeating: "t", count: 200), body: String(repeating: "b", count: 500))
        XCTAssertEqual(banner.source.count, 80)
        XCTAssertLessThanOrEqual(banner.title.count, 160)
        XCTAssertFalse(banner.title.contains("\u{0}"))
        XCTAssertEqual(banner.body.count, 360)
    }

    func testDedupIsEphemeralAndBounded() {
        let owner = NotificationBannerOwner()
        owner.configure(enabled: true, active: true)
        let generation = owner.generation
        owner.receive([item("old")], generation: generation, blocked: false, now: time)
        owner.receive([item("old")], generation: generation, blocked: false, now: time.addingTimeInterval(121))
        XCTAssertEqual(owner.visible?.title, "old")
        owner.clear()
        for index in 0..<100 { owner.receive([item("\(index)")], generation: generation, blocked: true, now: time.addingTimeInterval(122)) }
        owner.receive([item("0")], generation: generation, blocked: false, now: time.addingTimeInterval(122))
        XCTAssertEqual(owner.visible?.title, "0")
    }
}

private final class FixtureNotificationTree: NotificationTreeReading {
    // Deliberately fictional identifiers. These are not a macOS layout profile.
    var metadataByID: [Int: NotificationNodeMetadata] = [
        0: .init(identifier: "fixture.transient", role: kAXWindowRole),
        1: .init(identifier: "fixture.banner", role: kAXGroupRole),
        2: .init(identifier: "fixture.source", role: kAXStaticTextRole),
        3: .init(identifier: "fixture.title", role: kAXStaticTextRole),
        4: .init(identifier: "fixture.body", role: kAXStaticTextRole)
    ]
    var edges = [0: [1], 1: [2, 3, 4]]
    var texts = [2: "Fixture", 3: "Synthetic title", 4: "<img src=x onerror=alert(1)>"]
    var reads = 0
    var metadataReads = 0
    func windows(limit: Int) -> [Int] { [0] }
    func metadata(_ node: Int) -> NotificationNodeMetadata? { metadataReads += 1; return metadataByID[node] }
    func children(_ node: Int, limit: Int) -> [Int] { Array((edges[node] ?? []).prefix(limit)) }
    func text(_ node: Int, limit: Int) -> String? { reads += 1; return texts[node] }
}

final class NotificationClassifierTests: XCTestCase {
    private let layout = NotificationLayout(transientWindow: "fixture.transient", banner: "fixture.banner", source: "fixture.source", title: "fixture.title", body: "fixture.body")

    func testUnverifiedOrHistoryLayoutNeverReadsText() {
        let tree = FixtureNotificationTree()
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: nil).scan(tree).isEmpty)
        XCTAssertEqual(tree.metadataReads, 0)
        tree.metadataByID[0] = .init(identifier: "fixture.history", role: kAXWindowRole)
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: layout).scan(tree).isEmpty)
        XCTAssertEqual(tree.reads, 0)
        tree.metadataByID[0] = .init(identifier: "fixture.transient", role: kAXWindowRole)
        tree.metadataByID[1] = .init(identifier: "unknown", role: kAXGroupRole)
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: layout).scan(tree).isEmpty)
        XCTAssertEqual(tree.reads, 0)
    }

    func testFixturePositiveClassificationAndPlaintextBounds() {
        let tree = FixtureNotificationTree()
        let items = NotificationClassifier(limits: .init(), layout: layout).scan(tree)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.banner.body, "<img src=x onerror=alert(1)>")
        XCTAssertEqual(tree.reads, 3)
        tree.texts[3] = String(repeating: "x", count: 513)
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: layout).scan(tree).isEmpty)
    }

    func testNodeDepthStringWindowAndElapsedBudgetsFailClosed() {
        for limits in [NotificationReadLimits(windows: 0), NotificationReadLimits(nodes: 2), NotificationReadLimits(depth: 0), NotificationReadLimits(strings: 1), NotificationReadLimits(elapsed: 0)] {
            let tree = FixtureNotificationTree()
            XCTAssertTrue(NotificationClassifier(limits: limits, layout: layout).scan(tree).isEmpty)
            XCTAssertLessThanOrEqual(tree.metadataReads, limits.nodes)
        }
        let tree = FixtureNotificationTree()
        tree.edges[1] = [1]
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: layout).scan(tree).isEmpty)
        XCTAssertLessThanOrEqual(tree.metadataReads, 64)
        var time: TimeInterval = 0
        XCTAssertTrue(NotificationClassifier(limits: .init(), layout: layout).scan(FixtureNotificationTree(), now: { time += 0.1; return time }).isEmpty)
    }
}
