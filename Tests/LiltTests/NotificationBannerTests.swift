import XCTest
import ApplicationServices
@testable import Lilt

final class NotificationBannerTests: XCTestCase {
    let time = Date(timeIntervalSince1970: 1000)
    func item(_ key: String) -> CapturedNotification {
        .init(key: key, banner: .init(source: "Fixture", title: key, body: "Synthetic"))
    }

    func testBaselineDedupAndQueuedPresentation() {
        let owner = NotificationBannerOwner()
        owner.configure(enabled: true, active: true)
        let generation = owner.generation
        owner.receive([item("existing")], generation: generation, now: time)
        owner.advance(blocked: false, now: time)
        XCTAssertNil(owner.visible)
        owner.receive([item("existing"), item("one"), item("two")], generation: generation, now: time)
        owner.advance(blocked: true, now: time)
        XCTAssertNil(owner.visible)
        owner.advance(blocked: false, now: time)
        XCTAssertEqual(owner.visible?.title, "one")
        owner.advance(blocked: false, now: time.addingTimeInterval(8))
        XCTAssertEqual(owner.visible?.title, "two")
        owner.clear()
        owner.receive([item("two")], generation: generation, now: time)
        owner.advance(blocked: false, now: time)
        XCTAssertNil(owner.visible)
    }

    func testQueueIsBoundedDropsStaleAndClearsOnInvalidate() {
        let owner = NotificationBannerOwner()
        for index in 0..<8 { owner.enqueue(item("\(index)").banner, now: time) }
        owner.advance(blocked: false, now: time)
        XCTAssertEqual(owner.visible?.title, "3")
        owner.clear()
        owner.advance(blocked: false, now: time.addingTimeInterval(121))
        XCTAssertNil(owner.visible)
        XCTAssertFalse(owner.hasPending)
        owner.enqueue(item("later").banner, now: time)
        owner.invalidate()
        XCTAssertFalse(owner.hasPending)
        owner.configure(enabled: false, active: false)
        owner.enqueue(item("suspended").banner, now: time)
        XCTAssertFalse(owner.hasPending)
    }

    func testImagePayloadKeepsTypeAndDropsOversizedData() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x00])
        XCTAssertEqual((NotificationBanner(source: "s", title: "t", body: "", image: jpeg).payload["image"] as? String)?.hasPrefix("data:image/jpeg;base64,"), true)
        XCTAssertEqual((NotificationBanner(source: "s", title: "t", body: "", image: Data([0x89, 0x50])).payload["image"] as? String)?.hasPrefix("data:image/png;base64,"), true)
        XCTAssertNil(NotificationBanner(source: "s", title: "t", body: "", image: Data(count: 200_001)).image)
        XCTAssertNil(NotificationBanner(source: "s", title: "t", body: "").payload["image"])
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
        owner.receive([], generation: old, now: time)
        owner.receive([item("one")], generation: old, now: time)
        owner.advance(blocked: false, now: time)
        XCTAssertNotNil(owner.visible)
        owner.configure(enabled: false, active: true)
        XCTAssertNil(owner.visible)
        owner.receive([item("stale")], generation: old, now: time)
        XCTAssertFalse(owner.hasPending)
        owner.configure(enabled: true, active: false)
        XCTAssertFalse(owner.present(item("suspended").banner, blocked: false))
        owner.configure(enabled: true, active: true)
        owner.receive([item("resume baseline")], generation: owner.generation, now: time)
        XCTAssertFalse(owner.hasPending)
        owner.receive([item("new")], generation: owner.generation, now: time)
        owner.invalidate()
        XCTAssertFalse(owner.hasPending)
        owner.receive([item("permission baseline")], generation: owner.generation, now: time)
        XCTAssertFalse(owner.hasPending)
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
        owner.receive([item("old")], generation: generation, now: time)
        owner.receive([item("old")], generation: generation, now: time.addingTimeInterval(121))
        owner.advance(blocked: false, now: time.addingTimeInterval(121))
        XCTAssertEqual(owner.visible?.title, "old")
        owner.clear()
        // Only the last 64 keys are remembered, so "0" counts as new again; the queue keeps the newest five.
        for index in 0..<100 { owner.receive([item("\(index)")], generation: generation, now: time.addingTimeInterval(122)) }
        owner.receive([item("0")], generation: generation, now: time.addingTimeInterval(122))
        var shown: [String] = []
        for _ in 0..<5 {
            owner.advance(blocked: false, now: time.addingTimeInterval(122))
            shown.append(owner.visible?.title ?? "")
            owner.clear()
        }
        XCTAssertEqual(shown, ["96", "97", "98", "99", "0"])
    }
}

/// Shaped like the macOS 26 reports: window → hosting groups → banner group with UUID and texts.
private final class FixtureNotificationTree: NotificationTreeReading {
    var metadataByID: [Int: NotificationNodeMetadata] = [
        0: .init(identifier: "", role: kAXWindowRole, subrole: "AXSystemDialog"),
        1: .init(identifier: "", role: kAXGroupRole, subrole: "AXHostingView"),
        2: .init(identifier: "6F1C-UUID", role: kAXGroupRole, subrole: "AXNotificationCenterBanner"),
        3: .init(identifier: "title", role: kAXStaticTextRole, subrole: ""),
        4: .init(identifier: "subtitle", role: kAXStaticTextRole, subrole: ""),
        5: .init(identifier: "body", role: kAXStaticTextRole, subrole: "")
    ]
    var edges = [0: [1], 1: [2], 2: [3, 4, 5]]
    var texts: [Int: String] = [2: "WhatsApp, Mia, Lunch?, <img src=x onerror=alert(1)>", 3: "Mia", 4: "Lunch?", 5: "<img src=x onerror=alert(1)>"]
    var reads = 0
    var metadataReads = 0
    func windows(limit: Int) -> [Int] { [0] }
    func metadata(_ node: Int) -> NotificationNodeMetadata? { metadataReads += 1; return metadataByID[node] }
    func children(_ node: Int, limit: Int) -> [Int] { Array((edges[node] ?? []).prefix(limit)) }
    func text(_ node: Int, attribute: String, limit: Int) -> String? { reads += 1; return texts[node] }
}

final class NotificationClassifierTests: XCTestCase {
    func testBannerFieldsSourceAndIdentifierKey() {
        let tree = FixtureNotificationTree()
        let items = NotificationClassifier(limits: .init()).scan(tree)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.banner.source, "WhatsApp")
        XCTAssertEqual(items.first?.banner.title, "Mia")
        XCTAssertEqual(items.first?.banner.body, "Lunch? · <img src=x onerror=alert(1)>")
        XCTAssertEqual(items.first?.key, "6F1C-UUID")
    }

    func testDescriptionOnlyLayoutAndUnknownGroupsReadNoText() {
        let tree = FixtureNotificationTree()
        tree.edges[2] = []
        tree.texts[2] = "Messages, Sam, See you at 8, ok?"
        let items = NotificationClassifier(limits: .init()).scan(tree)
        XCTAssertEqual(items.first?.banner.title, "Sam")
        XCTAssertEqual(items.first?.banner.body, "See you at 8, ok?")
        let other = FixtureNotificationTree()
        other.metadataByID[2] = .init(identifier: "", role: kAXGroupRole, subrole: "AXSomethingElse")
        XCTAssertTrue(NotificationClassifier(limits: .init()).scan(other).isEmpty)
        XCTAssertEqual(other.reads, 0)
    }

    func testOpenHistoryPanelReturnsNothing() {
        let tree = FixtureNotificationTree()
        tree.metadataByID[6] = .init(identifier: "widget-editor-button", role: kAXButtonRole, subrole: "")
        tree.edges[0] = [6, 1]
        XCTAssertTrue(NotificationClassifier(limits: .init()).scan(tree).isEmpty)
        XCTAssertEqual(tree.reads, 0)
    }

    func testNodeDepthStringWindowAndElapsedBudgetsFailClosed() {
        for limits in [NotificationReadLimits(windows: 0), NotificationReadLimits(nodes: 2), NotificationReadLimits(depth: 1), NotificationReadLimits(strings: 0), NotificationReadLimits(elapsed: 0)] {
            let tree = FixtureNotificationTree()
            XCTAssertTrue(NotificationClassifier(limits: limits).scan(tree).isEmpty)
            XCTAssertLessThanOrEqual(tree.metadataReads, max(limits.nodes, 1))
        }
        let tree = FixtureNotificationTree()
        tree.edges[1] = [1]
        tree.metadataByID[1] = .init(identifier: "", role: kAXGroupRole, subrole: "")
        XCTAssertTrue(NotificationClassifier(limits: .init()).scan(tree).isEmpty)
        XCTAssertLessThanOrEqual(tree.metadataReads, 200)
        let long = FixtureNotificationTree()
        long.texts[3] = String(repeating: "x", count: 513)
        XCTAssertEqual(NotificationClassifier(limits: .init()).scan(long).first?.banner.title, "Mia")
        var time: TimeInterval = 0
        XCTAssertTrue(NotificationClassifier(limits: .init()).scan(FixtureNotificationTree(), now: { time += 0.1; return time }).isEmpty)
    }
}
