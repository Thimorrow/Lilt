import AppKit

extension AppDelegate {
    func renderNotificationBanner(_ banner: NotificationBanner?, id: UUID) {
        guard ready else { return }
        panel.permitsKey = banner == nil
        send("receiveNotificationBanner", value: banner?.payload ?? ["id": id.uuidString, "clear": true])
        isOpen = banner != nil
        if banner != nil { panel.orderFrontRegardless() }
        else if panel.isKeyWindow { panel.resignKey() }
    }

    func installNotificationBanners() {
        if !smokeTest, diagnosticDirectory == nil {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            notificationSessionActive = session?[kCGSessionOnConsoleKey as String] as? Bool ?? false
        }
        notificationOwner.onChange = { [weak self] banner, id in self?.renderNotificationBanner(banner, id: id) }
        let center = NSWorkspace.shared.notificationCenter
        for (name, active) in [(NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.notificationSessionActive = active
                self.configureNotificationBanners()
            })
        }
        configureNotificationBanners()
        slack.onMessage = { [weak self] banner in self?.notificationOwner.enqueue(banner) }
        slack.onStatus = { [weak self] _ in self?.slackNote = ""; self?.sendSettings() }
        if !isolatedRun, let tokens = SlackKeychain.read() { slack.start(tokens) }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.pollNotificationBanners() }
        RunLoop.main.add(timer, forMode: .common)
        notificationTimer = timer
    }

    func configureNotificationBanners() {
        notificationOwner.configure(enabled: settings.value.notificationBannersEnabled,
                                    active: notificationSessionActive && !notificationSleeping)
        let status: NotificationCaptureStatus = smokeTest || diagnosticDirectory != nil ? .diagnostic
            : !settings.value.notificationBannersEnabled ? .disabled
            : !notificationOwner.active ? .suspended : .active
        notificationStatus = status
        sendSettings()
    }

    func pollNotificationBanners() {
        if ready {
            for message in AgentInbox.drain(AgentInbox.directory(dataDirectory)) {
                notificationOwner.enqueue(NotificationBanner(source: message.source, title: message.project, body: message.message,
                                                             image: appIcon(bundleIdentifier: message.app)))
            }
        }
        notificationOwner.advance(blocked: isOpen || selectingFiles || !ready)
        guard !smokeTest, diagnosticDirectory == nil, ready, notificationOwner.enabled, notificationOwner.active else { return }
        let generation = notificationOwner.generation
        notificationPoller.poll { [weak self] result in
            guard let self, generation == self.notificationOwner.generation,
                  self.notificationOwner.enabled, self.notificationOwner.active else { return }
            if self.notificationStatus != result.status {
                self.notificationStatus = result.status
                if result.status == .permission { self.notificationOwner.invalidate() }
                self.sendSettings()
            }
            guard result.status != .permission else { return }
            // With the Slack app connected, Slack's own system banners would duplicate its richer ones.
            let slackConnected = self.slack.status.code == "connected"
            let items = result.items.filter { !(slackConnected && $0.banner.source == "Slack") }.map { item in
                let banner = item.banner
                return CapturedNotification(key: item.key, banner: NotificationBanner(source: banner.source, title: banner.title,
                                                                                      body: banner.body, image: self.appIcon(named: banner.source)))
            }
            self.notificationOwner.receive(items, generation: generation)
        }
    }

    func notificationInteraction(keepOpen: Bool) {
        guard let id = notificationOwner.visible?.id else { return }
        notificationOwner.clear(notify: false)
        panel.permitsKey = true
        send("notificationTakeover", value: ["id": id.uuidString, "open": keepOpen])
        isOpen = keepOpen
        if !keepOpen, panel.isKeyWindow { panel.resignKey() }
    }

    func previewNotification(_ body: [String: Any] = [:]) {
        guard ready, notificationOwner.active else { return }
        let diagnostic = diagnosticDirectory != nil
        let banner = NotificationBanner(source: diagnostic ? body["source"] as? String ?? "Lilt preview" : "Lilt preview",
                                        title: diagnostic ? body["title"] as? String ?? "Notification banner" : "Notification banner",
                                        body: diagnostic ? body["body"] as? String ?? "Synthetic preview. No other app was read." : "Synthetic preview. No other app was read.",
                                        image: appIcon(bundleIdentifier: diagnostic ? body["app"] as? String ?? "" : ""))
        notificationOwner.enqueue(banner)
    }

    func notificationAccessibilitySettings() {
        guard !smokeTest, diagnosticDirectory == nil, settings.value.notificationBannersEnabled,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Pictures

    /// App icons rendered once at 2x banner size; unknown apps simply get no picture.
    func appIcon(bundleIdentifier: String) -> Data? {
        guard !bundleIdentifier.isEmpty, bundleIdentifier.count <= 200 else { return nil }
        if let cached = appIcons[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return cacheIcon(NSWorkspace.shared.icon(forFile: url.path), key: bundleIdentifier)
    }

    func appIcon(named name: String) -> Data? {
        if let cached = appIcons["name:" + name] { return cached }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }), let icon = app.icon else { return nil }
        return cacheIcon(icon, key: "name:" + name)
    }

    private func cacheIcon(_ icon: NSImage, key: String) -> Data? {
        let size = NSSize(width: 80, height: 80)
        let image = NSImage(size: size, flipped: false) { rect in icon.draw(in: rect); return true }
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        if appIcons.count > 50 { appIcons.removeAll() }
        appIcons[key] = png
        return png
    }

    // MARK: Slack

    func connectSlack(app: String, user: String) {
        guard let tokens = SlackTokens(app: app, user: user) else {
            slackNote = "Paste the app-level token (xapp-…) and the user token (xoxp-…)."
            sendSettings()
            return
        }
        // Isolated runs never touch the Keychain or the network.
        guard !isolatedRun else { slackNote = "Slack is disabled in diagnostics."; sendSettings(); return }
        guard SlackKeychain.save(tokens) else { slackNote = "The tokens could not be saved to the Keychain."; sendSettings(); return }
        slackNote = ""
        slack.start(tokens)
    }

    func disconnectSlack() {
        slack.stop()
        if !isolatedRun { SlackKeychain.delete() }
        slackNote = ""
        sendSettings()
    }

    /// Opens Slack's "create app from manifest" page with Lilt's scopes and Socket Mode prefilled.
    func createSlackApp() {
        guard !isolatedRun, let data = try? JSONSerialization.data(withJSONObject: slackManifest),
              let json = String(data: data, encoding: .utf8) else { return }
        var components = URLComponents(string: "https://api.slack.com/apps")!
        components.queryItems = [URLQueryItem(name: "new_app", value: "1"), URLQueryItem(name: "manifest_json", value: json)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    var slackManifest: [String: Any] {
        ["display_information": ["name": "Lilt", "description": "Shows your Slack messages in the Lilt notch."],
         "oauth_config": ["scopes": ["user": ["im:history", "mpim:history", "channels:history", "groups:history",
                                              "users:read", "channels:read", "groups:read"]]],
         "settings": ["event_subscriptions": ["user_events": ["message.im", "message.mpim", "message.channels", "message.groups"]],
                      "socket_mode_enabled": true, "org_deploy_enabled": false, "token_rotation_enabled": false]]
    }
}
