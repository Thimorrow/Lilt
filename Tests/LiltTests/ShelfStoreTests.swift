import XCTest
@testable import Lilt

final class ShelfStoreTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("lilt-shelf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private var state: URL { folder.appendingPathComponent("shelf.json") }
    private func fixture(_ name: String, content: String = "original") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    func testReferencesPersistAndSameNamedFilesRemainDistinct() throws {
        let first = try fixture("a/same.txt", content: "first original")
        let second = try fixture("b/same.txt", content: "second original")
        let shelf = ShelfStore(file: state)
        shelf.add([first, second, first])
        XCTAssertEqual(shelf.entries.count, 2)
        let restored = ShelfStore(file: state)
        XCTAssertEqual(restored.entries.map(\.id), shelf.entries.map(\.id))
        XCTAssertEqual(restored.resolvedURL(for: restored.entries[0].id), first.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(restored.resolvedURL(for: restored.entries[1].id), second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first original")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second original")
    }

    func testRemovingAndClearingNeverTouchesOriginals() throws {
        let first = try fixture("first.txt")
        let second = try fixture("second.txt")
        let shelf = ShelfStore(file: state)
        shelf.add([first, second])
        shelf.remove(shelf.entries[0].id)
        XCTAssertEqual(shelf.entries.count, 1)
        shelf.clear()
        XCTAssertTrue(ShelfStore(file: state).entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: first), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("original".utf8))
    }

    func testMissingFileKeepsRemovableEntry() throws {
        let url = try fixture("disposable.txt")
        let shelf = ShelfStore(file: state)
        shelf.add([url])
        let id = shelf.entries[0].id
        try FileManager.default.removeItem(at: url)
        let restored = ShelfStore(file: state)
        XCTAssertNil(restored.resolvedURL(for: id))
        XCTAssertEqual((restored.snapshot["items"] as? [[String: Any]])?.first?["available"] as? Bool, false)
        restored.remove(id)
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testFullShelfReportsRejectedFilesAndRetainsAllAcceptedEntries() throws {
        let urls = try (0...ShelfStore.limit).map { try fixture("\($0).txt") }
        let shelf = ShelfStore(file: state)
        shelf.add(urls)
        XCTAssertEqual(shelf.entries.count, ShelfStore.limit)
        XCTAssertNotNil(shelf.message)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
