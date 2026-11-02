import AppKit

// Fixtures, diagnostic commands and the smoke test. Only active with --ui-test-dir or --smoke-test.
extension AppDelegate {
    func diagnosticMusicFixture(_ body: [String: Any]) {
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

    func diagnosticFixture(_ body: [String: Any]) {
        if diagnosticDirectory != nil, !focus.brainFMEnabled {
            if let seconds = body["remaining"] as? Int { focus.setDiagnosticRemaining(seconds) }
            return
        }
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

    func diagnosticPointer(_ body: [String: Any]) {
        guard diagnosticDirectory != nil,
              let x = body["x"] as? Double, let y = body["y"] as? Double,
              x.isFinite, y.isFinite, x >= 0, x < notchView.bounds.width, y >= 0, y < notchView.bounds.height,
              let phase = body["phase"] as? String, ["down", "up"].contains(phase) else { return }
        let type: NSEvent.EventType = phase == "down" ? .leftMouseDown : .leftMouseUp
        let point = NSPoint(x: x, y: panel.contentView!.bounds.height - y)
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: phase == "down" ? 1 : 0) else { return }
        panel.sendEvent(event)
    }

    func runDiagnosticCommand(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = command["id"] as? String, id != lastDiagnosticID else { return }
        let settingsTarget = command["target"] as? String == "settings"
        guard let steps = command["steps"] as? [[String: Any]] else { return }
        if settingsTarget, settingsWindow?.window?.isVisible != true { showSettings() }
        guard settingsTarget ? settingsWindow?.ready == true : ready else { return }
        lastDiagnosticID = id
        if settingsTarget, let size = command["settingsSize"] as? [String: Double],
           let width = size["width"], let height = size["height"],
           width.isFinite, height.isFinite, (700...1600).contains(width), (540...1200).contains(height) {
            settingsWindow?.window?.setContentSize(NSSize(width: width, height: height))
        }
        runDiagnosticSteps(steps[...], directory: directory, settings: settingsTarget) { [weak self] in
            guard let self else { return }
            var response = self.diagnosticResponse(id: id)
            response["result"] = settingsTarget ? self.settingsWindow?.model.inspect() as Any? ?? NSNull() : self.notchModel.inspect()
            if command["snapshot"] as? Bool == true {
                let url = directory.appendingPathComponent("capture.png")
                let saved = settingsTarget ? self.snapshotSettings(to: url) : self.snapshotNotch(to: url)
                response["snapshotSuccess"] = saved
                if !saved { response["snapshotError"] = "The view returned no usable image." }
            }
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
                try? data.write(to: directory.appendingPathComponent("response.json"), options: .atomic)
            }
        }
    }

    /// Native replacement for injected diagnostic scripts. Each step is a JSON object; `wait` is in milliseconds.
    /// With `settings`, calls, messages, intents and captures address the settings window instead of the notch.
    func runDiagnosticSteps(_ steps: ArraySlice<[String: Any]>, directory: URL, settings: Bool = false, completion: @escaping () -> Void) {
        guard let step = steps.first else { completion(); return }
        let rest = steps.dropFirst()
        var delay = 0.0
        if let method = step["call"] as? String {
            if settings { settingsWindow?.send(method, value: step["value"] ?? NSNull()) } else { send(method, value: step["value"] ?? NSNull()) }
        }
        if let message = step["message"] as? [String: Any] {
            if settings { handleSettingsAction(message) } else { handleNotchMessage(message) }
        }
        if let intent = step["intent"] as? String {
            if settings { settingsIntent(intent, step) } else { diagnosticIntent(intent, step) }
        }
        if let pointer = step["pointer"] as? [String: Any] { diagnosticPointer(pointer) }
        if let swipe = step["swipe"] as? [String: Any], let phase = swipe["phase"] as? String {
            let number = { (key: String) in CGFloat((swipe[key] as? NSNumber)?.doubleValue ?? 0) }
            notchModel.swipeGesture(phase: phase, dx: number("dx"), dy: number("dy"), accepted: (swipe["accepted"] as? Int) ?? 0,
                                    point: CGPoint(x: number("x"), y: number("y")),
                                    time: (swipe["time"] as? NSNumber)?.doubleValue ?? ProcessInfo.processInfo.systemUptime)
        }
        if let name = step["capture"] as? String, name.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            let url = directory.appendingPathComponent("\(name).png")
            _ = settings ? snapshotSettings(to: url) : snapshotNotch(to: url)
        }
        if let wait = (step["wait"] as? NSNumber)?.doubleValue, wait.isFinite { delay = max(0, min(wait, 10_000)) / 1000 }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runDiagnosticSteps(rest, directory: directory, settings: settings, completion: completion)
        }
    }

    private func diagnosticIntent(_ intent: String, _ step: [String: Any]) {
        let model = notchModel
        switch intent {
        case "userOpen": model.userOpen()
        case "escape": model.escape()
        case "outsideClick": dismissMenusOrClose()
        case "togglePlayback": model.togglePlayback()
        case "focusPrimary": model.focusPrimary()
        case "focusMenu": if let kind = step["value"] as? String { model.toggleFocusMenu(kind == "activity" ? .activity : .duration) }
        case "focusMinutes": if let minutes = step["value"] as? Int { model.configureFocus(minutes: minutes) }
        case "selectShelf":
            if let id = step["value"] as? String { model.selectShelfItem(id, toggle: step["toggle"] as? Bool == true, range: step["range"] as? Bool == true) }
        case "shelfMenu":
            if let id = step["value"] as? String, let frame = model.shelfRowFrames[id] {
                model.openShelfMenu(for: id, at: CGPoint(x: frame.maxX, y: frame.maxY + 4), alignRight: true, keyboard: false)
            }
        default: break
        }
    }

    /// Settings intents go through the same model methods as clicks and keys.
    private func settingsIntent(_ intent: String, _ step: [String: Any]) {
        guard let model = settingsWindow?.model else { return }
        let value = step["value"]
        let text = value as? String ?? ""
        let keyboard = step["keyboard"] as? Bool == true
        switch intent {
        case "section": if let section = SettingsSection(rawValue: text) { model.setSection(section, animate: !keyboard) }
        case "moveSection": model.moveSection(by: value as? Int ?? 1)
        case "source": model.selectSource(text, keyboard: keyboard)
        case "activity": model.selectActivity(text, keyboard: keyboard)
        case "preset": if let minutes = value as? Int { model.choosePreset(minutes) }
        case "durationInput": model.editDuration(text)
        case "durationCommit": model.commitDuration(keyboard: keyboard)
        case "toggle": model.toggle(text, keyboard: keyboard)
        case "focusNotifications": model.toggleFocusNotifications()
        case "menu": model.toggleMenu(text, animate: !keyboard)
        case "menuChoose": model.chooseMenuItem(text, keyboard: keyboard)
        case "menuKey": _ = model.menuKey(text)
        case "retentionInput": if let key = step["key"] as? String { model.editRetention(key, text) }
        case "retentionCommit": model.commitRetention(text)
        case "shortcutRecord": model.toggleShortcutRecording()
        case "shortcutReset": model.resetShortcut()
        case "action": model.act(text)
        case "escape": model.escape()
        case "outsideClick": model.closeMenu()
        default: break
        }
    }

    func diagnosticResponse(id: String) -> [String: Any] {
        ["id": id, "panelFrame": NSStringFromRect(panel.frame), "surfaceRect": NSStringFromRect(surfaceRect), "ignoresMouseEvents": panel.ignoresMouseEvents,
         "notificationCaptureStatus": notificationStatus.rawValue,
         "notificationVisible": notificationOwner.visible != nil,
         "notificationPending": notificationOwner.hasPending,
         "shelfDragActive": notchView.isDraggingShelfFiles,
         "shelfDragCompletions": notchView.completedShelfDrags,
         "shelfDragOperation": notchView.lastShelfDragOperation,
         "shelfDragRegionCount": shelfDragRegions.count,
         "selectedNativeView": selectedView,
         "notificationPanelKey": panel.isKeyWindow,
         "notificationAcceptsKey": panel.permitsKey,
         "notificationGeneration": notificationOwner.generation,
         "brainfmPermission": brainFM.hasPermission,
         "brainfmScan": brainFM.lastScanSummary,
         "dataDirectory": dataDirectory.path, "simulatedBrainFM": simulated, "simulatedMeld": simulatedMeld,
         "settingsFrame": settingsWindow?.window.map { NSStringFromRect($0.frame) } as Any? ?? NSNull(),
         "settingsVisible": settingsWindow?.window?.isVisible ?? false,
         "settingsKey": settingsWindow?.window?.isKeyWindow ?? false,
         "keyWindow": NSApp.keyWindow?.title as Any? ?? NSNull(),
         "nativeChecks": [
            ["name": "panel touches physical screen top", "pass": abs(panel.frame.maxY - geometry.screenFrame.maxY) < 0.1],
            ["name": "panel covers menu bar icons", "pass": panel.level.rawValue > NSWindow.Level.statusBar.rawValue]
         ]]
    }

    @discardableResult
    func snapshotNotch(to url: URL) -> Bool { snapshot(notchView, scale: panel.backingScaleFactor, to: url) }

    @discardableResult
    func snapshotSettings(to url: URL) -> Bool {
        guard let view = settingsWindow?.hostView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Renders a view's current layer tree; no screen capture permission is involved.
    private func snapshot(_ view: NSView, scale: CGFloat, to url: URL) -> Bool {
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        guard let layer = view.layer,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
        bitmap.size = size
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
        (layer.presentation() ?? layer).render(in: cg)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    func runSmokeTest() {
        var checks: [[String: Any]] = []
        let check = { (name: String, pass: Bool) in checks.append(["name": name, "pass": pass]) }
        let model = notchModel
        let finish = {
            check("no layout without font", NSFont(name: "Familjen Grotesk", size: 18) != nil)
            let payload: [String: Any] = ["checks": checks, "state": model.inspect()]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/lilt-native-smoke.json"), options: .atomic)
            }
            self.snapshotNotch(to: URL(fileURLWithPath: "/tmp/lilt-native-smoke.png"))
            NSApp.terminate(nil)
        }
        let steps: [(TimeInterval, () -> Void)] = [
            (0, { check("model ready", model.ready); self.setOpen(false) }),
            (0.65, { check("fold", !model.open); self.setOpen(true) }),
            (0.65, { check("open", model.open); self.send("setView", value: "focus") }),
            (0.35, { check("view focus", model.page == .focus); self.send("setView", value: "shelf") }),
            (0.35, { check("view shelf", model.page == .shelf); self.send("setView", value: "music") }),
            (0.35, { check("view music", model.page == .music); self.setOpen(false) }),
            (0.09, { self.setOpen(true) }),
            (0.65, { check("interrupted fold", model.open) })
        ]
        func run(_ index: Int) {
            guard index < steps.count else { finish(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + steps[index].0) { steps[index].1(); run(index + 1) }
        }
        run(0)
    }
}
