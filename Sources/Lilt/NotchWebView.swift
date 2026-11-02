import AppKit
import WebKit

final class NotchWebView: WKWebView, NSDraggingSource {
    var onFiles: (([URL]) -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    var onShelfKeyCommand: ((String) -> Bool)?
    var onShelfDragStarted: (([String]) -> Void)?
    var onShelfMouseDown: ((CGPoint) -> Void)?
    private(set) var isDraggingShelfFiles = false
    private(set) var completedShelfDrags = 0
    private(set) var lastShelfDragOperation: UInt = 0
    var onTabSwipeProgress: ((String, CGFloat, CGFloat, Int, CGPoint) -> Void)?
    private var shelfDrag = ShelfDragGesture()
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command, let command = [UInt16(9): "paste", UInt16(6): "undo"][event.keyCode],
           onShelfKeyCommand?(command) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    func recordMouseDown(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        shelfDrag.mouseDown(at: point)
        onShelfMouseDown?(point)
    }
    func endMouseSequence() { shelfDrag.reset() }

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
        let blocked = fileDragActive || isDraggingShelfFiles || NSEvent.pressedMouseButtons != 0 || !bounds.contains(swipeOrigin)
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
        recordMouseDown(event)
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isDraggingShelfFiles else { return [] }
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

    func prepareShelfDrag(_ urls: [URL], ids: [String], htmlFrame: CGRect) {
        guard htmlFrame.minX.isFinite, htmlFrame.minY.isFinite, htmlFrame.width.isFinite, htmlFrame.height.isFinite,
              htmlFrame.width > 0, htmlFrame.height > 0 else { return }
        let y = isFlipped ? htmlFrame.minY : bounds.height - htmlFrame.maxY
        shelfDrag.prepare(urls: urls, ids: ids, frame: CGRect(x: htmlFrame.minX, y: y, width: htmlFrame.width, height: htmlFrame.height))
    }

    func beginShelfDrag(with event: NSEvent) -> Bool {
        guard event.type == .leftMouseDragged, event.window === window, !isDraggingShelfFiles,
              let payload = shelfDrag.drag(at: convert(event.locationInWindow, from: nil)) else { return false }
        let location = convert(event.locationInWindow, from: nil)
        let items = payload.urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 40, height: 40)
            let offset = CGFloat(min(index, 3)) * 3
            item.setDraggingFrame(NSRect(x: location.x - 20 + offset, y: location.y - 20 - offset, width: 40, height: 40), contents: image)
            return item
        }
        isDraggingShelfFiles = true
        if swipeTracking { onTabSwipeProgress?("cancel", 0, 0, 0, swipeOrigin); swipeTracking = false }
        tabSwipe.reset()
        onShelfDragStarted?(payload.ids)
        beginDraggingSession(with: items, event: event, source: self)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingShelfFiles = false
        shelfDrag.reset()
        completedShelfDrags += 1
        lastShelfDragOperation = operation.rawValue
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
