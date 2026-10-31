import AppKit
import WebKit

final class NotchWebView: WKWebView, NSDraggingSource {
    var onFiles: (([URL]) -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    var onTabSwipeProgress: ((String, CGFloat, CGFloat, Int, CGPoint) -> Void)?
    private var lastMouseDown: NSEvent?
    private var tabSwipe = TabSwipeGesture()
    private var swipeOrigin = CGPoint.zero
    private var swipeAccepted = 0
    private var swipeTracking = false
    private var fileDragActive = false
    private var pendingSwipeScripts: [String] = []
    private var swipeScriptInFlight = false
    private(set) var swipeEventTime: TimeInterval = 0

    func sendTabSwipeProgress(_ phase: String, dx: CGFloat, dy: CGFloat, accepted: Int, point: CGPoint) {
        let y = isFlipped ? point.y : bounds.height - point.y
        let time = swipeEventTime > 0 ? swipeEventTime : ProcessInfo.processInfo.systemUptime
        pendingSwipeScripts.append("window.Lilt?.swipeGesture('\(phase)',\(dx),\(dy),\(accepted),\(point.x),\(y),\(time))")
        flushSwipeScripts()
    }

    private func flushSwipeScripts() {
        guard !swipeScriptInFlight, !pendingSwipeScripts.isEmpty else { return }
        let script = pendingSwipeScripts.joined(separator: ";")
        pendingSwipeScripts.removeAll(keepingCapacity: true)
        swipeScriptInFlight = true
        evaluateJavaScript(script) { [weak self] _, _ in
            guard let self else { return }
            self.swipeScriptInFlight = false
            self.flushSwipeScripts()
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func recordMouseDown(_ event: NSEvent) { lastMouseDown = event }

    func observeScrollWheel(_ event: NSEvent) {
        swipeEventTime = event.timestamp
        guard event.window === window else {
            if swipeTracking { onTabSwipeProgress?("cancel", 0, 0, 0, swipeOrigin) }
            swipeTracking = false
            tabSwipe.reset()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let phase: TabSwipeGesture.Phase
        if event.phase.contains(.began) { phase = .began; swipeOrigin = point; swipeAccepted = 0 }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return }
        let blocked = fileDragActive || NSEvent.pressedMouseButtons != 0 || !bounds.contains(swipeOrigin)
        let momentum = !event.momentumPhase.isEmpty
        if blocked || momentum || !event.hasPreciseScrollingDeltas {
            if swipeTracking { onTabSwipeProgress?("cancel", 0, 0, 0, swipeOrigin) }
            swipeTracking = false
            tabSwipe.reset()
            return
        }
        if phase == .ended { swipeAccepted = tabSwipe.completionDirection ?? 0 }
        let result = tabSwipe.update(phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                     precise: true, momentum: false, blocked: false)
        if let result { swipeAccepted = result }
        switch phase {
        case .began:
            swipeTracking = true
            onTabSwipeProgress?("begin", event.scrollingDeltaX, event.scrollingDeltaY, 0, swipeOrigin)
        case .changed:
            if swipeTracking { onTabSwipeProgress?("change", event.scrollingDeltaX, event.scrollingDeltaY, 0, swipeOrigin) }
        case .ended, .cancelled:
            if swipeTracking { onTabSwipeProgress?(phase == .ended ? "end" : "cancel", 0, 0, phase == .ended ? swipeAccepted : 0, swipeOrigin) }
            swipeTracking = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard fileURLs(sender).isEmpty == false else { return [] }
        fileDragActive = true
        if swipeTracking { onTabSwipeProgress?("cancel", 0, 0, 0, swipeOrigin); swipeTracking = false }
        tabSwipe.reset()
        onFileDragEntered?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { fileDragActive = false; onFileDragExited?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        fileDragActive = false
        onFileDragExited?()
        return true
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func dragFile(_ url: URL, at rect: CGRect) -> Bool {
        dragFiles([url], at: rect)
    }

    func dragFiles(_ urls: [URL], at rect: CGRect) -> Bool {
        guard let event = lastMouseDown, event.type == .leftMouseDown,
              ProcessInfo.processInfo.systemUptime - event.timestamp < 5,
              !urls.isEmpty else { return false }
        let location = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 40, height: 40)
            let offset = CGFloat(min(index, 3)) * 3
            item.setDraggingFrame(NSRect(x: location.x - 20 + offset, y: location.y - 20 - offset, width: 40, height: 40), contents: image)
            return item
        }
        fileDragActive = true
        if swipeTracking { onTabSwipeProgress?("cancel", 0, 0, 0, swipeOrigin); swipeTracking = false }
        tabSwipe.reset()
        beginDraggingSession(with: items, event: event, source: self)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { fileDragActive = false }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
