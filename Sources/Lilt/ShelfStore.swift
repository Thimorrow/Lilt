import Foundation

final class ShelfStore {
    struct Entry: Codable, Equatable {
        let id: String
        var bookmark: Data
        var lastURL: URL
    }
    static let limit = 24
    private let file: URL
    private(set) var entries: [Entry] = []
    private(set) var message: String?

    init(file: URL) {
        self.file = file
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { entries = Array(try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file)).prefix(Self.limit)) }
        catch { message = "Die gespeicherte Ablage konnte nicht gelesen werden." }
    }

    func add(_ urls: [URL]) {
        message = nil
        var rejected = 0
        for candidate in urls {
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard url.isFileURL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { rejected += 1; continue }
            if entries.contains(where: { resolvedURL(for: $0.id)?.standardizedFileURL.resolvingSymlinksInPath() == url }) { continue }
            guard entries.count < Self.limit else { rejected += 1; continue }
            do {
                let bookmark = try url.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                entries.append(Entry(id: UUID().uuidString, bookmark: bookmark, lastURL: url))
            } catch { rejected += 1 }
        }
        if rejected > 0 { message = "\(rejected) Datei(en) konnten nicht hinzugefügt werden. Die Ablage fasst bis zu \(Self.limit) lokale Dateien." }
        save()
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
    func clear() { entries = []; message = nil; save() }
    func report(_ text: String) { message = text }

    var snapshot: [String: Any] {
        let items: [[String: Any]] = entries.map { entry in
            let url = resolvedURL(for: entry.id)
            let current = url ?? entry.lastURL
            return ["id": entry.id, "name": current.lastPathComponent,
                    "location": current.deletingLastPathComponent().lastPathComponent,
                    "available": url != nil, "kind": current.pathExtension.uppercased()]
        }
        return ["items": items, "limit": Self.limit, "message": message as Any? ?? NSNull()]
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch { message = "Die Ablage konnte nicht gespeichert werden. Prüfe den freien Speicherplatz." }
    }
}
