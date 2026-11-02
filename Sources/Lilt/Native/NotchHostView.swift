import AppKit
import SwiftUI

/// AppKit host for the SwiftUI notch. Owns what SwiftUI cannot: real file drops, multi-file outgoing drags,
/// precise scroll phases for swipes and key equivalents. Coordinates passed to the model use a top-left origin.
final class NotchHostView: NSHostingView<NotchRootView> {
    let model: NotchModel
    var onFiles: (([URL]) -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    var onShelfKeyCommand: ((String) -> Bool)?
    var onShelfDragStarted: (([String]) -> Void)?
    var onShelfMouseDown: ((CGPoint) -> Void)?
    var canTrackSwipe: () -> Bool = { true }
    private(set) var isDraggingShelfFiles = false
    private(set) var completedShelfDrags = 0
    private(set) var lastShelfDragOperation: UInt = 0
    private var shelfDrag = ShelfDragGesture()
    private var tabSwipe = TabSwipeGesture()
    private var swipeOrigin = CGPoint.zero
    private var swipeAccepted = 0
    private var swipeTracking = false
    private var fileDragActive = false
    private lazy var dragSource = ShelfDragSource { [weak self] operation in
        guard let self else { return }
        self.isDraggingShelfFiles = false
        self.shelfDrag.reset()
        self.completedShelfDrags += 1
        self.lastShelfDragOperation = operation.rawValue
    }

    init(model: NotchModel) {
        self.model = model
        super.init(rootView: NotchRootView(model: model))
    }

    @MainActor required init(rootView: NotchRootView) { fatalError("Use init(model:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("Use init(model:)") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Converts a window event location into the top-left panel space used by SwiftUI and the model.
    func topLeft(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command, let command = [UInt16(9): "paste", UInt16(6): "undo"][event.keyCode],
           onShelfKeyCommand?(command) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { model.escape() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { model.escape(); return }
        super.keyDown(with: event)
    }

    // MARK: Pointer

    func recordMouseDown(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        shelfDrag.mouseDown(at: point)
        onShelfMouseDown?(point)
    }

    func endMouseSequence() { shelfDrag.reset() }

    override func mouseDown(with event: NSEvent) {
        recordMouseDown(event)
        super.mouseDown(with: event)
    }

    /// Right-click on a shelf row opens the in-notch file menu at the pointer.
    override func rightMouseDown(with event: NSEvent) {
        let point = topLeft(event)
        if model.open, model.page == .shelf,
           let id = model.shelf.first(where: { model.shelfRowFrames[$0.id]?.intersection(model.shelfListFrame).contains(point) == true })?.id {
            model.openShelfMenu(for: id, at: point, alignRight: false, keyboard: false)
            return
        }
        super.rightMouseDown(with: event)
    }

    // MARK: Swipe

    func observeScrollWheel(_ event: NSEvent) {
        guard event.window === window else {
            cancelSwipe()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let phase: TabSwipeGesture.Phase
        if event.phase.contains(.began) { phase = .began; swipeOrigin = point; swipeAccepted = 0 }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return }
        let blocked = fileDragActive || isDraggingShelfFiles || NSEvent.pressedMouseButtons != 0 || !bounds.contains(swipeOrigin) || !canTrackSwipe()
        if blocked || !event.momentumPhase.isEmpty || !event.hasPreciseScrollingDeltas {
            cancelSwipe()
            return
        }
        if phase == .ended { swipeAccepted = tabSwipe.completionDirection ?? 0 }
        if let result = tabSwipe.update(phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                        precise: true, momentum: false, blocked: false) { swipeAccepted = result }
        switch phase {
        case .began:
            swipeTracking = true
            forward("begin", event.scrollingDeltaX, event.scrollingDeltaY, 0, event.timestamp)
        case .changed:
            if swipeTracking { forward("change", event.scrollingDeltaX, event.scrollingDeltaY, 0, event.timestamp) }
        case .ended, .cancelled:
            if swipeTracking { forward(phase == .ended ? "end" : "cancel", 0, 0, phase == .ended ? swipeAccepted : 0, event.timestamp) }
            swipeTracking = false
        }
    }

    private func forward(_ phase: String, _ dx: CGFloat, _ dy: CGFloat, _ accepted: Int, _ time: TimeInterval) {
        let origin = CGPoint(x: swipeOrigin.x, y: isFlipped ? swipeOrigin.y : bounds.height - swipeOrigin.y)
        model.swipeGesture(phase: phase, dx: dx, dy: dy, accepted: accepted, point: origin, time: time)
    }

    private func cancelSwipe() {
        if swipeTracking { forward("cancel", 0, 0, 0, ProcessInfo.processInfo.systemUptime) }
        swipeTracking = false
        tabSwipe.reset()
    }

    // MARK: Incoming file drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isDraggingShelfFiles, !fileURLs(sender).isEmpty else { return [] }
        fileDragActive = true
        cancelSwipe()
        onFileDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender).isEmpty ? [] : .copy }
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

    // MARK: Outgoing shelf drags

    /// `frame` is a visible row in top-left panel coordinates.
    func prepareShelfDrag(_ urls: [URL], ids: [String], frame: CGRect) {
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return }
        let y = isFlipped ? frame.minY : bounds.height - frame.maxY
        shelfDrag.prepare(urls: urls, ids: ids, frame: CGRect(x: frame.minX, y: y, width: frame.width, height: frame.height))
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
        cancelSwipe()
        onShelfDragStarted?(payload.ids)
        beginDraggingSession(with: items, event: event, source: dragSource)
        return true
    }
}

/// Outgoing shelf drags advertise copy only; the hosting view's own SwiftUI drag source stays untouched.
private final class ShelfDragSource: NSObject, NSDraggingSource {
    private let ended: (NSDragOperation) -> Void

    init(ended: @escaping (NSDragOperation) -> Void) { self.ended = ended }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { ended(operation) }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
