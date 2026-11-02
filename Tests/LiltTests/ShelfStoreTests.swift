import XCTest
import AppKit
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

    func testMoreThan24FilesSurviveRestart() throws {
        let urls = try (0..<40).map { try fixture("\($0).txt") }
        let shelf = ShelfStore(file: state)
        shelf.add(urls)
        XCTAssertEqual(shelf.entries.count, 40)
        XCTAssertEqual(ShelfStore(file: state).entries.count, 40)
        XCTAssertNil(shelf.message)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testExpirationAndLongerRetentionSurviveRestartWithoutTouchingOriginals() throws {
        let first = try fixture("short.txt")
        let second = try fixture("long.txt")
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let shelf = ShelfStore(file: state, now: { clock })
        shelf.add([first, second], retentionDays: 7)
        let longID = shelf.entries[1].id
        clock.addTimeInterval(3 * 86_400)
        shelf.keepLonger([longID], retentionDays: 30)
        clock.addTimeInterval(4 * 86_400)
        shelf.pruneExpired()
        XCTAssertEqual(shelf.entries.map(\.id), [longID])
        let restored = ShelfStore(file: state, now: { clock })
        XCTAssertEqual(restored.entries.map(\.id), [longID])
        clock.addTimeInterval(25 * 86_400)
        restored.pruneExpired()
        XCTAssertEqual(restored.entries.count, 1)
        clock.addTimeInterval(86_400)
        let expired = ShelfStore(file: state, now: { clock })
        XCTAssertTrue(expired.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: first), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("original".utf8))
    }

    func testLaterRetentionChangesDoNotChangeExistingDeadlines() throws {
        let first = try fixture("first.txt")
        let second = try fixture("second.txt")
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let shelf = ShelfStore(file: state, now: { clock })
        shelf.add([first], retentionDays: 7)
        clock.addTimeInterval(86_400)
        shelf.add([second], retentionDays: 2)
        XCTAssertEqual(shelf.entries[0].expiresAt, Date(timeIntervalSince1970: 1_700_000_000 + 7 * 86_400))
        XCTAssertEqual(shelf.entries[1].expiresAt, clock.addingTimeInterval(2 * 86_400))
    }

    func testLegacyEntriesWithoutDeadlineArePreserved() throws {
        struct LegacyEntry: Encodable { let id: String; let bookmark: Data; let lastURL: URL }
        let url = try fixture("legacy.txt")
        let bookmark = try url.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try JSONEncoder().encode([LegacyEntry(id: "old", bookmark: bookmark, lastURL: url)]).write(to: state)
        let shelf = ShelfStore(file: state, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        shelf.pruneExpired()
        XCTAssertEqual(shelf.entries.map(\.id), ["old"])
        XCTAssertNil(shelf.entries.first?.expiresAt)
    }

    func testImagePreviewIsBoundedAndDoesNotExposeFilePath() throws {
        let url = folder.appendingPathComponent("photo.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        let shelf = ShelfStore(file: state)
        shelf.add([url])
        let ready = expectation(description: "thumbnail arrives")
        shelf.onChange = { ready.fulfill() }
        _ = shelf.snapshot
        wait(for: [ready], timeout: 5)
        let item = try XCTUnwrap((shelf.snapshot["items"] as? [[String: Any]])?.first)
        let preview = try XCTUnwrap(item["thumbnail"] as? String)
        XCTAssertTrue(preview.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertFalse(preview.contains(url.path))
        let data = try XCTUnwrap(Data(base64Encoded: String(preview.dropFirst("data:image/jpeg;base64,".count))))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertLessThanOrEqual(max(decoded.pixelsWide, decoded.pixelsHigh), 96)
        XCTAssertLessThanOrEqual(data.count, 100_000)
    }

    func testUnsupportedAndInvalidImagesFallBackToIcon() throws {
        let document = try fixture("example.txt")
        let invalid = try fixture("bad.png")
        XCTAssertNil(ShelfStore.makeThumbnail(invalid))
        let shelf = ShelfStore(file: state)
        shelf.add([document, invalid])
        let items = try XCTUnwrap(shelf.snapshot["items"] as? [[String: Any]])
        XCTAssertTrue(items.allSatisfy { $0["thumbnail"] == nil })
    }

    func testFolderReferencesPersistAndRemovalNeverTouchesNestedContents() throws {
        let nested = try fixture("project.png/nested/original.txt", content: "nested original")
        let directory = folder.appendingPathComponent("project.png")
        let shelf = ShelfStore(file: state)
        shelf.add([directory, directory])
        XCTAssertEqual(shelf.entries.count, 1)
        let restored = ShelfStore(file: state)
        let id = try XCTUnwrap(restored.entries.first?.id)
        XCTAssertEqual(restored.resolvedURL(for: id), directory.standardizedFileURL.resolvingSymlinksInPath())
        let item = try XCTUnwrap((restored.snapshot["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["kind"] as? String, "FOLDER")
        XCTAssertNil(item["thumbnail"])
        restored.remove(id)
        restored.undoRemoval()
        restored.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try String(contentsOf: nested, encoding: .utf8), "nested original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["nested"])
    }

    func testUndoMultipleRemovalRestoresIDsOrderAndPreservesLaterAdditions() throws {
        let urls = try (0..<5).map { try fixture("\($0).txt") }
        let shelf = ShelfStore(file: state)
        shelf.add(Array(urls.prefix(4)))
        let original = shelf.entries
        shelf.remove([original[0].id, original[2].id])
        shelf.add([urls[4]])
        let added = try XCTUnwrap(shelf.entries.last)
        XCTAssertTrue(shelf.canUndoRemoval)
        shelf.undoRemoval()
        XCTAssertEqual(shelf.entries, original + [added])
        XCTAssertEqual(ShelfStore(file: state).entries, shelf.entries)
        XCTAssertFalse(shelf.canUndoRemoval)
        XCTAssertTrue(urls.allSatisfy { (try? Data(contentsOf: $0)) == Data("original".utf8) })
    }

    func testUndoClearSupportsSuccessiveRemovalsWithoutPersistingHistory() throws {
        let urls = try (0..<3).map { try fixture("\($0).txt") }
        let shelf = ShelfStore(file: state)
        shelf.add(urls)
        let original = shelf.entries
        shelf.remove(original[1].id)
        shelf.clear()
        XCTAssertTrue(shelf.entries.isEmpty)
        XCTAssertFalse(ShelfStore(file: state).canUndoRemoval)
        shelf.undoRemoval()
        XCTAssertEqual(shelf.entries.map(\.id), [original[0].id, original[2].id])
        shelf.undoRemoval()
        XCTAssertEqual(shelf.entries, original)
        XCTAssertFalse(shelf.canUndoRemoval)
    }

    func testUndoSkipsExpiredRemovedEntriesAndKeepsOrderAfterOtherExpiry() throws {
        let urls = try (0..<4).map { try fixture("\($0).txt") }
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let shelf = ShelfStore(file: state, now: { clock })
        shelf.add([urls[0]], retentionDays: 1)
        shelf.add([urls[1]], retentionDays: 1)
        shelf.add([urls[2], urls[3]], retentionDays: 7)
        let original = shelf.entries
        shelf.remove([original[0].id, original[2].id])
        clock.addTimeInterval(2 * 86_400)
        shelf.undoRemoval()
        XCTAssertEqual(shelf.entries.map(\.id), [original[2].id, original[3].id])
        XCTAssertFalse(shelf.canUndoRemoval)
        shelf.pruneExpired()
        XCTAssertFalse(shelf.canUndoRemoval)
    }

    func testUndoDoesNotDuplicateReaddedReference() throws {
        let url = try fixture("same.txt")
        let shelf = ShelfStore(file: state)
        shelf.add([url])
        let removedID = try XCTUnwrap(shelf.entries.first?.id)
        shelf.remove(removedID)
        shelf.add([url])
        let addedID = try XCTUnwrap(shelf.entries.first?.id)
        shelf.undoRemoval()
        XCTAssertEqual(shelf.entries.map(\.id), [addedID])
        XCTAssertNotEqual(removedID, addedID)
    }

    func testUndoHistoryIsBoundedAndNoOpRemovalDoesNotReplaceIt() throws {
        let urls = try (0..<21).map { try fixture("\($0).txt") }
        let shelf = ShelfStore(file: state)
        shelf.add(urls)
        let original = shelf.entries
        for entry in original { shelf.remove(entry.id) }
        shelf.remove("unknown")
        shelf.clear()
        for _ in 0..<20 { shelf.undoRemoval() }
        XCTAssertEqual(shelf.entries.map(\.id), Array(original.dropFirst()).map(\.id))
        XCTAssertFalse(shelf.canUndoRemoval)
    }
}
