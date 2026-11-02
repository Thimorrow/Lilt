import AppKit

// Typed mirrors of the native coordinator snapshots. Parsing happens once here, at the UI boundary.

enum NotchPage: String, CaseIterable {
    case music, focus, shelf
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var title: String { rawValue.capitalized }
    var icon: NotchIcon { self == .music ? .music : self == .focus ? .focus : .shelf }
}

struct NotchMessage: Equatable {
    var code: String
    var message: String
    var action: String?

    init?(_ value: Any?) {
        guard let value = value as? [String: Any], let code = value["code"] as? String,
              let message = value["message"] as? String else { return nil }
        self.code = code
        self.message = message
        action = value["action"] as? String
    }
}

struct MusicState: Equatable {
    enum Availability: String { case checking, ready, offline, empty, unavailable, disabled }

    var availability = Availability.checking
    var id = "", title = "", artist = "", album = "", queueID = ""
    var duration = 0.0, elapsed = 0.0, speed = 1.0
    var playing = false, buffering = false
    var cover: String?
    var canPlay = false, canPause = false, canNext = false, canPrevious = false
    var pending: String?
    var error: NotchMessage?
    var source: String?
    var sourceName: String?
    /// Monotonic time of the snapshot; elapsed playback is interpolated from here.
    var since: TimeInterval = 0

    init() {}

    init?(_ raw: Any?, now: TimeInterval) {
        guard let value = raw as? [String: Any],
              let availability = (value["availability"] as? String).flatMap(Availability.init(rawValue:)) else { return nil }
        func string(_ key: String) -> String? { value[key] == nil ? "" : value[key] as? String }
        func number(_ key: String, _ fallback: Double) -> Double? {
            guard let raw = value[key] else { return fallback }
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
            return number.doubleValue
        }
        func flag(_ key: String) -> Bool? { value[key] == nil ? false : value[key] as? Bool }
        guard let id = string("id"), let title = string("title"), let artist = string("artist"),
              let album = string("album"), let queueID = string("queueID"),
              let duration = number("duration", 0), let elapsed = number("elapsed", 0), let speed = number("speed", 1),
              let playing = flag("playing"), let buffering = flag("buffering"), let canPlay = flag("canPlay"),
              let canPause = flag("canPause"), let canNext = flag("canNext"), let canPrevious = flag("canPrevious") else { return nil }
        let pending = value["pending"] as? String
        if let pending, !["play", "pause", "next", "previous"].contains(pending) { return nil }
        if let error = value["error"], !(error is NSNull), NotchMessage(error) == nil { return nil }
        self.availability = availability
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.queueID = queueID
        self.duration = duration; self.speed = speed
        self.elapsed = duration > 0 ? min(duration, elapsed) : elapsed
        self.pending = pending
        self.error = NotchMessage(value["error"])
        source = value["source"] as? String
        sourceName = value["sourceName"] as? String
        since = now
        if let cover = value["cover"] as? String, cover.count <= 90_000, cover.hasPrefix("data:image/jpeg;base64,") { self.cover = cover }
        if availability == .ready {
            self.playing = playing && !buffering
            self.buffering = buffering
            self.canPlay = canPlay; self.canPause = canPause; self.canNext = canNext; self.canPrevious = canPrevious
        }
    }

    func elapsed(at now: TimeInterval) -> Double {
        let value = elapsed + (playing ? max(0, now - since) * speed : 0)
        return duration > 0 ? min(duration, value) : value
    }

    /// Equality that ignores the arrival time, so identical repeated polls cause no re-render.
    func sameContent(as other: MusicState) -> Bool {
        var a = self, b = other
        a.since = 0; b.since = 0
        return a == b
    }
}

struct FocusState: Equatable {
    enum Phase: String { case idle, running, paused, completed, uncertain, checking }

    struct Interval: Equatable {
        var workMinutes: Int
        var restMinutes: Int
        var phase: String
        var state: String
    }

    var activity = "deepWork"
    var duration = 1500
    var remaining = 1500.0
    var phase = Phase.checking
    var restoring = true
    var pending: String?
    var error: NotchMessage?
    var canExtend = false
    var brainFMEnabled: Bool?
    var interval: Interval?
    var ready = false

    init() {}

    init?(_ raw: Any?) {
        guard let value = raw as? [String: Any],
              let activity = value["activity"] as? String, ["deepWork", "lightWork"].contains(activity),
              let phase = (value["phase"] as? String).flatMap(Phase.init(rawValue:)),
              let duration = value["duration"] as? Int, (60...10800).contains(duration),
              let remaining = (value["remaining"] as? NSNumber)?.doubleValue, remaining.isFinite, (0...10800).contains(remaining) else { return nil }
        if value["canExtend"] != nil, !(value["canExtend"] is Bool) { return nil }
        if let total = value["totalDuration"], !(total is NSNull) {
            guard let total = total as? Int, (duration...10800).contains(total) else { return nil }
        }
        self.activity = activity
        self.duration = duration
        self.remaining = remaining
        self.phase = phase
        restoring = value["restoring"] as? Bool ?? false
        pending = (value["pending"] as? [String: Any])?["action"] as? String
        error = NotchMessage(value["error"])
        canExtend = value["canExtend"] as? Bool ?? false
        brainFMEnabled = value["brainFMEnabled"] as? Bool
        if let interval = value["interval"] as? [String: Any], let work = interval["workMinutes"] as? Int,
           let rest = interval["restMinutes"] as? Int, let phase = interval["phase"] as? String, let state = interval["state"] as? String {
            self.interval = Interval(workMinutes: work, restMinutes: rest, phase: phase, state: state)
        }
        ready = true
    }

    var locked: Bool { !ready || pending != nil || phase == .running || phase == .uncertain || restoring }
    var primaryAction: String { error?.action ?? (phase == .running ? "pause" : "start") }
    var isBreak: Bool { interval?.phase == "rest" }
    var awaitingNext: Bool { interval?.state == "awaitingNext" }
}

struct ShelfItem: Identifiable, Equatable {
    var id: String
    var name: String
    var location: String
    var available: Bool
    var kind: String
    var retention: String
    var thumbnail: NSImage?

    init?(_ raw: Any) {
        guard let value = raw as? [String: Any], let id = value["id"] as? String, let name = value["name"] as? String,
              let location = value["location"] as? String, let available = value["available"] as? Bool else { return nil }
        self.id = id; self.name = name; self.location = location; self.available = available
        let kind = value["kind"] as? String ?? ""
        self.kind = kind == "FOLDER" || kind.range(of: "^[A-Z0-9]{1,4}$", options: .regularExpression) != nil ? kind : ""
        retention = value["retention"] as? String ?? "short"
        if let uri = value["thumbnail"] as? String, uri.count <= 200_000 { thumbnail = decodeDataImage(uri, types: ["png", "jpeg"]) }
    }

    static func == (a: ShelfItem, b: ShelfItem) -> Bool {
        a.id == b.id && a.name == b.name && a.location == b.location && a.available == b.available
            && a.kind == b.kind && a.retention == b.retention && (a.thumbnail == nil) == (b.thumbnail == nil)
    }
}

struct NotificationBannerContent: Equatable {
    var id: String
    var source: String
    var title: String
    var body: String
    var image: NSImage?

    init?(_ raw: Any?) {
        guard let value = raw as? [String: Any], let id = value["id"] as? String, UUID(uuidString: id) != nil,
              let source = value["source"] as? String, let title = value["title"] as? String,
              let body = value["body"] as? String else { return nil }
        let clean = { (text: String, limit: Int) in
            String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit).filter { $0 == "\n" || ($0.value >= 0x20 && $0.value != 0x7f) }))
        }
        self.id = id
        self.source = clean(source, 80)
        self.title = clean(title, 160)
        self.body = clean(body, 360)
        if let uri = value["image"] as? String, uri.count <= 280_000 { image = decodeDataImage(uri, types: ["png", "jpeg"]) }
    }
}

/// Mirrors `selectShelfItem` from the web shelf: plain, toggle (⌘) and range (⇧) selection.
struct ShelfSelection: Equatable {
    var selected: Set<String> = []
    var anchor: String?

    mutating func select(_ id: String, in ids: [String], toggle: Bool = false, range: Bool = false) {
        guard let index = ids.firstIndex(of: id) else { return }
        if range, let anchor, let from = ids.firstIndex(of: anchor) {
            let span = Set(ids[min(from, index)...max(from, index)])
            selected = toggle ? selected.union(span) : span
            return
        }
        if toggle {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
            return
        }
        selected = [id]
        anchor = id
    }

    mutating func retain(_ ids: [String]) {
        let known = Set(ids)
        selected.formIntersection(known)
        if let anchor, !known.contains(anchor) { self.anchor = nil }
    }
}

func decodeDataImage(_ uri: String, types: [String]) -> NSImage? {
    guard let comma = uri.firstIndex(of: ","), types.contains(where: { uri.hasPrefix("data:image/\($0);base64,") }),
          let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { return nil }
    return NSImage(data: data)
}
