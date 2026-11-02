import Foundation

struct NotificationBanner: Equatable {
    let id: UUID
    let source: String
    let title: String
    let body: String

    init(id: UUID = UUID(), source: String, title: String, body: String) {
        self.id = id
        self.source = Self.clean(source, limit: 80)
        self.title = Self.clean(title, limit: 160)
        self.body = Self.clean(body, limit: 360)
    }

    static func clean(_ value: String, limit: Int) -> String {
        String(value.prefix(limit).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
    }

    var payload: [String: Any] { ["id": id.uuidString, "source": source, "title": title, "body": body] }
}

// Main-thread owner. No notification text or dedup keys leave this ephemeral session.
final class NotificationBannerOwner {
    private(set) var visible: NotificationBanner?
    private(set) var generation = 0
    private(set) var enabled = false
    private(set) var active = true
    private var baseline = true
    private var seen: [(String, Date)] = []
    private var deadline: Date?
    var onChange: ((NotificationBanner?, UUID) -> Void)?

    func configure(enabled: Bool, active: Bool) {
        guard self.enabled != enabled || self.active != active else {
            if !enabled || !active { clear() }
            return
        }
        self.enabled = enabled
        self.active = active
        invalidate()
    }

    func invalidate() {
        generation += 1
        baseline = true
        seen.removeAll()
        clear()
    }

    func clear(id: UUID? = nil, notify: Bool = true) {
        if let id, visible?.id != id { return }
        let previousID = visible?.id
        visible = nil
        deadline = nil
        if notify, let previousID { onChange?(nil, previousID) }
    }

    @discardableResult
    func present(_ banner: NotificationBanner, blocked: Bool, now: Date = Date()) -> Bool {
        guard active, !blocked, visible == nil else { return false }
        visible = banner
        deadline = now.addingTimeInterval(8)
        onChange?(banner, banner.id)
        return true
    }

    func expire(now: Date = Date()) {
        guard let deadline, now >= deadline, let id = visible?.id else { return }
        clear(id: id)
    }

    func receive(_ items: [CapturedNotification], generation: Int, blocked: Bool, now: Date = Date()) {
        guard generation == self.generation, enabled, active else { return }
        seen.removeAll { now.timeIntervalSince($0.1) > 120 }
        let isBaseline = baseline
        baseline = false
        for item in items.prefix(8) {
            guard !seen.contains(where: { $0.0 == item.key }) else { continue }
            seen.append((item.key, now))
            if seen.count > 64 { seen.removeFirst(seen.count - 64) }
            if !isBaseline { _ = present(item.banner, blocked: blocked, now: now) }
        }
    }
}

struct CapturedNotification {
    let key: String
    let banner: NotificationBanner
}
