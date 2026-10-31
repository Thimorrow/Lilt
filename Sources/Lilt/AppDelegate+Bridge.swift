import AppKit
import WebKit

// Routes messages from the notch and settings web views to native owners.
extension AppDelegate: WKScriptMessageHandler, WKNavigationDelegate {
    func handleSettingsAction(_ body: [String: Any]) {
        switch body["action"] as? String {
        case "settingsUpdate":
            guard let changes = body["changes"] as? [String: Any] else { return }
            updateSettings(changes)
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready":
            ready = true
            configureUI()
            send("receiveFocusSnapshot", value: focus.snapshot)
            sendShelf()
            sendSettings()
            sendMusic()
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
        case "swipeHaptic": NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
}
