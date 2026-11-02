import AppKit
import ApplicationServices

struct NotificationReadLimits {
    var windows = 4
    var nodes = 64
    var depth = 6
    var strings = 24
    var stringLength = 512
    var elapsed: TimeInterval = 0.15
    var messagingTimeout: Float = 0.04
}

struct NotificationNodeMetadata {
    let identifier: String
    let role: String
}

// Metadata and content are separate operations so an unknown/history tree is never a text probe.
protocol NotificationTreeReading {
    func windows(limit: Int) -> [Int]
    func metadata(_ node: Int) -> NotificationNodeMetadata?
    func children(_ node: Int, limit: Int) -> [Int]
    func text(_ node: Int, limit: Int) -> String?
}

struct NotificationLayout {
    let transientWindow: String
    let banner: String
    let source: String
    let title: String
    let body: String
}

struct NotificationClassifier {
    let limits: NotificationReadLimits
    let layout: NotificationLayout?

    func scan(_ reader: NotificationTreeReading, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> [CapturedNotification] {
        guard let layout else { return [] }
        let start = now()
        var nodes = 0
        var strings = 0
        var results: [CapturedNotification] = []
        func permitted(_ depth: Int) -> Bool {
            depth <= limits.depth && nodes < limits.nodes && now() - start < limits.elapsed
        }
        func readMetadata(_ node: Int) -> NotificationNodeMetadata? {
            guard let value = reader.metadata(node), value.identifier.count <= limits.stringLength,
                  value.role.count <= 80, now() - start < limits.elapsed else { return nil }
            return value
        }
        func visit(_ node: Int, depth: Int) {
            guard permitted(depth), results.count < 8 else { return }
            nodes += 1
            guard let metadata = readMetadata(node), permitted(depth + 1) else { return }
            if metadata.identifier == layout.banner, metadata.role == kAXGroupRole {
                var fields: [String: String] = [:]
                for child in reader.children(node, limit: min(8, limits.nodes - nodes)).prefix(8) {
                    guard permitted(depth + 1), strings < limits.strings else { return }
                    nodes += 1
                    guard let field = readMetadata(child), field.role == kAXStaticTextRole,
                          [layout.source, layout.title, layout.body].contains(field.identifier),
                          fields[field.identifier] == nil else { continue }
                    strings += 1
                    guard let text = reader.text(child, limit: limits.stringLength), text.count <= limits.stringLength,
                          now() - start < limits.elapsed else { return }
                    fields[field.identifier] = text
                }
                guard let source = fields[layout.source], let title = fields[layout.title], !source.isEmpty, !title.isEmpty else { return }
                // Ephemeral, bounded key. Never persisted, hashed or logged.
                let body = fields[layout.body] ?? ""
                let banner = NotificationBanner(source: source, title: title, body: body)
                results.append(CapturedNotification(key: "\(banner.source)\u{0}\(banner.title)\u{0}\(banner.body)", banner: banner))
                return
            }
            for child in reader.children(node, limit: max(0, limits.nodes - nodes)).prefix(limits.nodes) {
                visit(child, depth: depth + 1)
            }
        }
        for window in reader.windows(limit: limits.windows).prefix(limits.windows) {
            guard permitted(0) else { break }
            nodes += 1
            guard let metadata = readMetadata(window), metadata.role == kAXWindowRole,
                  metadata.identifier == layout.transientWindow, permitted(1) else { continue }
            for child in reader.children(window, limit: max(0, limits.nodes - nodes)).prefix(limits.nodes) { visit(child, depth: 1) }
        }
        return now() - start < limits.elapsed ? results : []
    }
}

enum NotificationCaptureStatus: String {
    case disabled, diagnostic, suspended, permission, unsupported

    var message: String {
        switch self {
        case .disabled: return "Off. No notifications are read."
        case .diagnostic: return "Capture and permission actions are disabled in diagnostics. Preview uses synthetic text only."
        case .suspended: return "Suspended while the session is inactive or the Mac is sleeping."
        case .permission: return "Accessibility permission is needed. Capture also requires a verified system layout."
        case .unsupported: return "Unsupported/unverified Notification Center layout. No notification content is read. Preview is synthetic."
        }
    }
}

struct NotificationCaptureResult {
    let status: NotificationCaptureStatus
    let items: [CapturedNotification]
}

protocol NotificationCapturing {
    func scan() -> NotificationCaptureResult
}

struct NotificationCenterCapture: NotificationCapturing {
    static let bundleIdentifier = "com.apple.notificationcenterui"
    let limits = NotificationReadLimits()

    func scan() -> NotificationCaptureResult {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard AXIsProcessTrusted() else { return .init(status: .permission, items: []) }
        // No public, locally verified transient-window/banner identifiers are known.
        // Do not enumerate AX windows/children or read text until a reviewed profile exists.
        // A future reader must target only bundleIdentifier, set the AX messaging timeout,
        // and enforce NotificationReadLimits before each public AX attribute operation.
        return .init(status: .unsupported, items: [])
    }
}

final class NotificationPoller {
    private let queue = DispatchQueue(label: "lilt.notification-capture", qos: .utility)
    private var inFlight = false
    private let capture: NotificationCapturing

    init(capture: NotificationCapturing = NotificationCenterCapture()) { self.capture = capture }

    func poll(completion: @escaping (NotificationCaptureResult) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !inFlight else { return }
        inFlight = true
        queue.async {
            let result = self.capture.scan()
            DispatchQueue.main.async {
                self.inFlight = false
                completion(result)
            }
        }
    }
}
