import AppKit
import WebKit

final class NotchWebView: WKWebView, NSDraggingSource {
    var onFiles: (([URL]) -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    private var lastMouseDown: NSEvent?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func recordMouseDown(_ event: NSEvent) { lastMouseDown = event }

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard fileURLs(sender).isEmpty == false else { return [] }
        onFileDragEntered?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onFileDragExited?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        onFileDragExited?()
        return true
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func dragFile(_ url: URL, at rect: CGRect) -> Bool {
        guard let event = lastMouseDown, event.type == .leftMouseDown,
              ProcessInfo.processInfo.systemUptime - event.timestamp < 5 else { return false }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 40, height: 40)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: location.x - 20, y: location.y - 20, width: 40, height: 40), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
