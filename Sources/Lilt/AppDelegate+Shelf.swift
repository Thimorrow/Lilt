import AppKit
import Quartz

// Shelf files, sharing and Quick Look. The context menu is rendered by the web view.
extension AppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSSharingServicePickerDelegate {
    func chooseFiles() {
        notificationInteraction(keepOpen: true)
        selectingFiles = true
        NSApp.activate(ignoringOtherApps: true)
        let chooser = NSOpenPanel()
        chooser.title = "Dateien zur Ablage hinzufügen"
        chooser.message = "Originale bleiben an ihrem Ort. Lilt merkt sich lokale Dateiverweise."
        chooser.allowsMultipleSelection = true
        chooser.canChooseDirectories = true
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
        if action == "paste" { pasteShelf(); return }
        if action == "undo" { shelf.undoRemoval(); sendShelf(); return }
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

    func receiveShelfDragRegions(_ body: [String: Any]) {
        guard let regions = body["regions"] as? [[String: Any]], regions.count <= 50,
              let selected = body["selected"] as? [String], selected.count <= shelf.entries.count else { return }
        let known = Set(shelf.entries.map(\.id))
        shelfDragSelection = selected.filter { known.contains($0) }
        shelfDragRegions = regions.compactMap { region in
            guard let id = region["id"] as? String, known.contains(id),
                  let x = region["x"] as? Double, let y = region["y"] as? Double,
                  let width = region["width"] as? Double, let height = region["height"] as? Double,
                  [x, y, width, height].allSatisfy(\.isFinite), x >= 0, y >= 0, width > 0, height > 0,
                  x + width <= Double(webView.bounds.width) + 1, y + height <= Double(webView.bounds.height) + 1 else { return nil }
            return (id, CGRect(x: x, y: y, width: width, height: height))
        }
    }

    func prepareShelfDrag(at point: CGPoint) {
        guard isOpen, selectedView == "shelf", !selectingFiles else { return }
        let htmlPoint = CGPoint(x: point.x, y: webView.isFlipped ? point.y : webView.bounds.height - point.y)
        guard let region = shelfDragRegions.first(where: { $0.frame.contains(htmlPoint) }) else { return }
        let ids = shelfDragSelection.contains(region.id) ? shelfDragSelection : [region.id]
        let urls = ids.compactMap { shelf.resolvedURL(for: $0) }
        guard urls.count == ids.count else { return }
        webView.prepareShelfDrag(urls, ids: ids, htmlFrame: region.frame)
    }

    func pasteShelf() {
        if isolatedRun, let diagnosticShelfPasteboard { pasteShelf(from: diagnosticShelfPasteboard); return }
        guard !isolatedRun else {
            shelf.report("Clipboard access is disabled in diagnostic mode.")
            sendShelf(); return
        }
        pasteShelf(from: .general)
    }

    func pasteShelf(from pasteboard: NSPasteboard) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { shelf.report("Copy files or folders in Finder, then paste them here."); sendShelf(); return }
        addFiles(urls)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        selectingFiles = false
        sharingPicker = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURL as NSURL? }
}
