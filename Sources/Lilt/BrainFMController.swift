import AppKit
import ApplicationServices

final class BrainFMController: BrainFMControlling {
    enum Command { case play, pause }
    enum PlaybackState: String { case playing, paused }
    struct ControlError: Error, Equatable {
        let code: String
        let message: String
        static let permission = Self(code: "permission", message: "Erlaube Lilt unter Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen.")
        static let missing = Self(code: "notInstalled", message: "Die Brain.fm-App wurde nicht gefunden.")
        static let unavailable = Self(code: "unavailable", message: "Öffne Brain.fm und prüfe deine Anmeldung und die Fokus-Auswahl.")
        static let activity = Self(code: "wrongActivity", message: "In Brain.fm ist eine andere Aktivität ausgewählt. Starte die gewünschte Sitzung erneut in Lilt.")
        static let ambiguous = Self(code: "ambiguous", message: "Die Wiedergabe ist nicht eindeutig erkennbar. Öffne einen einzelnen Brain.fm-Player.")
        static let timeout = Self(code: "timeout", message: "Brain.fm hat die Wiedergabe nicht bestätigt. Prüfe den Player und versuche es erneut.")
        static let busy = Self(code: "busy", message: "Brain.fm wird gerade gesteuert. Bitte kurz warten.")
    }

    struct Snapshot: Equatable {
        var play = 0
        var pause = 0
        var deepWork = 0
        var lightWork = 0
        var previous = 0
        var next = 0
        var activity: String?
        var start = 0
        var activityPicker = false
    }
    enum Decision: Equatable {
        case confirmed(PlaybackState)
        case press(String)
        case failure(ControlError)
    }

    static func decide(_ command: Command, activity: FocusActivity = .deepWork, snapshot: Snapshot) -> Decision {
        guard snapshot.play + snapshot.pause <= 1, snapshot.deepWork <= 1, snapshot.lightWork <= 1, snapshot.start <= 1 else { return .failure(.ambiguous) }
        if snapshot.activityPicker { return .failure(.unavailable) }
        if snapshot.play + snapshot.pause == 1, snapshot.previous == 1, snapshot.next == 1 {
            guard snapshot.activity == activity.title else {
                return command == .play && snapshot.start == 1 ? .press("START") : .failure(.activity)
            }
            let state: PlaybackState = snapshot.pause == 1 ? .playing : .paused
            switch (command, state) {
            case (.play, .playing), (.pause, .paused): return .confirmed(state)
            case (.play, .paused): return .press("Play")
            case (.pause, .playing): return .press("Pause")
            }
        }
        let homeCount = activity == .deepWork ? snapshot.deepWork : snapshot.lightWork
        if homeCount == 1, snapshot.play + snapshot.pause == 0 {
            return command == .play ? .press(activity.launchLabel) : .failure(.unavailable)
        }
        return .failure(.unavailable)
    }

    private static let bundleID = "com.electron.brain.fm"
    private let queue = DispatchQueue(label: "local.lilt.brainfm-control", qos: .userInitiated)
    private var busy = false
    private let summaryLock = NSLock()
    private var scanSummary: [String: Int] = [:]
    private var navigationSummary: [String: Int] = [:]
    var lastScanSummary: [String: Int] {
        summaryLock.lock(); defer { summaryLock.unlock() }
        return scanSummary.merging(navigationSummary) { _, latest in latest }
    }
    private func recordScan(_ summary: [String: Int]) {
        summaryLock.lock(); defer { summaryLock.unlock() }
        scanSummary = summary
    }
    private var operationID: UUID?
    var hasPermission: Bool { AXIsProcessTrusted() }
    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) }

    func perform(_ command: Command, activity: FocusActivity = .deepWork, completion: @escaping (Result<PlaybackState, ControlError>) -> Void) {
        DispatchQueue.main.async { [self] in
            guard !busy else { completion(.failure(.busy)); return }
            guard hasPermission else { completion(.failure(.permission)); return }
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
                let operation = begin(completion: completion)
                run(command, activity: activity, pid: app.processIdentifier, operation: operation, completion: completion)
                return
            }
            guard command == .play else { completion(.success(.paused)); return }
            guard let url = applicationURL else { completion(.failure(.missing)); return }
            let operation = begin(completion: completion)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] app, error in
                DispatchQueue.main.async {
                    guard let self, self.operationID == operation.id, Date() < operation.deadline else { return }
                    guard error == nil, let app else {
                        self.finish(.failure(.unavailable), operationID: operation.id, completion: completion)
                        return
                    }
                    self.run(command, activity: activity, pid: app.processIdentifier, operation: operation, completion: completion)
                }
            }
        }
    }

    func inspect(activity: FocusActivity = .deepWork, completion: @escaping (Result<PlaybackState, ControlError>) -> Void) {
        DispatchQueue.main.async { [self] in
            guard !busy else { completion(.failure(.busy)); return }
            guard hasPermission else { completion(.failure(.permission)); return }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else {
                completion(.success(.paused)); return
            }
            let operation = begin(seconds: 3, completion: completion)
            queue.async { [self] in
                let root = applicationElement(pid: app.processIdentifier)
                let result: Result<PlaybackState, ControlError>
                if let scan = scan(root, deadline: Date().addingTimeInterval(2.5)) {
                    if scan.snapshot.activityPicker { result = .failure(.unavailable) }
                    else if scan.snapshot.play + scan.snapshot.pause == 1,
                            scan.snapshot.previous == 1, scan.snapshot.next == 1 {
                        if scan.snapshot.activity == activity.title {
                            result = .success(scan.snapshot.pause == 1 ? .playing : .paused)
                        } else { result = .failure(.activity) }
                    } else { result = .failure(.unavailable) }
                } else { result = .failure(.unavailable) }
                finish(result, operationID: operation.id, completion: completion)
            }
        }
    }

    private func run(_ command: Command, activity: FocusActivity, pid: pid_t, operation: (id: UUID, deadline: Date), completion: @escaping (Result<PlaybackState, ControlError>) -> Void) {
        queue.async { [self] in
            let root = applicationElement(pid: pid)
            let deadline = operation.deadline
            var stableReads = 0
            var lastState: PlaybackState?
            var lastPress: String?
            var lastPressTime = Date.distantPast
            var presses = 0
            var lastError = ControlError.unavailable
            while Date() < deadline {
                guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                      app.bundleIdentifier == Self.bundleID else {
                    finish(.failure(.unavailable), operationID: operation.id, completion: completion); return
                }
                guard hasPermission else { finish(.failure(.permission), operationID: operation.id, completion: completion); return }
                guard let scan = scan(root, deadline: min(deadline, Date().addingTimeInterval(3))) else {
                    stableReads = 0
                    lastError = .timeout
                    Thread.sleep(forTimeInterval: 0.25)
                    continue
                }
                guard Date() < deadline else { break }
                switch Self.decide(command, activity: activity, snapshot: scan.snapshot) {
                case .confirmed(let state):
                    stableReads = lastState == state ? stableReads + 1 : 1
                    lastState = state
                    if stableReads >= 3 && (lastPress == nil || Date().timeIntervalSince(lastPressTime) >= 1) {
                        finish(.success(state), operationID: operation.id, completion: completion); return
                    }
                case .press(let label):
                    stableReads = 0
                    lastState = nil
                    // Home launches briefly expose Play before their automatic start has settled.
                    let settlingLaunch = lastPress == activity.launchLabel && Date().timeIntervalSince(lastPressTime) < 2
                    if !settlingLaunch, presses < 5, Date().timeIntervalSince(lastPressTime) >= 1.6,
                       let target = scan.targets[label], target.count == 1 {
                        lastPressTime = Date()
                        presses += 1
                        if press(label, element: target[0], pid: pid) { lastPress = label }
                        else { lastError = .unavailable }
                    }
                case .failure(let error):
                    stableReads = 0
                    lastState = nil
                    lastError = error
                    if error == .activity || error == .ambiguous {
                        finish(.failure(error), operationID: operation.id, completion: completion); return
                    }
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            finish(.failure(lastPress == nil ? lastError : .timeout), operationID: operation.id, completion: completion)
        }
    }

    private func begin(seconds: TimeInterval = 16, completion: @escaping (Result<PlaybackState, ControlError>) -> Void) -> (id: UUID, deadline: Date) {
        let id = UUID()
        busy = true
        operationID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.finish(.failure(.timeout), operationID: id, completion: completion)
        }
        return (id, Date().addingTimeInterval(seconds))
    }

    private func finish(_ result: Result<PlaybackState, ControlError>, operationID id: UUID, completion: @escaping (Result<PlaybackState, ControlError>) -> Void) {
        DispatchQueue.main.async { [self] in
            guard operationID == id else { return }
            operationID = nil
            busy = false
            completion(result)
        }
    }

    private func applicationElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.08)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return element
    }

    private func press(_ label: String, element: AXUIElement, pid: pid_t) -> Bool {
        guard ["Play", "Pause", "START", FocusActivity.deepWork.launchLabel, FocusActivity.lightWork.launchLabel].contains(label),
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Self.bundleID else { return false }
        if label == "START" {
            // Electron exposes Press on the navigation item's parent, not its text.
            var target = element
            for depth in 0..<4 {
                if string(target, kAXRoleAttribute) == "AXWebArea" { break }
                var names: CFArray?
                _ = AXUIElementCopyActionNames(target, &names)
                let actions = names as? [String] ?? []
                summaryLock.lock()
                navigationSummary["navigationActions\(depth)"] = actions.count
                navigationSummary["navigationPress\(depth)"] = actions.contains(kAXPressAction as String) ? 1 : 0
                summaryLock.unlock()
                if actions.contains(kAXPressAction as String), AXUIElementPerformAction(target, kAXPressAction as CFString) == .success { return true }
                guard let parent = attribute(target, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                target = parent as! AXUIElement
            }
            return false
        }
        let key: CGKeyCode = label.hasPrefix("Go to ") ? 36 : 49
        guard AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = []; up.flags = []
        down.postToPid(pid); up.postToPid(pid)
        return true
    }

    private struct Scan {
        var snapshot = Snapshot()
        var targets: [String: [AXUIElement]] = [:]
    }

    private func scan(_ root: AXUIElement, deadline: Date) -> Scan? {
        var result = Scan()
        var pending = [root]
        var visited: [CFHashCode: [AXUIElement]] = [:]
        var count = 0
        var activityLabels = Set<String>()
        let wanted = Set(["Play", "Pause", "Previous", "Next", FocusActivity.deepWork.launchLabel, FocusActivity.lightWork.launchLabel])
        let activities = Set(["Deep Work", "Motivation", "Creativity", "Learning", "Light Work", "Relax", "Sleep", "Meditate"])
        while let element = pending.popLast() {
            guard Date() < deadline, count < 1800 else {
                recordScan(["nodes": count, "incomplete": 1]); return nil
            }
            let hash = CFHash(element)
            guard !(visited[hash]?.contains(where: { CFEqual($0, element) }) ?? false) else { continue }
            visited[hash, default: []].append(element)
            count += 1
            AXUIElementSetMessagingTimeout(element, 0.08)
            let role = string(element, kAXRoleAttribute)
            if role == kAXApplicationRole {
                if let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] { pending.append(contentsOf: windows) }
                continue
            }
            if role == kAXMenuBarRole { continue }
            if role == kAXButtonRole {
                let title = string(element, kAXTitleAttribute)
                let label = title.flatMap { wanted.contains($0) ? $0 : nil } ?? string(element, kAXDescriptionAttribute)
                if let label, wanted.contains(label) { result.targets[label, default: []].append(element) }
            } else if role == kAXStaticTextRole {
                let value = string(element, kAXValueAttribute) ?? string(element, kAXTitleAttribute)
                if let value {
                    if activities.contains(value) { activityLabels.insert(value) }
                    if value == "START" { result.targets[value, default: []].append(element) }
                    if value == "ACTIVITIES" { result.snapshot.activityPicker = true }
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { pending.append(contentsOf: children) }
        }
        result.snapshot.play = result.targets["Play"]?.count ?? 0
        result.snapshot.pause = result.targets["Pause"]?.count ?? 0
        result.snapshot.previous = result.targets["Previous"]?.count ?? 0
        result.snapshot.next = result.targets["Next"]?.count ?? 0
        result.snapshot.deepWork = result.targets[FocusActivity.deepWork.launchLabel]?.count ?? 0
        result.snapshot.lightWork = result.targets[FocusActivity.lightWork.launchLabel]?.count ?? 0
        result.snapshot.start = result.targets["START"]?.count ?? 0
        if activityLabels.count == 1 { result.snapshot.activity = activityLabels.first }
        recordScan(["nodes": count, "play": result.snapshot.play, "pause": result.snapshot.pause,
                    "deepWork": result.snapshot.deepWork, "lightWork": result.snapshot.lightWork,
                    "previous": result.snapshot.previous, "next": result.snapshot.next,
                    "activityDeepWork": result.snapshot.activity == "Deep Work" ? 1 : 0,
                    "activityLightWork": result.snapshot.activity == "Light Work" ? 1 : 0,
                    "start": result.snapshot.start, "activityPicker": result.snapshot.activityPicker ? 1 : 0])
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? {
        (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
