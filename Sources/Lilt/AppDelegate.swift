import AppKit
import WebKit
import ApplicationServices
import Quartz
import CoreFoundation
import ServiceManagement

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NotchPanel!
    var webView: NotchWebView!
    var statusItem: NSStatusItem!
    var pointerMonitor: Any?
    var localPointerMonitor: Any?
    var diagnosticTimer: Timer?
    var shelfTimer: Timer?
    var sharingPicker: NSSharingServicePicker?
    var screenObserver: NSObjectProtocol?
    var accessibilityObserver: NSObjectProtocol?
    var wakeObserver: NSObjectProtocol?
    var sleepObserver: NSObjectProtocol?
    var focus: FocusCoordinator!
    var shelf: ShelfStore!
    var music: MusicCoordinator!
    var settings: SettingsStore!
    var settingsWindow: SettingsWindowController?
    var settingsError: SettingsError?
    var shortcut: GlobalShortcut?
    var toggleItem: NSMenuItem?
    var shortcutConflict = false
    var simulatedLoginItem = false
    var focusSignals = 0
    let spotify = DirectMusicController(source: .spotify)
    let appleMusic = DirectMusicController(source: .appleMusic)
    let meld = MeldController()
    let simulatedMusic = SimulatedMeld()
    var previewURL: URL?
    let simulatedPlayer = SimulatedBrainFM()
    var geometry: NotchGeometry!
    var surfaceRect = CGRect.zero
    var surfaceRadius: CGFloat = 28
    var isOpen = false
    var ready = false
    var selectingFiles = false
    var lastDiagnosticID = ""
    var resourceDirectory: URL!
    let brainFM = BrainFMController()
    let smokeTest = CommandLine.arguments.contains("--smoke-test")
    var diagnosticDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--ui-test-dir"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
    }

    var dataDirectory: URL {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
        }
        if let directory = diagnosticDirectory { return directory.appendingPathComponent("data", isDirectory: true) }
        if smokeTest { return FileManager.default.temporaryDirectory.appendingPathComponent("lilt-smoke-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lilt", isDirectory: true)
    }

    var simulatedMeld: Bool { diagnosticDirectory != nil && CommandLine.arguments.contains("--simulate-meld") }

    var simulated: Bool { diagnosticDirectory != nil && CommandLine.arguments.contains("--simulate-brainfm") }

    func makeStores() {
        let settingsFile = dataDirectory.appendingPathComponent("settings.json")
        let hasSettings = FileManager.default.fileExists(atPath: settingsFile.path)
        settings = SettingsStore(file: settingsFile, focusFile: dataDirectory.appendingPathComponent("focus.json"))
        if !hasSettings, simulated || simulatedMeld {
            var initial = settings.value
            if simulatedMeld { initial.musicSource = .meld }
            if simulated { initial.brainFMEnabled = true }
            settings.save(initial)
        }
        let player: BrainFMControlling
        if simulated { player = simulatedPlayer }
        else if smokeTest || (diagnosticDirectory != nil && !CommandLine.arguments.contains("--live-brainfm")) { player = DisabledBrainFM() }
        else { player = brainFM }
        focus = FocusCoordinator(player: player, file: dataDirectory.appendingPathComponent("focus.json"), brainFMEnabled: settings.value.brainFMEnabled)
        if focus.canApplyDefaults,
           focus.session.activity != settings.value.focusActivity || focus.session.duration != settings.value.focusMinutes * 60 {
            focus.configure(activity: settings.value.focusActivity, minutes: settings.value.focusMinutes)
        }
        shelf = ShelfStore(file: dataDirectory.appendingPathComponent("shelf.json"))
        shelf.onChange = { [weak self] in self?.sendShelf() }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let previous = self.shelf.entries.map(\.id)
            self.shelf.pruneExpired()
            if previous != self.shelf.entries.map(\.id) { self.sendShelf() }
        }
        RunLoop.main.add(timer, forMode: .common)
        shelfTimer = timer
        focus.onChange = { [weak self] in
            guard let self, self.ready else { return }
            self.send("receiveFocusSnapshot", value: self.focus.snapshot)
            self.sendSettings()
        }
        focus.onComplete = { [weak self] in self?.playFocusSignal() }
        focus.startObserving()
        music = MusicCoordinator(player: self.player(for: settings.value.musicSource))
        music.onChange = { [weak self] in
            guard let self, self.ready else { return }
            self.sendMusic()
            self.sendSettings()
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
        applyShortcut()
        observeScreen()
        installWakeObservers()
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            guard let self else { return }
            self.updateMousePassthrough()
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if self.isOpen, !self.selectingFiles, !self.hitSurface(NSEvent.mouseLocation) { self.setOpen(false) }
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
            self?.updateMousePassthrough()
            if event.type == .scrollWheel, let self, self.isOpen, !self.selectingFiles, event.window === self.panel {
                self.webView.observeScrollWheel(event)
            }
            if event.type == .leftMouseDown {
                if event.window === self?.panel { self?.webView.recordMouseDown(event) }
                else if self?.isOpen == true, self?.selectingFiles == false { self?.setOpen(false) }
            }
            return event
        }
        updateMousePassthrough()
        if CommandLine.arguments.contains("--settings") { showSettings() }
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

    func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Lilt")
        let menu = NSMenu()
        let title = NSMenuItem(title: "Lilt", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        addItem("Öffnen / Falten", action: #selector(togglePanel), to: menu)
        toggleItem = menu.items.last
        menu.addItem(.separator())
        for (title, view) in [("Music", "music"), ("Focus", "focus"), ("Shelf", "shelf")] {
            let item = NSMenuItem(title: title, action: #selector(selectView(_:)), keyEquivalent: "")
            item.representedObject = view
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("Einstellungen…", action: #selector(showSettings), key: ",", to: menu)
        addItem("Musikplayer öffnen", action: #selector(openMusic), to: menu)
        addItem("Über Lilt", action: #selector(showAbout), to: menu)
        menu.addItem(.separator())
        addItem("Lilt beenden", action: #selector(quit), key: "q", to: menu)
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        addItem("Einstellungen…", action: #selector(showSettings), key: ",", to: applicationMenu)
        applicationMenu.addItem(.separator())
        addItem("Lilt beenden", action: #selector(quit), key: "q", to: applicationMenu)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select all", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func makePanel() {
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
        config.preferences.tabFocusesLinks = true
        webView = NotchWebView(frame: CGRect(origin: .zero, size: NotchGeometry.panelSize), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.registerForDraggedTypes([.fileURL])
        webView.onFiles = { [weak self] urls in self?.addFiles(urls) }
        webView.onTabSwipeProgress = { [weak self] phase, dx, dy, accepted, point in
            guard let self, self.ready, self.isOpen, !self.selectingFiles,
                  point.x.isFinite, point.y.isFinite, dx.isFinite, dy.isFinite else { return }
            self.webView.sendTabSwipeProgress(phase, dx: dx, dy: dy, accepted: accepted, point: point)
        }
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

    func displayID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func displayCandidates() -> [(NSScreen, DisplayCandidate)] {
        NSScreen.screens.enumerated().map { index, screen in
            (screen, DisplayCandidate(id: displayID(screen) ?? "unidentified-\(index)", name: screen.localizedName,
                                      hasNotch: screen.safeAreaInsets.top > 0, isMain: screen == NSScreen.screens.first))
        }
    }

    func currentGeometry() -> NotchGeometry {
        let candidates = displayCandidates()
        let selected = DisplaySelection.resolve(candidates.map { $0.1 }, preferredID: settings.value.displayID)
        let screen = candidates.first(where: { $0.1 == selected?.display })?.0 ?? NSScreen.main ?? NSScreen.screens[0]
        return NotchGeometry(screenFrame: screen.frame, safeTop: screen.safeAreaInsets.top,
                             leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }

    func observeScreen() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.geometry = self.currentGeometry()
            self.panel.setFrame(self.geometry.panelFrame, display: true)
            self.configureUI()
            self.sendSettings()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.configureUI()
        }
    }

    func installWakeObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.focus.recheck()
            self?.music.recheck()
            self?.sendShelf()
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.focus.checkpoint()
        }
    }

    func configureUI() {
        guard ready else { return }
        send("configure", value: ["hardwareWidth": geometry.hardwareWidth,
                                  "hardwareHeight": geometry.hardwareHeight,
                                  "hideHardwareWings": geometry.hideHardwareWings,
                                  "hideNotchContent": geometry.hideNotchContent,
                                  "reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion])
        settingsWindow?.send("configure", value: ["reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion])
    }

    func send(_ method: String, value: Any) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: encoded, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.Lilt?.\(method)(\(json))", completionHandler: nil)
    }

    func setOpen(_ value: Bool) {
        guard ready else { return }
        isOpen = value
        send("setOpen", value: value)
        if value { panel.orderFrontRegardless() }
        else { panel.resignKey() }
    }

    @objc func togglePanel() { setOpen(!isOpen) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard ready, isOpen, !selectingFiles, !smokeTest, diagnosticDirectory == nil else { return }
        setOpen(false)
    }

    @objc func selectView(_ item: NSMenuItem) {
        guard let view = item.representedObject as? String else { return }
        send("setView", value: view)
        setOpen(true)
    }

    func player(for source: MusicSource) -> MeldControlling {
        if source == .meld, simulatedMeld { return simulatedMusic }
        let liveFlag = source == .meld ? "--live-meld" : "--live-music"
        if smokeTest || (diagnosticDirectory != nil && !CommandLine.arguments.contains(liveFlag)) { return DisabledMeld() }
        switch source {
        case .spotify: return spotify
        case .appleMusic: return appleMusic
        case .meld: return meld
        }
    }

    var directPlayer: DirectMusicController? {
        switch settings.value.musicSource {
        case .spotify: return spotify
        case .appleMusic: return appleMusic
        case .meld: return nil
        }
    }

    func sendMusic() {
        guard ready, music != nil else { return }
        var snapshot = music.snapshot
        snapshot["source"] = settings.value.musicSource.rawValue
        snapshot["sourceName"] = settings.value.musicSource.title
        send("receiveMusicSnapshot", value: snapshot)
    }

    var settingsSnapshot: [String: Any] {
        var snapshot = settings.value.payload
        let candidates = displayCandidates().map { $0.1 }
        snapshot["displays"] = candidates.filter { UUID(uuidString: $0.id) != nil }.map { ["id": $0.id, "name": $0.name] }
        snapshot["displayUnavailable"] = DisplaySelection.resolve(candidates, preferredID: settings.value.displayID)?.preferredUnavailable ?? false
        snapshot["brainFMEnabled"] = focus.brainFMEnabled
        snapshot["musicBusy"] = music?.pending != nil
        snapshot["focusLocked"] = focus.integrationLocked
        snapshot["brainFM"] = ["installed": brainFM.applicationURL != nil, "permission": brainFM.hasPermission]
        snapshot["error"] = (settingsError ?? settings.error).map(\.payload) as Any? ?? NSNull()
        snapshot["saved"] = settingsError == nil && settings.error == nil
        snapshot["openAtLogin"] = openAtLogin
        snapshot["shortcutLabel"] = GlobalShortcut.label
        snapshot["shortcutConflict"] = shortcutConflict
        snapshot["providers"] = MusicSource.allCases.map { source -> [String: Any] in
            let controller: DirectMusicController? = source == .spotify ? spotify : source == .appleMusic ? appleMusic : nil
            let selected = source == settings.value.musicSource
            let fixture = source == .meld && simulatedMeld
            let installed = fixture || (source == .meld ? meld.applicationURL != nil : controller?.applicationURL != nil)
            let running = fixture ? music?.reading.availability == .ready || music?.reading.availability == .empty : controller?.isRunning ?? !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
            let status = controller?.permissionStatus
            let needsPermission = selected && ["permission", "permissionRequired"].contains(music?.error?.code ?? "")
            let message: String
            if !installed { message = "Install \(source.title) to use it with Lilt." }
            else if !running { message = "Open \(source.title) to connect." }
            else if status == -1743 { message = "Allow Lilt in System Settings → Privacy & Security → Automation." }
            else if status == -1744 { message = "Allow Lilt to connect to \(source.title)." }
            else { message = selected ? music?.error?.message ?? "" : "Select \(source.title) to connect." }
            return ["id": source.rawValue, "name": source.title, "installed": installed, "running": running,
                    "availability": needsPermission ? "permission" : selected ? music?.reading.availability.rawValue ?? "checking" : installed ? "offline" : "unavailable",
                    "permission": status == 0, "message": message]
        }
        return snapshot
    }

    func sendSettings() {
        guard settings != nil, focus != nil else { return }
        if ready { send("receiveSettingsSnapshot", value: settingsSnapshot) }
        settingsWindow?.send("receiveSnapshot", value: settingsSnapshot)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let resources = Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true)
            let controller = SettingsWindowController(resources: resources)
            controller.onReady = { [weak self] in
                guard let self else { return }
                self.settingsWindow?.send("configure", value: ["reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion])
                self.sendSettings()
            }
            controller.onAction = { [weak self] body in self?.handleSettingsAction(body) }
            settingsWindow = controller
        }
        if isOpen { setOpen(false) }
        settingsWindow?.present()
    }

    func updateSettings(_ changes: [String: Any]) {
        if changes.keys.contains("openAtLogin") {
            guard changes.count == 1, let number = changes["openAtLogin"] as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { settingsError = .invalid; sendSettings(); return }
            setOpenAtLogin(number.boolValue)
            return
        }
        do {
            let value = try settings.value.applying(changes)
            if value.displayID != settings.value.displayID, !value.displayID.isEmpty,
               !displayCandidates().contains(where: { $0.1.id == value.displayID }) { throw SettingsError.invalid }
            let displayChanged = value.displayID != settings.value.displayID
            let sourceChanged = value.musicSource != settings.value.musicSource
            let focusChanged = value.brainFMEnabled != focus.brainFMEnabled || value.focusMinutes != settings.value.focusMinutes || value.focusActivity != settings.value.focusActivity
            if sourceChanged, music.pending != nil { throw SettingsError.musicBusy }
            if focusChanged, focus.integrationLocked { throw SettingsError.focusBusy }
            guard settings.save(value) else { settingsError = settings.error; sendSettings(); return }
            settingsError = nil
            if displayChanged {
                geometry = currentGeometry()
                panel.setFrame(geometry.panelFrame, display: true)
                configureUI()
            }
            if sourceChanged { _ = music.select(player: player(for: value.musicSource)) }
            applyShortcut()
            if focusChanged {
                _ = focus.setBrainFMEnabled(value.brainFMEnabled)
                focus.configure(activity: value.focusActivity, minutes: value.focusMinutes)
            }
            sendMusic()
            sendSettings()
        } catch let error as SettingsError { settingsError = error; sendSettings() }
        catch { settingsError = .invalid; sendSettings() }
    }

    func connectMusic() {
        guard !smokeTest, diagnosticDirectory == nil || CommandLine.arguments.contains("--live-music") else {
            music.recheck(); sendSettings(); return
        }
        guard let controller = directPlayer else { music.recheck(); return }
        controller.connect { [weak self] result in
            guard let self, controller === self.directPlayer else { return }
            if case .failure(let error) = result { self.music.report(error) }
            else { self.music.recheck() }
            self.sendSettings()
        }
    }

    @objc func openMusic() {
        if settings.value.musicSource == .meld { openMeld(); return }
        guard !smokeTest, diagnosticDirectory == nil || CommandLine.arguments.contains("--live-music"),
              let controller = directPlayer else { return }
        guard let url = controller.applicationURL else {
            music.report(.init(code: "notInstalled", message: "Install \(settings.value.musicSource.title) to connect it to Lilt.")); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, controller === self.directPlayer else { return }
                if error != nil { self.music.report(.init(code: "openFailed", message: "The selected music player could not be opened. Open it from Applications and try again.")) }
                else { self.music.recheck() }
                self.sendSettings()
            }
        }
    }

    @objc func openMeld() {
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

    @objc func openBrainFM() {
        guard settings.value.brainFMEnabled, !smokeTest, diagnosticDirectory == nil else { return }
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

    @objc func openAccessibilitySettings() {
        guard settings.value.brainFMEnabled, !smokeTest, diagnosticDirectory == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Lilt"
        alert.informativeText = "Lokale Mac-App nach dem Lilt-Konzept von Vayun Godara.\n\nMusic verbindet Spotify, Apple Music oder die lokale Meld-App. Focus funktioniert unabhängig, mit optionaler Brain.fm-Verbindung. Shelf speichert lokale Dateiverweise.\n\nReferenz: vayun.net/studies/lilt/"
        alert.addButton(withTitle: "Schließen")
        alert.runModal()
    }

    @objc func quit() { NSApp.terminate(nil) }

    func hitSurface(_ point: NSPoint) -> Bool {
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

    func updateMousePassthrough() {
        guard panel != nil else { return }
        let ignore = !hitSurface(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    /// Diagnostic and smoke runs never register system-wide keys or login items, so a running user instance keeps them.
    var isolatedRun: Bool { smokeTest || diagnosticDirectory != nil }

    func applyShortcut() {
        if shortcut == nil, !isolatedRun { shortcut = GlobalShortcut { [weak self] in self?.toggleFromShortcut() } }
        shortcutConflict = !(shortcut?.setEnabled(settings.value.shortcutEnabled) ?? true)
        toggleItem?.keyEquivalent = settings.value.shortcutEnabled && !shortcutConflict ? "l" : ""
        toggleItem?.keyEquivalentModifierMask = [.control, .option]
    }

    func toggleFromShortcut() {
        setOpen(!isOpen)
        if isOpen { panel.makeKey() }
    }

    var openAtLogin: Bool { isolatedRun ? simulatedLoginItem : SMAppService.mainApp.status == .enabled }

    func setOpenAtLogin(_ enabled: Bool) {
        if isolatedRun { simulatedLoginItem = enabled; settingsError = nil; sendSettings(); return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settingsError = nil
        } catch {
            settingsError = SMAppService.mainApp.status == .requiresApproval ? .loginApproval : .loginItem
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
        sendSettings()
    }

    func playFocusSignal() {
        guard settings.value.focusSound else { return }
        focusSignals += 1
        if !isolatedRun { NSSound(named: "Glass")?.play() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        diagnosticTimer?.invalidate()
        shelfTimer?.invalidate()
        focus?.stop()
        music?.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }
}
