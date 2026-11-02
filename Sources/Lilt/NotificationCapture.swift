import AppKit
import ApplicationServices

struct NotificationReadLimits {
    var windows = 4
    var nodes = 200
    var depth = 10
    var strings = 24
    var stringLength = 512
    var elapsed: TimeInterval = 0.15
    var messagingTimeout: Float = 0.04
}

struct NotificationNodeMetadata {
    let identifier: String
    let role: String
    let subrole: String
}

// Metadata and content are separate operations so only a classified banner is ever a text probe.
protocol NotificationTreeReading {
    func windows(limit: Int) -> [Int]
    func metadata(_ node: Int) -> NotificationNodeMetadata?
    func children(_ node: Int, limit: Int) -> [Int]
    func text(_ node: Int, attribute: String, limit: Int) -> String?
}

/// macOS 26 layout (public reports, see docs/FEATURE-PLAN.md): a transient banner is an `AXGroup` with subrole
/// `AXNotificationCenterBanner`/`AXNotificationCenterAlert`, a per-notification UUID identifier, `AXStaticText`
/// children `title`/`subtitle`/`body`, and the sending app as the first item of its description.
struct NotificationClassifier {
    static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    /// Present only while the user has the Notification Center history or widgets open; nothing is read then.
    static let historyMarkers: Set<String> = ["widget-editor-button", "AXNotificationListItems"]
    static let fields: Set<String> = ["title", "subtitle", "body"]

    let limits: NotificationReadLimits

    func scan(_ reader: NotificationTreeReading, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> [CapturedNotification] {
        let start = now()
        var nodes = 0
        var strings = 0
        var history = false
        var results: [CapturedNotification] = []
        func permitted(_ depth: Int) -> Bool {
            !history && depth <= limits.depth && nodes < limits.nodes && now() - start < limits.elapsed
        }
        func meta(_ node: Int) -> NotificationNodeMetadata? {
            nodes += 1
            guard let value = reader.metadata(node), value.identifier.count <= limits.stringLength,
                  value.role.count <= 80, value.subrole.count <= 80 else { return nil }
            if Self.historyMarkers.contains(value.identifier) || Self.historyMarkers.contains(value.subrole) { history = true }
            return value
        }
        func read(_ node: Int, _ attribute: String) -> String? {
            guard strings < limits.strings, now() - start < limits.elapsed else { return nil }
            strings += 1
            guard let text = reader.text(node, attribute: attribute, limit: limits.stringLength), text.count <= limits.stringLength else { return nil }
            return text
        }
        func readBanner(_ node: Int, identifier: String, depth: Int) {
            var fields: [String: String] = [:]
            func collect(_ parent: Int, _ level: Int) {
                guard level <= 3, permitted(depth + level) else { return }
                for child in reader.children(parent, limit: 12).prefix(12) {
                    guard permitted(depth + level), let metadata = meta(child) else { continue }
                    if metadata.role == kAXStaticTextRole, Self.fields.contains(metadata.identifier), fields[metadata.identifier] == nil {
                        fields[metadata.identifier] = read(child, kAXValueAttribute)
                    } else {
                        collect(child, level + 1)
                    }
                }
            }
            collect(node, 1)
            let description = read(node, kAXDescriptionAttribute) ?? ""
            let parts = description.components(separatedBy: ", ")
            let source = parts.count > 1 ? parts[0] : ""
            var title = fields["title"] ?? ""
            var body = [fields["subtitle"], fields["body"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            // Older layouts expose only the description: "App, Title, Body".
            if title.isEmpty, parts.count > 1 {
                title = parts[1]
                if body.isEmpty { body = parts.dropFirst(2).joined(separator: ", ") }
            }
            guard !history, !source.isEmpty, !title.isEmpty else { return }
            let banner = NotificationBanner(source: source, title: title, body: body)
            // Ephemeral, bounded key. Never persisted, hashed or logged.
            let key = identifier.isEmpty ? "\(banner.source)\u{0}\(banner.title)\u{0}\(banner.body)" : identifier
            results.append(CapturedNotification(key: key, banner: banner))
        }
        func visit(_ node: Int, depth: Int) {
            guard permitted(depth), results.count < 8, let metadata = meta(node) else { return }
            if metadata.role == kAXGroupRole, Self.bannerSubroles.contains(metadata.subrole) {
                readBanner(node, identifier: metadata.identifier, depth: depth)
                return
            }
            for child in reader.children(node, limit: max(0, limits.nodes - nodes)).prefix(limits.nodes) {
                visit(child, depth: depth + 1)
            }
        }
        for window in reader.windows(limit: limits.windows).prefix(limits.windows) {
            guard permitted(0), let metadata = meta(window), metadata.role == kAXWindowRole else { continue }
            for child in reader.children(window, limit: max(0, limits.nodes - nodes)).prefix(limits.nodes) { visit(child, depth: 1) }
        }
        // A cut-off or history-visible scan returns nothing rather than a partial, possibly historical read.
        return history || now() - start >= limits.elapsed ? [] : results
    }
}

enum NotificationCaptureStatus: String {
    case disabled, diagnostic, suspended, permission, active

    var message: String {
        switch self {
        case .disabled: return "Off. No other apps are read."
        case .diagnostic: return "Capture and permission actions are disabled in diagnostics. Preview uses synthetic text only."
        case .suspended: return "Suspended while the session is inactive or the Mac is sleeping."
        case .permission: return "Allow Lilt in System Settings → Privacy & Security → Accessibility."
        case .active: return "On. Banners are shown and never saved."
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

/// Public AX reads of the Notification Center process only, each bounded by the messaging timeout.
private final class AXNotificationTree: NotificationTreeReading {
    private var elements: [AXUIElement] = []
    private let app: AXUIElement

    init(pid: pid_t, timeout: Float) {
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private func register(_ list: [AXUIElement], limit: Int) -> [Int] {
        list.prefix(limit).map { elements.append($0); return elements.count - 1 }
    }

    func windows(limit: Int) -> [Int] { register(value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [], limit: limit) }

    func metadata(_ node: Int) -> NotificationNodeMetadata? {
        let element = elements[node]
        guard let role = value(element, kAXRoleAttribute) as? String else { return nil }
        return .init(identifier: value(element, kAXIdentifierAttribute) as? String ?? "", role: role,
                     subrole: value(element, kAXSubroleAttribute) as? String ?? "")
    }

    func children(_ node: Int, limit: Int) -> [Int] {
        let element = elements[node]
        let list = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? value(element, "AXOrderedChildren") as? [AXUIElement] ?? []
        return register(list, limit: limit)
    }

    func text(_ node: Int, attribute: String, limit: Int) -> String? {
        (value(elements[node], attribute) as? String).map { String($0.prefix(limit + 1)) }
    }
}

struct NotificationCenterCapture: NotificationCapturing {
    static let bundleIdentifier = "com.apple.notificationcenterui"
    let limits = NotificationReadLimits()

    func scan() -> NotificationCaptureResult {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard AXIsProcessTrusted() else { return .init(status: .permission, items: []) }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            return .init(status: .active, items: [])
        }
        let tree = AXNotificationTree(pid: process.processIdentifier, timeout: limits.messagingTimeout)
        return .init(status: .active, items: NotificationClassifier(limits: limits).scan(tree))
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
