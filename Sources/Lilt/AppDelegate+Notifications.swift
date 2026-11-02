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
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.pollNotificationBanners() }
        RunLoop.main.add(timer, forMode: .common)
        notificationTimer = timer
    }

    func configureNotificationBanners() {
        notificationOwner.configure(enabled: settings.value.notificationBannersEnabled,
                                    active: notificationSessionActive && !notificationSleeping)
        let status: NotificationCaptureStatus = smokeTest || diagnosticDirectory != nil ? .diagnostic
            : !settings.value.notificationBannersEnabled ? .disabled
            : !notificationOwner.active ? .suspended : .unsupported
        notificationStatus = status
        sendSettings()
    }

    func pollNotificationBanners() {
        notificationOwner.expire()
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
            self.notificationOwner.receive(result.items, generation: generation,
                                           blocked: self.isOpen || self.selectingFiles || !self.ready)
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
                                        body: diagnostic ? body["body"] as? String ?? "Synthetic preview. No other app was read." : "Synthetic preview. No other app was read.")
        _ = notificationOwner.present(banner, blocked: isOpen || selectingFiles)
    }

    func notificationAccessibilitySettings() {
        guard !smokeTest, diagnosticDirectory == nil, settings.value.notificationBannersEnabled,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
