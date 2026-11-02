import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model = SettingsModel()
    let hostView: SettingsHostView
    var onAction: (([String: Any]) -> Void)?
    var onReady: (() -> Void)?
    private(set) var ready = false
    private var shortcutMonitor: Any?

    init() {
        hostView = SettingsHostView(model: model)
        hostView.frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        hostView.sizingOptions = []
        let window = NSWindow(contentRect: hostView.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Lilt Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 700, height: 540)
        window.isReleasedWhenClosed = false
        window.contentView = hostView
        window.center()
        super.init(window: window)
        window.delegate = self
        model.post = { [weak self] body in self?.receive(body) }
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(hostView)
        if ready { onReady?() }
    }

    func beginShortcutRecording() {
        endShortcutRecording()
        send("receiveShortcutRecording", value: ["recording": true])
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.recordShortcutKey(event) ? nil : event
        }
    }

    func recordShortcutKey(_ event: NSEvent) -> Bool {
        guard shortcutMonitor != nil else { return false }
        if event.keyCode == 53 || event.keyCode == 48 {
            endShortcutRecording()
            return event.keyCode != 48
        }
        let shortcut = KeyboardShortcut(event: event)
        guard shortcut.isValid else {
            send("receiveShortcutRecording", value: ["recording": true, "error": SettingsError.invalidShortcut.message])
            return true
        }
        endShortcutRecording()
        onAction?(["action": "settingsUpdate", "changes": ["shortcut": ["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers]]])
        return true
    }

    func endShortcutRecording() {
        guard let shortcutMonitor else { return }
        NSEvent.removeMonitor(shortcutMonitor)
        self.shortcutMonitor = nil
        send("receiveShortcutRecording", value: ["recording": false])
        onAction?(["action": "shortcutRecordingEnded"])
    }

    func windowWillClose(_ notification: Notification) { endShortcutRecording() }
    func windowDidResignKey(_ notification: Notification) { endShortcutRecording() }

    /// Values cross the same JSON boundary as the former web bridge, so the model parses exactly what it would have carried.
    func send(_ method: String, value: Any) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return }
        model.receive(method, decoded)
    }

    private func receive(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        if action == "settingsReady" { ready = true; onReady?() }
        else if action == "settingsClose" { close() }
        else { onAction?(body) }
    }
}

/// AppKit host for the SwiftUI settings: outside clicks dismiss an open menu, and keys reach the menu and Escape.
final class SettingsHostView: NSHostingView<SettingsRootView> {
    let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(rootView: SettingsRootView(model: model))
    }

    @MainActor required init(rootView: SettingsRootView) { fatalError("Use init(model:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if model.openMenu != nil, !model.menuContains(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)) {
            model.closeMenu()
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let keys: [UInt16: String] = [125: "down", 126: "up", 115: "home", 119: "end", 36: "return", 76: "return", 49: "return", 53: "escape", 48: "tab"]
        if let key = keys[event.keyCode], model.menuKey(key) { return }
        if event.keyCode == 53 { model.escape(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { model.escape() }
}
