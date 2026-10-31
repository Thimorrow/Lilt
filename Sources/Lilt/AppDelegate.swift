import AppKit
import WebKit
import ApplicationServices
import Quartz

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var panel: NotchPanel!
    private var webView: NotchWebView!
    private var statusItem: NSStatusItem!
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var diagnosticTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var focus: FocusCoordinator!
    private var shelf: ShelfStore!
    private var music: MusicCoordinator!
    private let meld = MeldController()
    private let simulatedMusic = SimulatedMeld()
    private var previewURL: URL?
    private let simulatedPlayer = SimulatedBrainFM()
    private var geometry: NotchGeometry!
    private var surfaceRect = CGRect.zero
    private var surfaceRadius: CGFloat = 28
    private var isOpen = false
    private var ready = false
    private var selectingFiles = false
    private var lastDiagnosticID = ""
    private var resourceDirectory: URL!
    private let brainFM = BrainFMController()
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private var diagnosticDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--ui-test-dir"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
    }

    private var dataDirectory: URL {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
        }
        if let directory = diagnosticDirectory { return directory.appendingPathComponent("data", isDirectory: true) }
        if smokeTest { return FileManager.default.temporaryDirectory.appendingPathComponent("lilt-smoke-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lilt", isDirectory: true)
    }

    private var simulatedMeld: Bool { diagnosticDirectory != nil && CommandLine.arguments.contains("--simulate-meld") }

    private var simulated: Bool { diagnosticDirectory != nil && CommandLine.arguments.contains("--simulate-brainfm") }

    private func makeStores() {
        let player: BrainFMControlling
        if simulated { player = simulatedPlayer }
        else if smokeTest || (diagnosticDirectory != nil && !CommandLine.arguments.contains("--live-brainfm")) { player = DisabledBrainFM() }
        else { player = brainFM }
        focus = FocusCoordinator(player: player, file: dataDirectory.appendingPathComponent("focus.json"))
        shelf = ShelfStore(file: dataDirectory.appendingPathComponent("shelf.json"))
        focus.onChange = { [weak self] in
            guard let self, self.ready else { return }
            self.send("receiveFocusSnapshot", value: self.focus.snapshot)
        }
        focus.startObserving()
        let musicPlayer: MeldControlling
        if simulatedMeld { musicPlayer = simulatedMusic }
        else if smokeTest || (diagnosticDirectory != nil && !CommandLine.arguments.contains("--live-meld")) { musicPlayer = DisabledMeld() }
        else { musicPlayer = meld }
        music = MusicCoordinator(player: musicPlayer)
        music.onChange = { [weak self] in
            guard let self, self.ready else { return }
            self.send("receiveMusicSnapshot", value: self.music.snapshot)
        }
        music.startObserving()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        makeStores()
        makeMenu()
        makePanel()
        observeScreen()
        installWakeObservers()
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.updateMousePassthrough()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.updateMousePassthrough()
            if event.type == .leftMouseDown, event.window === self?.panel { self?.webView.recordMouseDown(event) }
            return event
        }
        updateMousePassthrough()
        if let directory = diagnosticDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
               let previous = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let id = previous["id"] as? String { lastDiagnosticID = id }
            diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.runDiagnosticCommand(directory: directory)
            }
        }
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Lilt")
        let menu = NSMenu()
        let title = NSMenuItem(title: "Lilt", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        addItem("Öffnen / Falten", action: #selector(togglePanel), to: menu)
        menu.addItem(.separator())
        for (title, view) in [("Music", "music"), ("Focus", "focus"), ("Shelf", "shelf")] {
            let item = NSMenuItem(title: title, action: #selector(selectView(_:)), keyEquivalent: "")
            item.representedObject = view
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("Meld öffnen", action: #selector(openMeld), to: menu)
        addItem("Brain.fm öffnen", action: #selector(openBrainFM), to: menu)
        addItem("Brain.fm-Steuerung erlauben…", action: #selector(openAccessibilitySettings), to: menu)
        addItem("Über Lilt", action: #selector(showAbout), to: menu)
        menu.addItem(.separator())
        addItem("Lilt beenden", action: #selector(quit), key: "q", to: menu)
        statusItem.menu = menu
    }

    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func makePanel() {
        geometry = currentGeometry()
        surfaceRect = geometry.surfaceRect(open: false)
        panel = NotchPanel(contentRect: geometry.panelFrame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.title = "Lilt"
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let controller = WKUserContentController()
        controller.add(self, name: "lilt")
        controller.addUserScript(WKUserScript(source: """
            (() => {
              const notch = document.getElementById('notch');
              if (!notch) return;
              const report = () => {
                const r = notch.getBoundingClientRect();
                window.webkit.messageHandlers.lilt.postMessage({action:'hitRect',x:r.x,y:r.y,width:r.width,height:r.height,radius:parseFloat(getComputedStyle(notch).borderBottomLeftRadius)||0});
              };
              new ResizeObserver(report).observe(notch);
              report();
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        resourceDirectory = Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalResources(directory: resourceDirectory), forURLScheme: "lilt-ui")
        config.userContentController = controller
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = NotchWebView(frame: CGRect(origin: .zero, size: NotchGeometry.panelSize), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.registerForDraggedTypes([.fileURL])
        webView.onFiles = { [weak self] urls in self?.addFiles(urls) }
        webView.onFileDragEntered = { [weak self] in
            self?.send("setDragging", value: true)
            self?.send("setView", value: "shelf")
            self?.setOpen(true)
        }
        webView.onFileDragExited = { [weak self] in self?.send("setDragging", value: false) }
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
        panel.contentView = webView

        resourceDirectory = Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)
        let index = resourceDirectory.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else {
            let alert = NSAlert()
            alert.messageText = "Lilt konnte seine Oberfläche nicht laden."
            alert.informativeText = "Bitte die mit scripts/build-app.sh erstellte Lilt.app starten."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        webView.load(URLRequest(url: URL(string: "lilt-ui://app/index.html")!))
    }

    private func currentGeometry() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        return NotchGeometry(screenFrame: screen.frame, safeTop: screen.safeAreaInsets.top,
                             leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }

    private func observeScreen() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.geometry = self.currentGeometry()
            self.panel.setFrame(self.geometry.panelFrame, display: true)
            self.configureUI()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.configureUI()
        }
    }

    private func installWakeObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.focus.recheck()
            self?.music.recheck()
            self?.sendShelf()
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.focus.checkpoint()
        }
    }

    private func configureUI() {
        guard ready else { return }
        send("configure", value: ["hardwareWidth": geometry.hardwareWidth,
                                  "hardwareHeight": geometry.hardwareHeight,
                                  "reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion])
    }

    private func send(_ method: String, value: Any) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: encoded, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.Lilt?.\(method)(\(json))", completionHandler: nil)
    }

    private func setOpen(_ value: Bool) {
        guard ready else { return }
        isOpen = value
        send("setOpen", value: value)
        if value { panel.orderFrontRegardless() }
        else { panel.resignKey() }
    }

    @objc private func togglePanel() { setOpen(!isOpen) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setOpen(true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard ready, isOpen, !selectingFiles, !smokeTest, diagnosticDirectory == nil else { return }
        setOpen(false)
    }

    @objc private func selectView(_ item: NSMenuItem) {
        guard let view = item.representedObject as? String else { return }
        send("setView", value: view)
        setOpen(true)
    }

    @objc private func openMeld() {
        guard !smokeTest, diagnosticDirectory == nil || CommandLine.arguments.contains("--live-meld") else { return }
        guard let url = meld.applicationURL else { music.report(.offline); return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                if error != nil { self?.music.report(.unavailable) }
                else {
                    self?.meld.openPlayer { result in
                        if case .failure(let error) = result, error != .offline { self?.music.report(error) }
                        self?.music.recheck()
                    }
                }
            }
        }
    }

    @objc private func openBrainFM() {
        guard !smokeTest, diagnosticDirectory == nil else { return }
        guard let url = brainFM.applicationURL else {
            let alert = NSAlert()
            alert.messageText = "Die Brain.fm-App wurde nicht gefunden."
            alert.informativeText = "Installiere Brain.fm, um Fokus-Musik mit Lilt zu steuern."
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Brain.fm konnte nicht geöffnet werden."
                alert.informativeText = "Versuche die installierte Brain.fm-App direkt zu öffnen."
                alert.runModal()
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        guard !smokeTest, diagnosticDirectory == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func receiveFocusAction(_ body: [String: Any]) {
        guard let raw = body["command"] as? String, let action = FocusCoordinator.Action(rawValue: raw) else { return }
        focus.request(action)
    }

    private func receiveFocusConfiguration(_ body: [String: Any]) {
        guard let raw = body["activity"] as? String, let activity = FocusActivity(rawValue: raw),
              let minutes = body["minutes"] as? Int, (1...180).contains(minutes) else { return }
        focus.configure(activity: activity, minutes: minutes)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Lilt"
        alert.informativeText = "Lokaler Nachbau des Lilt-Konzepts von Vayun Godara.\n\nMusic zeigt und steuert Meld in der lokalen Android-Umgebung. Focus steuert Deep Work oder Light Work in der installierten Brain.fm-App. Shelf speichert lokale Dateiverweise, ohne Originale zu verschieben oder hochzuladen.\n\nReferenz: vayun.net/studies/lilt/"
        alert.addButton(withTitle: "Schließen")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func chooseFiles() {
        selectingFiles = true
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel()
        chooser.title = "Dateien zur Ablage hinzufügen"
        chooser.message = "Originale bleiben an ihrem Ort. Lilt merkt sich lokale Dateiverweise."
        chooser.allowsMultipleSelection = true
        chooser.canChooseDirectories = false
        chooser.canChooseFiles = true
        chooser.begin { [weak self] result in
            guard let self else { return }
            self.selectingFiles = false
            if result == .OK { self.addFiles(chooser.urls) }
            self.setOpen(true)
        }
    }

    private func addFiles(_ urls: [URL]) {
        shelf.add(urls)
        sendShelf()
        send("setView", value: "shelf")
        setOpen(true)
    }

    private func sendShelf() { if ready { send("receiveShelfSnapshot", value: shelf.snapshot) } }

    private func shelfAction(_ body: [String: Any]) {
        guard let action = body["command"] as? String else { return }
        if action == "clear" { shelf.clear(); sendShelf(); return }
        if action == "refresh" { sendShelf(); return }
        guard let id = body["id"] as? String, shelf.entries.contains(where: { $0.id == id }) else { return }
        if action == "remove" { shelf.remove(id); sendShelf(); return }
        if action == "menu" { showShelfMenu(id: id, body: body); return }
        guard let url = shelf.resolvedURL(for: id) else {
            shelf.report("Die Datei ist nicht mehr verfügbar. Du kannst ihren Eintrag entfernen und die Datei erneut hinzufügen.")
            sendShelf(); return
        }
        switch action {
        case "open":
            if !NSWorkspace.shared.open(url) { shelf.report("Die Datei konnte nicht geöffnet werden.") }
        case "reveal": NSWorkspace.shared.activateFileViewerSelecting([url])
        case "preview":
            previewURL = url
            if let preview = QLPreviewPanel.shared() {
                preview.dataSource = self
                preview.delegate = self
                preview.reloadData()
                preview.makeKeyAndOrderFront(nil)
            }
        case "drag":
            let rect = CGRect(x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0,
                              width: body["width"] as? Double ?? 40, height: body["height"] as? Double ?? 40)
            if !webView.dragFile(url, at: rect) { shelf.report("Ziehe die Datei erneut mit gedrückter Maustaste aus der Ablage.") }
        default: return
        }
        sendShelf()
    }

    private func showShelfMenu(id: String, body: [String: Any]) {
        let menu = NSMenu()
        let available = shelf.resolvedURL(for: id) != nil
        for (title, command) in [("Quick Look", "preview"), ("Open", "open"), ("Show in Finder", "reveal"), ("Remove from Shelf", "remove")] {
            let item = NSMenuItem(title: title, action: #selector(shelfMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["id": id, "command": command]
            item.isEnabled = available || command == "remove"
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        let x = body["x"] as? Double ?? 250
        let y = body["y"] as? Double ?? 100
        selectingFiles = true
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y), in: webView)
        selectingFiles = false
    }

    @objc private func shelfMenuAction(_ item: NSMenuItem) {
        guard let command = item.representedObject as? [String: Any] else { return }
        shelfAction(command)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }

    private func diagnosticMusicFixture(_ body: [String: Any]) {
        guard simulatedMeld else { return }
        if let raw = body["availability"] as? String, let availability = MeldReading.Availability(rawValue: raw) { simulatedMusic.reading.availability = availability }
        if let playing = body["playing"] as? Bool { simulatedMusic.reading.playing = playing }
        if let buffering = body["buffering"] as? Bool { simulatedMusic.reading.buffering = buffering }
        if let title = body["title"] as? String { simulatedMusic.reading.title = title }
        if let id = body["id"] as? String { simulatedMusic.reading.id = id }
        if let code = body["error"] as? String { simulatedMusic.failure = .init(code: code, message: body["message"] as? String ?? "Simulated Meld failure.") }
        if body["clearError"] as? Bool == true { simulatedMusic.failure = nil }
        music.recheck()
    }

    private func diagnosticFixture(_ body: [String: Any]) {
        guard simulated else { return }
        if let raw = body["activity"] as? String, let activity = FocusActivity(rawValue: raw) { simulatedPlayer.activity = activity }
        if let raw = body["playback"] as? String, let playback = BrainFMController.PlaybackState(rawValue: raw) { simulatedPlayer.playback = playback }
        if let code = body["error"] as? String {
            simulatedPlayer.failure = .init(code: code, message: body["message"] as? String ?? "Simulated Brain.fm error.")
        }
        if body["clearError"] as? Bool == true { simulatedPlayer.failure = nil }
        if let seconds = body["remaining"] as? Int { focus.setDiagnosticRemaining(seconds) }
        if body["poll"] as? Bool == true { focus.recheck() }
    }

    private func hitSurface(_ point: NSPoint) -> Bool {
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        guard surfaceRect.contains(local) else { return false }
        let radius = min(surfaceRadius, surfaceRect.height / 2)
        let bottomY = surfaceRect.maxY - radius
        if local.y > bottomY {
            if local.x < surfaceRect.minX + radius {
                return hypot(local.x - surfaceRect.minX - radius, local.y - bottomY) <= radius
            }
            if local.x > surfaceRect.maxX - radius {
                return hypot(local.x - surfaceRect.maxX + radius, local.y - bottomY) <= radius
            }
        }
        return true
    }

    private func updateMousePassthrough() {
        guard panel != nil else { return }
        let ignore = !hitSurface(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            ready = true
            configureUI()
            send("receiveFocusSnapshot", value: focus.snapshot)
            sendShelf()
            send("receiveMusicSnapshot", value: music.snapshot)
            panel.orderFrontRegardless()
            if smokeTest { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.runSmokeTest() } }
        case "openChanged":
            if let open = body["open"] as? Bool {
                isOpen = open
                if !open { panel.resignKey() }
            }
        case "hitRect":
            if let x = body["x"] as? Double, let y = body["y"] as? Double,
               let width = body["width"] as? Double, let height = body["height"] as? Double,
               width.isFinite, height.isFinite, width > 0, height > 0 {
                surfaceRect = CGRect(x: x, y: y, width: width, height: height)
                surfaceRadius = body["radius"] as? Double ?? 28
                updateMousePassthrough()
            }
        case "chooseFiles": chooseFiles()
        case "brainfm": openBrainFM()
        case "brainfmSettings": openAccessibilitySettings()
        case "musicAction":
            if let raw = body["command"] as? String, let command = MeldCommand(rawValue: raw) { music.request(command) }
        case "meldOpen": openMeld()
        case "testMusic": diagnosticMusicFixture(body)
        case "focusAction": receiveFocusAction(body)
        case "focusConfigure": receiveFocusConfiguration(body)
        case "shelfAction": shelfAction(body)
        case "testFocus": diagnosticFixture(body)
        case "quit": quit()
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme == "lilt-ui", url.host == "app" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        diagnosticTimer?.invalidate()
        focus?.stop()
        music?.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }

    private func runDiagnosticCommand(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = command["id"] as? String, id != lastDiagnosticID,
              let script = command["script"] as? String else { return }
        lastDiagnosticID = id
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            var response: [String: Any] = ["id": id, "panelFrame": NSStringFromRect(self.panel.frame), "surfaceRect": NSStringFromRect(self.surfaceRect), "ignoresMouseEvents": self.panel.ignoresMouseEvents,
                "brainfmPermission": self.brainFM.hasPermission,
                "brainfmScan": self.brainFM.lastScanSummary,
                "dataDirectory": self.dataDirectory.path, "simulatedBrainFM": self.simulated, "simulatedMeld": self.simulatedMeld,
                "nativeChecks": [
                    ["name": "panel touches physical screen top", "pass": abs(self.panel.frame.maxY - self.geometry.screenFrame.maxY) < 0.1],
                    ["name": "panel covers menu bar icons", "pass": self.panel.level.rawValue > NSWindow.Level.statusBar.rawValue]
                ]]
            switch result {
            case .success(let value): response["result"] = value
            case .failure(let error): response["error"] = error.localizedDescription
            }
            func finish(_ response: [String: Any]) {
                if let data = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
                    try? data.write(to: directory.appendingPathComponent("response.json"), options: .atomic)
                }
            }
            if command["snapshot"] as? Bool == true {
                self.snapshot(to: directory.appendingPathComponent("capture.png")) { error in
                    response["snapshotSuccess"] = error == nil
                    if let error { response["snapshotError"] = error.localizedDescription }
                    finish(response)
                }
            } else { finish(response) }
        }
    }

    private func snapshot(to url: URL, completion: ((Error?) -> Void)? = nil) {
        webView.takeSnapshot(with: nil) { image, error in
            if let error { completion?(error); return }
            guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                completion?(NSError(domain: "LiltSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebKit returned no usable image."]))
                return
            }
            do { try data.write(to: url, options: .atomic); completion?(nil) }
            catch { completion?(error) }
        }
    }

    private func runSmokeTest() {
        let script = """
        const wait = ms => new Promise(r => setTimeout(r,ms));
        const checks = [];
        const check = (name, pass) => checks.push({name,pass:!!pass});
        check('bridge loaded',!!window.Lilt);
        check('font ready',document.fonts.check('18px "Familjen Grotesk"'));
        Lilt.setOpen(false); await wait(650);
        check('fold',!Lilt.inspect().open);
        Lilt.setOpen(true); await wait(650);
        check('open',Lilt.inspect().open);
        for(const view of ['focus','shelf','music']){Lilt.setView(view);await wait(350);check('view '+view,Lilt.inspect().view===view);}
        Lilt.setOpen(false);await wait(90);Lilt.setOpen(true);await wait(650);
        check('interrupted fold',Lilt.inspect().open);
        check('no page errors',Lilt.inspect().errors.length===0);
        return {checks,state:Lilt.inspect(),rect:document.querySelector('#notch').getBoundingClientRect().toJSON(),transition:getComputedStyle(document.querySelector('#notch')).transition};
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            let payload: Any
            switch result {
            case .success(let value): payload = value
            case .failure(let error): payload = ["error": error.localizedDescription]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/lilt-native-smoke.json"), options: .atomic)
            }
            self.snapshot(to: URL(fileURLWithPath: "/tmp/lilt-native-smoke.png")) { _ in NSApp.terminate(nil) }
        }
    }
}
