import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ShelfStore {
    struct Entry: Codable, Equatable {
        let id: String
        var bookmark: Data
        var lastURL: URL
        var expiresAt: Date?
        var retention: String?
    }
    private let file: URL
    private let now: () -> Date
    private let thumbnailQueue = DispatchQueue(label: "Lilt.shelf.thumbnails", qos: .utility)
    private var thumbnails: [String: (signature: String, value: String)] = [:]
    private var thumbnailPending: [String: String] = [:]
    private var thumbnailNotification: DispatchWorkItem?
    var onChange: (() -> Void)?
    private(set) var entries: [Entry] = []
    private(set) var message: String?

    init(file: URL, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.now = now
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
            pruneExpired()
        }
        catch { message = "Die gespeicherte Ablage konnte nicht gelesen werden." }
    }

    func add(_ urls: [URL], retentionDays: Int = 7) {
        message = nil
        pruneExpired()
        let expiration = now().addingTimeInterval(TimeInterval(max(1, retentionDays)) * 86_400)
        var rejected = 0
        for candidate in urls {
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard url.isFileURL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { rejected += 1; continue }
            if entries.contains(where: { resolvedURL(for: $0.id)?.standardizedFileURL.resolvingSymlinksInPath() == url }) { continue }
            do {
                let bookmark = try url.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                entries.append(Entry(id: UUID().uuidString, bookmark: bookmark, lastURL: url, expiresAt: expiration, retention: "short"))
            } catch { rejected += 1 }
        }
        if rejected > 0 { message = "\(rejected) Datei(en) konnten nicht hinzugefügt werden." }
        save()
    }

    func keepLonger(_ ids: [String], retentionDays: Int = 30) {
        pruneExpired()
        let selected = Set(ids)
        let expiration = now().addingTimeInterval(TimeInterval(max(1, retentionDays)) * 86_400)
        for index in entries.indices where selected.contains(entries[index].id) {
            entries[index].expiresAt = expiration
            entries[index].retention = "long"
        }
        message = nil
        save()
    }

    func pruneExpired() {
        let deadline = now()
        let count = entries.count
        entries.removeAll { entry in entry.expiresAt.map { $0 <= deadline } ?? false }
        if entries.count != count { save() }
    }

    func resolvedURL(for id: String) -> URL? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = entries[index]
        var stale = false
        let bookmarked = (try? URL(resolvingBookmarkData: entry.bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)) ?? entry.lastURL
        let resolved = bookmarked.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        if stale || resolved != entry.lastURL,
           let bookmark = try? resolved.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            entries[index].bookmark = bookmark
            entries[index].lastURL = resolved
            save()
        }
        return resolved
    }

    func remove(_ id: String) { entries.removeAll { $0.id == id }; message = nil; save() }
    func remove(_ ids: [String]) { let selected = Set(ids); entries.removeAll { selected.contains($0.id) }; message = nil; save() }
    func clear() { entries = []; message = nil; save() }
    func report(_ text: String) { message = text }

    var snapshot: [String: Any] {
        let ids = Set(entries.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        let items: [[String: Any]] = entries.enumerated().map { index, entry in
            let url = resolvedURL(for: entry.id)
            let current = url ?? entry.lastURL
            var item: [String: Any] = ["id": entry.id, "name": current.lastPathComponent,
                    "location": current.deletingLastPathComponent().lastPathComponent,
                    "available": url != nil, "kind": current.pathExtension.uppercased(),
                    "expiresAt": entry.expiresAt.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
                    "retention": entry.retention ?? "legacy"]
            if index < 128, let url, let preview = thumbnail(for: entry.id, url: url) {
                item["thumbnail"] = preview
            }
            return item
        }
        return ["items": items, "message": message as Any? ?? NSNull()]
    }

    private func thumbnail(for id: String, url: URL) -> String? {
        guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              let info = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              info.isRegularFile == true, let size = info.fileSize, size > 0, size <= 20_000_000,
              let modified = info.contentModificationDate else { return nil }
        let signature = "\(url.path)|\(size)|\(modified.timeIntervalSinceReferenceDate)"
        if let cached = thumbnails[id], cached.signature == signature {
            return cached.value.isEmpty ? nil : cached.value
        }
        guard thumbnailPending[id] != signature else { return nil }
        thumbnailPending[id] = signature
        thumbnailQueue.async { [weak self] in
            let result = Self.makeThumbnail(url) ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self, self.thumbnailPending[id] == signature else { return }
                self.thumbnailPending[id] = nil
                guard self.entries.contains(where: { $0.id == id }) else { return }
                self.thumbnails[id] = (signature, result)
                self.thumbnailNotification?.cancel()
                let notification = DispatchWorkItem { [weak self] in self?.onChange?() }
                self.thumbnailNotification = notification
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: notification)
            }
        }
        return nil
    }

    static func makeThumbnail(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              Double(width) * Double(height) <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
                  kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 100_000 else { return nil }
        return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch { message = "Die Ablage konnte nicht gespeichert werden. Prüfe den freien Speicherplatz." }
    }
}
