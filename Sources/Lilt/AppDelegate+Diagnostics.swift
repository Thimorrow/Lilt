import AppKit
import WebKit

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
              x.isFinite, y.isFinite, x >= 0, x < webView.bounds.width, y >= 0, y < webView.bounds.height,
              let phase = body["phase"] as? String, ["down", "up"].contains(phase) else { return }
        let type: NSEvent.EventType = phase == "down" ? .leftMouseDown : .leftMouseUp
        let point = NSPoint(x: x, y: panel.contentView!.bounds.height - y)
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: phase == "down" ? 1 : 0) else { return }
        panel.sendEvent(event)
    }

    func runDiagnosticCommand(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = command["id"] as? String, id != lastDiagnosticID,
              let script = command["script"] as? String else { return }
        lastDiagnosticID = id
        let settingsTarget = command["target"] as? String == "settings"
        if settingsTarget, settingsWindow == nil { showSettings() }
        if settingsTarget, let size = command["settingsSize"] as? [String: Double],
           let width = size["width"], let height = size["height"],
           width.isFinite, height.isFinite, (700...1600).contains(width), (540...1200).contains(height) {
            settingsWindow?.window?.setContentSize(NSSize(width: width, height: height))
        }
        guard let targetWebView = settingsTarget ? settingsWindow?.webView : webView else { return }
        targetWebView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            var response: [String: Any] = ["id": id, "panelFrame": NSStringFromRect(self.panel.frame), "surfaceRect": NSStringFromRect(self.surfaceRect), "ignoresMouseEvents": self.panel.ignoresMouseEvents,
                "brainfmPermission": self.brainFM.hasPermission,
                "brainfmScan": self.brainFM.lastScanSummary,
                "dataDirectory": self.dataDirectory.path, "simulatedBrainFM": self.simulated, "simulatedMeld": self.simulatedMeld,
                "settingsFrame": self.settingsWindow?.window.map { NSStringFromRect($0.frame) } as Any? ?? NSNull(),
                "settingsVisible": self.settingsWindow?.window?.isVisible ?? false,
                "settingsKey": self.settingsWindow?.window?.isKeyWindow ?? false,
                "keyWindow": NSApp.keyWindow?.title as Any? ?? NSNull(),
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
                self.snapshot(to: directory.appendingPathComponent("capture.png"), webView: targetWebView) { error in
                    response["snapshotSuccess"] = error == nil
                    if let error { response["snapshotError"] = error.localizedDescription }
                    finish(response)
                }
            } else { finish(response) }
        }
    }

    func snapshot(to url: URL, webView target: WKWebView? = nil, completion: ((Error?) -> Void)? = nil) {
        (target ?? webView).takeSnapshot(with: nil) { image, error in
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

    func runSmokeTest() {
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
