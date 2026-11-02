import AppKit

// Routes intents from the native notch and settings window to native owners.
extension AppDelegate {
    func handleSettingsAction(_ body: [String: Any]) {
        switch body["action"] as? String {
        case "settingsUpdate":
            guard let changes = body["changes"] as? [String: Any] else { return }
            updateSettings(changes)
        case "notificationPreview": previewNotification()
        case "notificationAccessibilitySettings": notificationAccessibilitySettings()
        case "slackConnect": connectSlack(app: body["appToken"] as? String ?? "", user: body["userToken"] as? String ?? "")
        case "slackDisconnect": disconnectSlack()
        case "slackCreateApp": createSlackApp()
        case "shortcutRecord":
            shortcut?.setEnabled(false)
            settingsWindow?.beginShortcutRecording()
        case "shortcutCancelRecording": settingsWindow?.endShortcutRecording()
        case "shortcutRecordingEnded": applyShortcut()
        case "focusNotificationPermission": enableFocusNotifications()
        case "testShortcutKey":
            guard diagnosticDirectory != nil, let code = body["keyCode"] as? Int, (0...127).contains(code),
                  let flags = body["modifiers"] as? UInt,
                  flags & ~NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue == 0,
                  let window = settingsWindow?.window,
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags), timestamp: 0,
                      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)) else { return }
            _ = settingsWindow?.recordShortcutKey(event)
        case "musicConnect": connectMusic()
        case "musicOpen": openMusic()
        case "brainfmSettings": openAccessibilitySettings()
        case "brainfm": openBrainFM()
        default: break
        }
    }

    func receiveFocusAction(_ body: [String: Any]) {
        guard let raw = body["command"] as? String, let action = FocusCoordinator.Action(rawValue: raw) else { return }
        focus.request(action)
    }

    func receiveFocusConfiguration(_ body: [String: Any]) {
        guard let raw = body["activity"] as? String, let activity = FocusActivity(rawValue: raw),
              let minutes = body["minutes"] as? Int, (1...180).contains(minutes) else { return }
        focus.configure(activity: activity, minutes: minutes)
        if focus.session.activity == activity, focus.session.duration == minutes * 60 {
            var value = settings.value
            value.focusActivity = activity
            value.focusMinutes = minutes
            settings.save(value)
            sendSettings()
        }
    }

    /// Every notch intent arrives here as a validated message dictionary, as it did across the former web bridge.
    func handleNotchMessage(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        switch action {
        case "viewChanged":
            if let view = body["view"] as? String, ["music", "focus", "shelf"].contains(view) { selectedView = view; panelInteractionRevision += 1 }
        case "testShelfPaste":
            guard diagnosticDirectory != nil, let names = body["names"] as? [String], !names.isEmpty,
                  names.count <= 100, names.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }) else { return }
            let pasteboard = NSPasteboard.withUniqueName()
            diagnosticShelfPasteboard?.releaseGlobally()
            diagnosticShelfPasteboard = pasteboard
            pasteboard.writeObjects(names.map { dataDirectory.appendingPathComponent("fixtures", isDirectory: true).appendingPathComponent($0) as NSURL })
        case "testShelfKey":
            guard diagnosticDirectory != nil, let code = body["keyCode"] as? UInt16, [6, 9].contains(code),
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber,
                    context: nil, characters: code == 6 ? "z" : "v", charactersIgnoringModifiers: code == 6 ? "z" : "v", isARepeat: false, keyCode: code) else { return }
            _ = notchView.performKeyEquivalent(with: event)
        case "ready":
            ready = true
            configureUI()
            send("receiveFocusSnapshot", value: focus.snapshot)
            sendShelf()
            sendSettings()
            sendMusic()
            panel.orderFrontRegardless()
            if openFocusOnReady {
                openFocusOnReady = false
                send("setView", value: "focus")
                setOpen(true)
                panel.makeKey()
            }
            if smokeTest { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.runSmokeTest() } }
        case "notificationDismiss":
            guard let raw = body["id"] as? String, let id = UUID(uuidString: raw), notificationOwner.visible?.id == id else { return }
            notificationInteraction(keepOpen: false)
        case "notificationTakeover":
            guard let raw = body["id"] as? String, let id = UUID(uuidString: raw), notificationOwner.visible?.id == id else { return }
            notificationInteraction(keepOpen: true)
        case "testNotification":
            guard diagnosticDirectory != nil else { return }
            if body["clear"] as? Bool == true { notificationOwner.clear() }
            else if body["expire"] as? Bool == true { notificationOwner.expire(now: Date().addingTimeInterval(9)) }
            else { previewNotification(body) }
        case "openChanged":
            if let open = body["open"] as? Bool {
                panelInteractionRevision += 1
                if !open || body["userOwned"] as? Bool == true { notificationInteraction(keepOpen: open) }
                isOpen = open
                if !open, panel.isKeyWindow { panel.resignKey() }
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
        case "settingsOpen": showSettings()
        case "musicOpen": openMusic()
        case "musicConnect": connectMusic()
        case "brainfm": openBrainFM()
        case "brainfmSettings": openAccessibilitySettings()
        case "musicAction":
            if let raw = body["command"] as? String, let command = MeldCommand(rawValue: raw) { music.request(command) }
        case "meldOpen": openMeld()
        case "testMusic": diagnosticMusicFixture(body)
        case "testPointer": diagnosticPointer(body)
        case "focusAction": receiveFocusAction(body)
        case "focusConfigure": receiveFocusConfiguration(body)
        case "focusIntervalsConfigure":
            guard let work = body["workMinutes"] as? NSNumber, let rest = body["restMinutes"] as? NSNumber,
                  CFGetTypeID(work) != CFBooleanGetTypeID(), CFGetTypeID(rest) != CFBooleanGetTypeID(),
                  work.doubleValue.isFinite, rest.doubleValue.isFinite,
                  work.doubleValue.rounded() == work.doubleValue, rest.doubleValue.rounded() == rest.doubleValue,
                  (1...180).contains(work.doubleValue), (1...180).contains(rest.doubleValue) else { return }
            focus.configureIntervals(workMinutes: work.intValue, restMinutes: rest.intValue)
        case "focusIntervalsNext": focus.nextInterval()
        case "shelfAction": shelfAction(body)
        case "shelfDragRegions": receiveShelfDragRegions(body)
        case "testOutsideInteraction":
            if diagnosticDirectory != nil { dismissMenusOrClose() }
        case "swipeHaptic": NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        case "testFocus": diagnosticFixture(body)
        case "quit": quit()
        default: break
        }
    }
}
