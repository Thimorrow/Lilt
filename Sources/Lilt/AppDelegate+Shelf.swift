import AppKit
import Quartz

// Shelf files, context menu, sharing and Quick Look.
extension AppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSSharingServicePickerDelegate {
    func chooseFiles() {
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

    func addFiles(_ urls: [URL]) {
        shelf.add(urls, retentionDays: settings.value.shelfShortDays)
        sendShelf()
        send("setView", value: "shelf")
        setOpen(true)
    }

    func sendShelf() {
        shelf.pruneExpired()
        if ready { send("receiveShelfSnapshot", value: shelf.snapshot) }
    }

    func shelfAction(_ body: [String: Any]) {
        guard let action = body["command"] as? String else { return }
        if action == "clear" { shelf.clear(); sendShelf(); return }
        if action == "refresh" { sendShelf(); return }
        shelf.pruneExpired()
        let ids: [String]
        if let values = body["ids"] as? [String], !values.isEmpty { ids = values }
        else if let id = body["id"] as? String { ids = [id] }
        else { return }
        let known = Set(shelf.entries.map(\.id))
        guard Set(ids).count == ids.count, ids.allSatisfy({ known.contains($0) }) else { return }
        if action == "remove" { shelf.remove(ids); sendShelf(); return }
        if action == "keep" { shelf.keepLonger(ids, retentionDays: settings.value.shelfLongDays); sendShelf(); return }
        if action == "menu" { showShelfMenu(ids: ids, body: body); return }
        let urls = ids.compactMap { shelf.resolvedURL(for: $0) }
        guard urls.count == ids.count else {
            shelf.report("Die Datei ist nicht mehr verfügbar. Du kannst ihren Eintrag entfernen und die Datei erneut hinzufügen.")
            sendShelf(); return
        }
        guard let url = urls.first else { return }
        switch action {
        case "open":
            guard ids.count == 1 else { return }
            if !NSWorkspace.shared.open(url) { shelf.report("Die Datei konnte nicht geöffnet werden.") }
        case "reveal":
            guard ids.count == 1 else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case "preview":
            guard ids.count == 1 else { return }
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
            if !webView.dragFiles(urls, at: rect) { shelf.report("Ziehe die Datei erneut mit gedrückter Maustaste aus der Ablage.") }
        case "share":
            let picker = NSSharingServicePicker(items: urls)
            sharingPicker = picker
            picker.delegate = self
            let x = max(0, min(webView.bounds.width, body["x"] as? Double ?? webView.bounds.midX))
            let y = max(0, min(webView.bounds.height, body["y"] as? Double ?? webView.bounds.midY))
            let point = NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y)
            selectingFiles = true
            picker.show(relativeTo: NSRect(origin: point, size: NSSize(width: 1, height: 1)), of: webView, preferredEdge: .minY)
        default: return
        }
        sendShelf()
    }

    func showShelfMenu(ids: [String], body: [String: Any]) {
        let menu = NSMenu()
        let available = ids.allSatisfy { shelf.resolvedURL(for: $0) != nil }
        var actions = ids.count == 1 ? [("Quick Look", "preview"), ("Open", "open"), ("Show in Finder", "reveal")] : []
        actions += [("Keep Longer", "keep"), ("Share…", "share"), ("Remove from Shelf", "remove")]
        for (title, command) in actions {
            let item = NSMenuItem(title: title, action: #selector(shelfMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["ids": ids, "command": command, "x": body["x"] ?? 250, "y": body["y"] ?? 100] as [String : Any]
            item.isEnabled = available || command == "remove" || command == "keep"
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        let x = body["x"] as? Double ?? 250
        let y = body["y"] as? Double ?? 100
        selectingFiles = true
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: webView.isFlipped ? y : webView.bounds.height - y), in: webView)
        selectingFiles = sharingPicker != nil
    }

    @objc func shelfMenuAction(_ item: NSMenuItem) {
        guard let command = item.representedObject as? [String: Any] else { return }
        shelfAction(command)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        selectingFiles = false
        sharingPicker = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }
}
