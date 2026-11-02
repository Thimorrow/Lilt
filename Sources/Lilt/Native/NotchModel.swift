import AppKit
import Observation
import QuartzCore

/// Native replacement for the former `window.Lilt` bridge. AppDelegate feeds it snapshots; SwiftUI renders it.
/// Outgoing user intents use the same validated message dictionaries that AppDelegate already routes.
@Observable
final class NotchModel {
    enum FocusMenu: Equatable { case duration, activity }
    enum FocusMenuMode: Equatable { case list, custom, intervals }

    struct ShelfMenu: Equatable {
        var ids: [String]
        /// Anchor point in notch-content coordinates.
        var point: CGPoint
        var alignRight: Bool
        var keyboard: Bool
    }

    // Native → UI state.
    var page = NotchPage.music
    var open = false
    var music = MusicState()
    var musicCover: NSImage?
    var focus = FocusState()
    var musicSource = "spotify"
    var musicSourceName = "Spotify"
    var brainFMSetting = false
    var shelf: [ShelfItem] = []
    var shelfMessage: String?
    var shelfCanUndo = false
    var banner: NotificationBannerContent?
    var dragging = false
    var hardwareWidth: CGFloat = 188
    var hardwareHeight: CGFloat = 32
    var hideHardwareWings = false
    var hideNotchContent = false
    var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private(set) var ready = false

    // Local presentation state.
    var selection = ShelfSelection()
    var focusMenu: FocusMenu?
    var focusMenuMode = FocusMenuMode.list
    var shelfMenu: ShelfMenu?
    /// Keyboard focus target after arrow navigation in the shelf list.
    var focusedShelfItem: String?
    /// When true, the next page change switches without the fade/scale transition.
    var instantPage = false
    /// Shared strip position in points while a swipe tracks or settles; nil otherwise.
    var swipePosition: CGFloat?
    /// Increments when a new track arrives so the cover can replay its entrance.
    var coverRevision = 0

    @ObservationIgnored var post: ([String: Any]) -> Void = { _ in }
    @ObservationIgnored private var swipe: SwipeTracker?
    @ObservationIgnored private var gesture: SwipeGestureState?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var closeHitWork: DispatchWorkItem?

    // MARK: Geometry (CSS k = 1)

    static let panelWidth = NotchGeometry.panelSize.width
    var compactSize: CGSize { CGSize(width: hardwareWidth + 132, height: hardwareHeight) }
    var openSize: CGSize {
        CGSize(width: min(Self.panelWidth - 32, max(500, hardwareWidth + 260)), height: hardwareHeight + 160)
    }
    /// Width of one page inside the 18 pt horizontal padding.
    var pageWidth: CGFloat { openSize.width - 36 }

    // MARK: Derived text

    var sourceName: String { music.sourceName ?? musicSourceName }
    var brainFMEnabled: Bool { focus.brainFMEnabled ?? brainFMSetting }
    var focusWithMusic: Bool { brainFMEnabled && !focus.isBreak }
    var connected: Bool { music.availability == .ready }
    var shelfSelectedIDs: [String] { shelf.map(\.id).filter(selection.selected.contains) }

    // MARK: Native → UI

    func receive(_ method: String, _ value: Any) {
        switch method {
        case "configure": configure(value as? [String: Any] ?? [:])
        case "setOpen": if let open = value as? Bool { setOpen(open) }
        case "setView": if let raw = value as? String, let page = NotchPage(rawValue: raw) { setPage(page) }
        case "setDragging":
            let dragging = value as? Bool ?? false
            if dragging { clearSwipe() }
            self.dragging = dragging
        case "receiveMusicSnapshot": receiveMusic(value)
        case "receiveFocusSnapshot": receiveFocus(value)
        case "receiveShelfSnapshot": receiveShelf(value)
        case "receiveSettingsSnapshot": receiveSettings(value)
        case "receiveNotificationBanner": receiveBanner(value)
        case "notificationTakeover":
            guard let value = value as? [String: Any], let id = value["id"] as? String, id == banner?.id,
                  let open = value["open"] as? Bool else { return }
            clearBanner(keepOpen: open, notify: false)
            setOpen(open)
        case "selectShelfDrag":
            guard let ids = value as? [String] else { return }
            let known = Set(shelf.map(\.id))
            selection = ShelfSelection(selected: Set(ids.filter(known.contains)), anchor: ids.first)
            publishShelfRegions()
        default: break
        }
    }

    func configure(_ value: [String: Any]) {
        if let width = (value["hardwareWidth"] as? NSNumber)?.doubleValue, width.isFinite { hardwareWidth = max(0, min(500, width)) }
        if let height = (value["hardwareHeight"] as? NSNumber)?.doubleValue, height.isFinite { hardwareHeight = max(24, min(100, height)) }
        if let hide = value["hideHardwareWings"] as? Bool { hideHardwareWings = hide }
        if let hide = value["hideNotchContent"] as? Bool { hideNotchContent = hide }
        if let reduce = value["reducedMotion"] as? Bool { reducedMotion = reduce }
        if reducedMotion { clearSwipe() }
        if !ready { ready = true }
        publishSurface(immediate: true)
    }

    private func receiveMusic(_ value: Any) {
        guard let snapshot = MusicState(value, now: ProcessInfo.processInfo.systemUptime), !snapshot.sameContent(as: music) else { return }
        let before = music
        music = snapshot
        if snapshot.cover != before.cover { musicCover = snapshot.cover.flatMap { decodeDataImage($0, types: ["jpeg"]) } }
        if !before.id.isEmpty, !snapshot.id.isEmpty, before.id != snapshot.id { coverRevision += 1 }
        if let error = snapshot.error, error.message != before.error?.message { announce(error.message) }
    }

    private func receiveFocus(_ value: Any) {
        guard let snapshot = FocusState(value) else { return }
        let before = focus
        focus = snapshot
        if snapshot.locked, focusMenu != nil { closeFocusMenu() }
        if let error = snapshot.error, error.message != before.error?.message { announce(error.message) }
        else if snapshot.phase == .completed, before.phase != .completed {
            if let interval = snapshot.interval {
                announce("\(interval.phase == "work" ? "Work" : "Break") complete. Start the next phase when ready.")
            } else {
                announce(brainFMEnabled ? "Focus session complete. Brain.fm paused." : "Focus session complete.")
            }
        }
    }

    private func receiveShelf(_ value: Any) {
        guard let value = value as? [String: Any], let items = value["items"] as? [Any] else { return }
        shelf = items.compactMap(ShelfItem.init)
        selection.retain(shelf.map(\.id))
        shelfMessage = value["message"] as? String
        shelfCanUndo = value["canUndoRemoval"] as? Bool == true
        if shelfMenu != nil { shelfMenu = nil }
        publishShelfRegions()
    }

    private func receiveSettings(_ value: Any) {
        guard let value = value as? [String: Any], let source = value["musicSource"] as? String,
              let name = ["spotify": "Spotify", "appleMusic": "Apple Music", "meld": "Meld"][source],
              let brainFM = value["brainFMEnabled"] as? Bool else { return }
        musicSource = source
        musicSourceName = name
        brainFMSetting = brainFM
    }

    // MARK: Banner

    private func receiveBanner(_ value: Any) {
        if let value = value as? [String: Any], value["clear"] as? Bool == true {
            guard value["id"] as? String == banner?.id else { return }
            clearBanner(keepOpen: false, notify: false)
            setOpen(false)
            return
        }
        guard let content = NotificationBannerContent(value), !open, banner == nil else { return }
        clearSwipe()
        banner = content
        setOpen(true)
    }

    func clearBanner(keepOpen: Bool, notify: Bool = true) {
        guard let id = banner?.id else { return }
        banner = nil
        guard notify else { return }
        post(["action": keepOpen ? "notificationTakeover" : "notificationDismiss", "id": id])
        if keepOpen { post(["action": "openChanged", "open": true, "userOwned": true]) }
    }

    // MARK: Open state and pages

    func setOpen(_ value: Bool) {
        if !value {
            clearBanner(keepOpen: false)
            clearSwipe()
            focusMenu = nil
            shelfMenu = nil
        }
        guard open != value else { return }
        open = value
        publishSurface(immediate: value)
        publishShelfRegions()
        post(["action": "openChanged", "open": value])
    }

    func setPage(_ page: NotchPage, animate: Bool = true, preserveSwipe: Bool = false) {
        clearBanner(keepOpen: true)
        if !preserveSwipe { clearSwipe() }
        focusMenu = nil
        shelfMenu = nil
        instantPage = !animate || reducedMotion || !open || preserveSwipe
        self.page = page
        post(["action": "viewChanged", "view": page.rawValue])
        if page == .shelf { shelfCommand("refresh") }
        publishShelfRegions()
    }

    /// Outside clicks first dismiss an open menu; only a click without a menu folds the notch.
    @discardableResult
    func dismissMenus() -> Bool {
        let hadMenu = focusMenu != nil || shelfMenu != nil
        closeFocusMenu()
        closeShelfMenu()
        return hadMenu
    }

    func escape() {
        if shelfMenu != nil { closeShelfMenu() }
        else if focusMenu != nil { closeFocusMenu() }
        else { setOpen(false) }
    }

    // MARK: Hit surface

    private func publishSurface(immediate: Bool) {
        closeHitWork?.cancel()
        let send = { [weak self] in
            guard let self else { return }
            let size = self.open ? self.openSize : self.compactSize
            self.post(["action": "hitRect", "x": Double((Self.panelWidth - size.width) / 2), "y": 0.0,
                       "width": Double(size.width), "height": Double(size.height), "radius": self.open ? 28.0 : 10.0])
        }
        if immediate || reducedMotion { send(); return }
        // The shell keeps covering the open area until the 520 ms fold finishes.
        let work = DispatchWorkItem(block: send)
        closeHitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52, execute: work)
    }

    // MARK: User intents

    func musicCommand(_ command: String) {
        guard music.pending == nil, connected else { return }
        let allowed = ["play": music.canPlay, "pause": music.canPause, "next": music.canNext, "previous": music.canPrevious]
        if allowed[command] == true { post(["action": "musicAction", "command": command]) }
    }

    func togglePlayback() { musicCommand(music.playing ? "pause" : "play") }

    func openPlayer() { post(["action": (music.source ?? musicSource) == "meld" ? "meldOpen" : "musicOpen"]) }

    func focusCommand(_ command: String) {
        guard focus.pending == nil, !focus.restoring, focus.ready else { return }
        post(["action": "focusAction", "command": command])
    }

    func focusPrimary() {
        if focus.error == nil, focus.awaitingNext { post(["action": "focusIntervalsNext"]); return }
        focusCommand(focus.primaryAction)
    }

    func configureFocus(activity: String? = nil, minutes: Int? = nil, activityOnly: Bool = false) {
        guard !focus.locked else { return }
        let activity = activity ?? focus.activity
        let minutes = minutes ?? focus.duration / 60
        guard (1...180).contains(minutes) else { return }
        if (!activityOnly && focus.interval != nil) || activity != focus.activity || minutes != focus.duration / 60 {
            post(["action": "focusConfigure", "activity": activity, "minutes": minutes])
        }
        closeFocusMenu()
    }

    func configureIntervals(work: Int, rest: Int) {
        guard !focus.locked, (1...180).contains(work), (1...180).contains(rest) else { return }
        post(["action": "focusIntervalsConfigure", "workMinutes": work, "restMinutes": rest])
        closeFocusMenu()
    }

    func toggleFocusMenu(_ kind: FocusMenu) {
        guard !focus.locked else { return }
        if focusMenu == kind { closeFocusMenu(); return }
        focusMenuMode = .list
        focusMenu = kind
    }

    func closeFocusMenu() {
        focusMenu = nil
        focusMenuMode = .list
    }

    func shelfCommand(_ command: String, ids: [String] = [], anchor: CGPoint? = nil) {
        var message: [String: Any] = ["action": "shelfAction", "command": command]
        if let first = ids.first { message["id"] = first; message["ids"] = ids }
        if let anchor { message["x"] = Double(anchor.x); message["y"] = Double(anchor.y) }
        post(message)
    }

    func selectShelfItem(_ id: String, toggle: Bool = false, range: Bool = false) {
        selection.select(id, in: shelf.map(\.id), toggle: toggle, range: range)
        publishShelfRegions()
    }

    func openShelfMenu(for id: String, at point: CGPoint, alignRight: Bool, keyboard: Bool) {
        if !selection.selected.contains(id) { selection.select(id, in: shelf.map(\.id)) }
        let ids = shelfSelectedIDs
        guard !ids.isEmpty else { return }
        shelfMenu = ShelfMenu(ids: ids, point: point, alignRight: alignRight, keyboard: keyboard)
        publishShelfRegions()
    }

    func closeShelfMenu() {
        guard shelfMenu != nil else { return }
        shelfMenu = nil
        publishShelfRegions()
    }

    func shelfMenuItems(_ ids: [String]) -> [(command: String, label: String, enabled: Bool)] {
        let available = shelf.filter { ids.contains($0.id) }.allSatisfy(\.available)
        let single = ids.count == 1
        return (single ? [("preview", "Quick Look", available), ("open", "Open", available), ("reveal", "Show in Finder", available)] : [])
            + [("share", "Share…", available), ("keep", "Keep Longer", true), ("remove", single ? "Remove" : "Remove \(ids.count)", true)]
    }

    // MARK: Shelf drag regions

    /// Visible row frames in panel coordinates (top-left origin), reported by the shelf list.
    @ObservationIgnored var shelfRowFrames: [String: CGRect] = [:]
    /// Focus view and dropdown trigger frames in panel coordinates (top-left origin).
    var focusPageFrame = CGRect.zero
    var focusTriggerFrames: [FocusMenu: CGRect] = [:]
    @ObservationIgnored var shelfListFrame = CGRect.zero
    @ObservationIgnored private var regionsScheduled = false

    func publishShelfRegions() {
        guard !regionsScheduled else { return }
        regionsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.regionsScheduled = false
            let active = self.open && self.page == .shelf && self.shelfMenu == nil && self.banner == nil && self.swipePosition == nil
            let clip = self.shelfListFrame
            let regions: [[String: Any]] = active ? self.shelf.compactMap { item in
                guard let frame = self.shelfRowFrames[item.id]?.intersection(clip), !frame.isNull, frame.width > 0, frame.height > 0 else { return nil }
                return ["id": item.id, "x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)]
            }.prefix(50).map { $0 } : []
            self.post(["action": "shelfDragRegions", "regions": regions, "selected": self.shelfSelectedIDs])
        }
    }

    // MARK: Swipe

    /// Precise native scroll phases. `point` is in panel coordinates with a top-left origin.
    func swipeGesture(phase: String, dx: CGFloat, dy: CGFloat, accepted: Int, point: CGPoint, time: TimeInterval) {
        if phase == "begin" {
            guard canSwipe(at: point) else { clearSwipe(); return }
            ticker?.stop()
            gesture = SwipeGestureState(index: page.index, origin: swipe?.position)
        }
        guard var gesture, open, dx.isFinite, dy.isFinite else { return }
        let pages = NotchPage.allCases.count
        if phase == "begin" || phase == "change" {
            gesture.x += dx
            gesture.y += dy
            gesture.lockAxis()
            self.gesture = gesture
            guard gesture.axis == .horizontal, !reducedMotion else { return }
            if swipe == nil { swipe = SwipeTracker(width: pageWidth, position: CGFloat(gesture.index) * pageWidth) }
            guard var swipe else { return }
            if gesture.origin == nil { gesture.origin = CGFloat(gesture.index) * swipe.width }
            let haptic = swipe.track(gesture: &gesture, pages: pages, time: time)
            self.swipe = swipe
            self.gesture = gesture
            if haptic { post(["action": "swipeHaptic"]) }
            swipePosition = swipe.position
            return
        }
        guard phase == "end" || phase == "cancel" else { return }
        let direction = gesture.x < 0 ? 1 : -1
        let next = gesture.index + direction
        let commit = phase == "end" && gesture.axis == .horizontal && accepted == direction && abs(gesture.x) >= 40 && (0..<pages).contains(next)
        let index = commit ? next : gesture.index
        self.gesture = nil
        if commit { setPage(NotchPage.allCases[index], animate: false, preserveSwipe: true) }
        guard !reducedMotion, var swipe else { clearSwipe(); return }
        if let last = swipe.inputTime, time - last > 0.08 { swipe.velocity = 0 }
        swipe.beginSettle(to: index)
        self.swipe = swipe
        startTicker()
    }

    private func canSwipe(at point: CGPoint) -> Bool {
        guard banner == nil, open, point.x.isFinite, point.y.isFinite, !dragging, focusMenu == nil, shelfMenu == nil else { return false }
        let size = openSize
        return CGRect(x: (Self.panelWidth - size.width) / 2, y: 0, width: size.width, height: size.height).contains(point)
    }

    private func startTicker() {
        if ticker == nil { ticker = FrameTicker { [weak self] now in self?.frame(now) } }
        ticker?.start()
    }

    private func frame(_ now: CFTimeInterval) {
        guard var swipe else { ticker?.stop(); return }
        let finished = swipe.step(now: now)
        self.swipe = swipe
        swipePosition = swipe.position
        if finished { clearSwipe() }
    }

    func clearSwipe() {
        gesture = nil
        ticker?.stop()
        guard swipe != nil || swipePosition != nil else { return }
        swipe = nil
        instantPage = true
        swipePosition = nil
        publishShelfRegions()
    }

    /// Read-only state for diagnostics. Banner text and file names stay out; counts and identifiers suffice.
    func inspect() -> [String: Any] {
        [
            "ready": ready, "open": open, "view": page.rawValue, "reducedMotion": reducedMotion,
            "hardware": ["width": Double(hardwareWidth), "height": Double(hardwareHeight), "hideWings": hideHardwareWings, "hideContent": hideNotchContent],
            "size": ["width": Double((open ? openSize : compactSize).width), "height": Double((open ? openSize : compactSize).height)],
            "music": ["availability": music.availability.rawValue, "id": music.id, "playing": music.playing, "pending": music.pending as Any? ?? NSNull(),
                      "hasCover": musicCover != nil, "error": music.error?.code as Any? ?? NSNull(), "source": music.source ?? musicSource],
            "focus": ["phase": focus.phase.rawValue, "activity": focus.activity, "duration": focus.duration, "remaining": focus.remaining,
                      "ready": focus.ready, "locked": focus.locked, "pending": focus.pending as Any? ?? NSNull(), "error": focus.error?.code as Any? ?? NSNull(),
                      "interval": focus.interval.map { ["phase": $0.phase, "state": $0.state] } as Any? ?? NSNull()],
            "shelf": ["ids": shelf.map(\.id), "selected": shelfSelectedIDs, "canUndo": shelfCanUndo, "hasMessage": shelfMessage != nil,
                      "visibleRows": shelfRowFrames.count],
            "focusMenu": focusMenu.map { $0 == .duration ? "duration" : "activity" } as Any? ?? NSNull(),
            "focusMenuMode": focusMenuMode == .list ? "list" : focusMenuMode == .custom ? "custom" : "intervals",
            "shelfMenu": shelfMenu.map { ["ids": $0.ids] } as Any? ?? NSNull(),
            "notification": ["visible": banner != nil, "hasText": banner.map { !$0.title.isEmpty || !$0.body.isEmpty } ?? false, "hasImage": banner?.image != nil],
            "dragging": dragging, "swipePosition": swipePosition.map { Double($0) } as Any? ?? NSNull(), "instantPage": instantPage,
            "errors": [String]()
        ]
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// Accumulated gesture since `begin`, with the 10 pt / 1.6× axis lock shared with `TabSwipeGesture`.
struct SwipeGestureState {
    enum Axis { case horizontal, vertical }
    var x: CGFloat = 0
    var y: CGFloat = 0
    var axis: Axis?
    var index: Int
    var origin: CGFloat?
    var armed = false
    var resisting = false

    mutating func lockAxis() {
        guard axis == nil else { return }
        if abs(y) >= 10, abs(y) >= abs(x) { axis = .vertical }
        else if abs(x) >= 10, abs(x) >= abs(y) * 1.6 { axis = .horizontal }
    }
}

/// One shared strip position for all pages: finger tracking with an iOS-like rubber band, then a
/// critically damped settle that a new gesture can interrupt at its live position and velocity.
struct SwipeTracker {
    var width: CGFloat
    var position: CGFloat
    var velocity: CGFloat = 0
    var inputTime: TimeInterval?
    private var target: CGFloat?
    private var frameTime: CFTimeInterval?
    static let omega: CGFloat = 32

    init(width: CGFloat, position: CGFloat) {
        self.width = max(1, width)
        self.position = position
    }

    /// Returns true when a trackpad tick should fire.
    mutating func track(gesture: inout SwipeGestureState, pages: Int, time: TimeInterval) -> Bool {
        target = nil
        let previous = position
        let proposed = (gesture.origin ?? CGFloat(gesture.index) * width) - gesture.x
        let lower = CGFloat(max(0, gesture.index - 1)) * width
        let upper = CGFloat(min(pages - 1, gesture.index + 1)) * width
        let bound = max(lower, min(upper, proposed))
        let overflow = proposed - bound
        let reach = width * 0.35
        position = bound + (overflow == 0 ? 0 : (overflow > 0 ? 1 : -1)) * reach * (1 - 1 / (abs(overflow) * 0.55 / reach + 1))
        var haptic = false
        let resisting = abs(overflow) >= 40 && (bound == 0 || bound == CGFloat(pages - 1) * width)
        if resisting, !gesture.resisting { haptic = true }
        gesture.resisting = resisting
        if let last = inputTime, time - last > 0, time - last < 0.1 {
            let dt = time - last
            let weight = 1 - exp(-dt / 0.035)
            velocity += CGFloat(weight) * ((position - previous) / CGFloat(dt) - velocity)
        } else {
            velocity = 0
        }
        inputTime = time
        // Mirrors the native 40-point commit threshold; the tick fires only when a neighbour page exists.
        let neighbour = gesture.index + (gesture.x < 0 ? 1 : -1)
        let armed = abs(gesture.x) >= 40 && (0..<pages).contains(neighbour)
        if armed, !gesture.armed { haptic = true }
        gesture.armed = armed
        return haptic
    }

    mutating func beginSettle(to index: Int) {
        let target = CGFloat(index) * width
        let distance = target - position
        let direction: CGFloat = distance < 0 ? -1 : 1
        velocity = direction * max(-width * 5, min(direction * velocity, abs(distance) * Self.omega))
        self.target = target
        frameTime = nil
    }

    /// Advances the settle by one display frame. Returns true when it has come to rest.
    mutating func step(now: CFTimeInterval) -> Bool {
        guard let target else { return true }
        let dt = CGFloat(min(frameTime.map { now - $0 } ?? 1.0 / 120, 0.05))
        frameTime = now
        let displacement = position - target
        let coefficient = velocity + Self.omega * displacement
        let decay = exp(-Self.omega * dt)
        position = target + (displacement + coefficient * dt) * decay
        velocity = (velocity - Self.omega * coefficient * dt) * decay
        return abs(position - target) < 0.5 && abs(velocity) < 15
    }
}

/// Display-synchronized callbacks for the swipe settle.
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: (CFTimeInterval) -> Void

    init(tick: @escaping (CFTimeInterval) -> Void) { self.tick = tick }

    func start() {
        guard link == nil, let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire(_ link: CADisplayLink) { tick(link.timestamp) }
}
