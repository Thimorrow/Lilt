import AppKit
import Observation
import SwiftUI

// Native replacement for settings.js and settings-state.mjs. Snapshots are validated here once;
// user intents leave as the same message dictionaries the former web view posted.

enum SettingsSection: String, CaseIterable {
    case music, focus, shelf, notifications, general
    var title: String { rawValue.capitalized }
    var icon: NotchIcon { [.music: .navMusic, .focus: .navFocus, .shelf: .navShelf, .notifications: .navNotifications, .general: .navGeneral][self]! }
}

let musicSources: [(id: String, name: String)] = [("spotify", "Spotify"), ("appleMusic", "Apple Music"), ("meld", "Meld")]

struct SettingsProvider: Equatable {
    var id: String
    var installed: Bool
    var running: Bool
    var availability: String
    var message: String
}

struct SettingsDisplay: Equatable {
    var id: String
    var name: String
}

struct ProviderState: Equatable {
    var status: String
    var label: String
    var connect: Bool
    var open: Bool

    init(status: String, label: String, connect: Bool, open: Bool) {
        self.status = status; self.label = label; self.connect = connect; self.open = open
    }

    init(_ provider: SettingsProvider?) {
        guard let provider else { self.init(status: "checking", label: "Checking connection…", connect: false, open: false); return }
        guard provider.installed else { self.init(status: "missing", label: "Not installed", connect: false, open: false); return }
        guard provider.running else { self.init(status: "offline", label: "Not running", connect: false, open: true); return }
        switch provider.availability {
        case "ready": self.init(status: "ready", label: "Connected", connect: false, open: true)
        case "empty": self.init(status: "ready", label: "Connected · no track selected", connect: false, open: true)
        case "checking": self.init(status: "checking", label: "Checking connection…", connect: true, open: true)
        case "disabled": self.init(status: "disabled", label: "Connection disabled in this test", connect: false, open: false)
        case "permission": self.init(status: "permission", label: "Permission needed", connect: true, open: true)
        case "unavailable", "offline": self.init(status: provider.availability, label: "Not connected", connect: true, open: true)
        default: self.init(status: "unavailable", label: "Connection unavailable", connect: true, open: true)
        }
    }
}

struct SettingsSnapshot {
    var musicSource = "spotify"
    var brainFMEnabled = false
    var notificationBannersEnabled = false
    var notificationCaptureStatus = "disabled"
    var notificationCaptureMessage = "Off. No other apps are read."
    var slackStatus = "off"
    var slackMessage = ""
    var focusMinutes = 25
    var focusActivity = "deepWork"
    var shelfShortDays = 7
    var shelfLongDays = 30
    var displayID = ""
    var displays: [SettingsDisplay] = []
    var focusSound = true
    var focusNotificationsEnabled = false
    var focusNotificationStatus = "off"
    var focusNotificationRequesting = false
    var shortcutEnabled = true
    var openAtLogin = false
    var shortcutLabel = "⌃⌥L"
    var shortcut: (keyCode: Int, modifiers: Int)?
    var shortcutConflict = false
    var displayUnavailable = false
    var musicBusy = false
    var focusLocked = false
    var providers: [SettingsProvider] = []
    var brainFMInstalled = false
    var brainFMPermission = false
    var error: NotchMessage?
    var saved = false
    var ready = false

    init() {}

    init?(_ raw: Any?) {
        guard let value = raw as? [String: Any] else { return nil }
        func flag(_ key: String, in dictionary: [String: Any]? = nil) -> Bool? {
            guard let number = (dictionary ?? value)[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        func integer(_ key: String, _ range: ClosedRange<Int>, in dictionary: [String: Any]? = nil) -> Int? {
            guard let number = (dictionary ?? value)[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  number.doubleValue >= Double(range.lowerBound), number.doubleValue <= Double(range.upperBound) else { return nil }
            return number.intValue
        }
        /// Optional fields may be absent (older snapshots) but never malformed.
        func optional<T>(_ key: String, _ parse: () -> T?) -> T?? {
            guard value[key] != nil else { return .some(nil) }
            guard let parsed = parse() else { return nil }
            return .some(parsed)
        }
        guard let source = value["musicSource"] as? String, musicSources.contains(where: { $0.id == source }),
              let activity = value["focusActivity"] as? String, ["deepWork", "lightWork"].contains(activity),
              let minutes = integer("focusMinutes", 1...180),
              let shortDays = integer("shelfShortDays", 1...3650), let longDays = integer("shelfLongDays", 1...3650),
              let brainFMEnabled = flag("brainFMEnabled"), let focusSound = flag("focusSound"),
              let shortcutEnabled = flag("shortcutEnabled"), let openAtLogin = flag("openAtLogin"),
              let shortcutConflict = flag("shortcutConflict"), let musicBusy = flag("musicBusy"),
              let focusLocked = flag("focusLocked"), let saved = flag("saved"),
              let shortcutLabel = value["shortcutLabel"] as? String,
              let providers = value["providers"] as? [Any],
              let displayID = value["displayID"] as? String, let displays = value["displays"] as? [Any],
              let displayUnavailable = flag("displayUnavailable"),
              let brainFM = value["brainFM"] as? [String: Any],
              let installed = flag("installed", in: brainFM), let permission = flag("permission", in: brainFM),
              let rawError = value["error"], rawError is NSNull || NotchMessage(rawError) != nil,
              let banners = optional("notificationBannersEnabled", { flag("notificationBannersEnabled") }),
              let captureStatus = optional("notificationCaptureStatus", {
                  (value["notificationCaptureStatus"] as? String).flatMap { ["disabled", "diagnostic", "suspended", "permission", "active"].contains($0) ? $0 : nil }
              }),
              let captureMessage = optional("notificationCaptureMessage", { value["notificationCaptureMessage"] as? String }),
              let focusNotifications = optional("focusNotificationsEnabled", { flag("focusNotificationsEnabled") }),
              let focusNotificationStatus = optional("focusNotificationStatus", {
                  (value["focusNotificationStatus"] as? String).flatMap { ["off", "allowed", "permission", "denied", "error", "diagnostic"].contains($0) ? $0 : nil }
              }),
              let requesting = optional("focusNotificationRequesting", { flag("focusNotificationRequesting") }),
              let shortcut = optional("shortcut", { () -> (keyCode: Int, modifiers: Int)? in
                  guard let raw = value["shortcut"] as? [String: Any], let keyCode = integer("keyCode", 0...127, in: raw),
                        let modifiers = integer("modifiers", 0...0xffff_ffff, in: raw),
                        modifiers & ~6912 == 0, modifiers & 6400 != 0 else { return nil }
                  return (keyCode, modifiers)
              }) else { return nil }
        musicSource = source
        focusActivity = activity
        focusMinutes = minutes
        shelfShortDays = shortDays
        shelfLongDays = longDays
        self.brainFMEnabled = brainFMEnabled
        self.focusSound = focusSound
        self.shortcutEnabled = shortcutEnabled
        self.openAtLogin = openAtLogin
        self.shortcutConflict = shortcutConflict
        self.musicBusy = musicBusy
        self.focusLocked = focusLocked
        self.saved = saved
        self.shortcutLabel = shortcutLabel
        self.displayID = displayID
        self.displayUnavailable = displayUnavailable
        brainFMInstalled = installed
        brainFMPermission = permission
        error = NotchMessage(rawError)
        if let banners { notificationBannersEnabled = banners }
        if let captureStatus { notificationCaptureStatus = captureStatus }
        if let captureMessage { notificationCaptureMessage = captureMessage }
        if let slack = value["slackStatus"] as? String, ["off", "connecting", "connected", "failed"].contains(slack) { slackStatus = slack }
        slackMessage = value["slackMessage"] as? String ?? ""
        if let focusNotifications { focusNotificationsEnabled = focusNotifications }
        if let focusNotificationStatus { self.focusNotificationStatus = focusNotificationStatus }
        if let requesting { focusNotificationRequesting = requesting }
        self.shortcut = shortcut
        // Malformed entries are dropped rather than becoming selectable sources or displays.
        self.providers = providers.compactMap { item in
            guard let item = item as? [String: Any], let id = item["id"] as? String, musicSources.contains(where: { $0.id == id }),
                  let installed = flag("installed", in: item), let running = flag("running", in: item),
                  let availability = item["availability"] as? String else { return nil }
            return SettingsProvider(id: id, installed: installed, running: running, availability: availability, message: item["message"] as? String ?? "")
        }
        self.displays = displays.compactMap { item in
            guard let item = item as? [String: Any], let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return SettingsDisplay(id: id, name: name)
        }
        ready = true
    }

    func bool(_ key: String) -> Bool {
        switch key {
        case "brainFMEnabled": return brainFMEnabled
        case "notificationBannersEnabled": return notificationBannersEnabled
        case "focusSound": return focusSound
        case "focusNotificationsEnabled": return focusNotificationsEnabled
        case "shortcutEnabled": return shortcutEnabled
        case "openAtLogin": return openAtLogin
        default: return false
        }
    }

    func days(_ key: String) -> Int { key == "shelfLongDays" ? shelfLongDays : shelfShortDays }

    /// Whether a requested change already equals the confirmed value.
    func matches(_ key: String, _ value: Any) -> Bool {
        switch key {
        case "musicSource": return value as? String == musicSource
        case "focusActivity": return value as? String == focusActivity
        case "displayID": return value as? String == displayID
        case "focusMinutes": return value as? Int == focusMinutes
        case "shelfShortDays", "shelfLongDays": return value as? Int == days(key)
        case "shortcut":
            guard let value = value as? [String: Int], let shortcut else { return false }
            return value["keyCode"] == shortcut.keyCode && value["modifiers"] == shortcut.modifiers
        default: return value as? Bool == bool(key)
        }
    }

    var inspect: [String: Any] {
        ["musicSource": musicSource, "brainFMEnabled": brainFMEnabled, "notificationBannersEnabled": notificationBannersEnabled,
         "notificationCaptureStatus": notificationCaptureStatus, "slackStatus": slackStatus, "focusMinutes": focusMinutes, "focusActivity": focusActivity,
         "shelfShortDays": shelfShortDays, "shelfLongDays": shelfLongDays, "displayID": displayID, "displays": displays.map(\.id),
         "focusSound": focusSound, "focusNotificationsEnabled": focusNotificationsEnabled, "focusNotificationStatus": focusNotificationStatus,
         "focusNotificationRequesting": focusNotificationRequesting, "shortcutEnabled": shortcutEnabled, "openAtLogin": openAtLogin,
         "shortcutLabel": shortcutLabel, "shortcut": shortcut.map { ["keyCode": $0.keyCode, "modifiers": $0.modifiers] } as Any? ?? NSNull(),
         "shortcutConflict": shortcutConflict, "displayUnavailable": displayUnavailable, "musicBusy": musicBusy, "focusLocked": focusLocked,
         "providers": providers.map { ["id": $0.id, "installed": $0.installed, "running": $0.running, "availability": $0.availability] },
         "brainFM": ["installed": brainFMInstalled, "permission": brainFMPermission],
         "error": error.map { ["code": $0.code, "message": $0.message] } as Any? ?? NSNull(), "saved": saved, "ready": ready]
    }
}

struct MenuOption: Equatable {
    var value: String
    var label: String
}

enum SettingsValues {
    static let retentionPresets = ["shelfShortDays": [1, 3, 7, 14, 30], "shelfLongDays": [7, 30, 90, 180, 365]]

    static func daysLabel(_ days: Int) -> String { days == 1 ? "1 day" : "\(days) days" }

    /// Menu choices for a setting; a stored value outside the presets stays listed so it is never hidden.
    static func menuOptions(_ key: String, _ state: SettingsSnapshot) -> [MenuOption] {
        if key == "displayID" {
            var options = [MenuOption(value: "", label: "Automatic")] + state.displays.map { MenuOption(value: $0.id, label: $0.name) }
            if !state.displayID.isEmpty, !options.contains(where: { $0.value == state.displayID }) {
                options.append(MenuOption(value: state.displayID, label: "Disconnected display"))
            }
            return options
        }
        return Set((retentionPresets[key] ?? []) + [state.days(key)]).sorted().map { MenuOption(value: String($0), label: daysLabel($0)) }
    }

    static func wholeNumber(_ raw: String, _ range: ClosedRange<Int>) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value.isFinite, value.rounded() == value,
              value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }

    static func duration(_ raw: String) -> Int? { wholeNumber(raw, 1...180) }
    static func retention(_ raw: String) -> Int? { wholeNumber(raw, 1...3650) }
}

@Observable
final class SettingsModel {
    var state = SettingsSnapshot()
    var section = SettingsSection.music
    /// Optimistic request until native confirms; clearing it rolls the shown values back.
    var requested: [String: Any]?
    var localError: String?
    /// Unsaved text in the duration editor; nil when it shows the confirmed value.
    var durationDraft: String?
    var durationError: String?
    var retentionDrafts: [String: String] = [:]
    var retentionCustom: Set<String> = []
    var retentionErrors: [String: String] = [:]
    var openMenu: String?
    var menuHighlight: Int?
    var recordingShortcut = false
    var shortcutRecordingError = ""
    var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Top-left window frames of menu triggers (by setting key) and of the open menu (`menu`), for outside clicks.
    @ObservationIgnored var menuFrames: [String: CGRect] = [:]

    @ObservationIgnored var post: ([String: Any]) -> Void = { _ in }
    @ObservationIgnored var requestTimeout: TimeInterval = 8
    @ObservationIgnored private var keyboardUpdate = false
    @ObservationIgnored private var requestTimer: DispatchWorkItem?

    func motion(_ animation: Animation) -> Animation? { reducedMotion ? nil : animation }

    /// Applies a change without implicit animations when motion is reduced or the change came from the keyboard.
    private func update(animated: Bool = true, _ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated || reducedMotion
        withTransaction(transaction, change)
    }

    // MARK: Native → UI

    func receive(_ method: String, _ value: Any) {
        switch method {
        case "receiveSnapshot": receiveSnapshot(value)
        case "configure":
            if let reduce = (value as? [String: Any])?["reducedMotion"] as? Bool { reducedMotion = reduce }
        case "receiveShortcutRecording":
            guard let value = value as? [String: Any], let recording = value["recording"] as? Bool else { return }
            recordingShortcut = recording
            shortcutRecordingError = value["error"] as? String ?? ""
        default: break
        }
    }

    private func receiveSnapshot(_ value: Any) {
        guard let snapshot = SettingsSnapshot(value) else { return }
        let previousError = state.error?.message
        update(animated: !keyboardUpdate) {
            state = snapshot
            if let requested, snapshot.error != nil || requested.allSatisfy({ snapshot.matches($0.key, $0.value) }) {
                requestTimer?.cancel()
                if snapshot.error == nil {
                    if requested["focusMinutes"] != nil { durationDraft = nil }
                    for key in requested.keys { retentionDrafts[key] = nil; retentionCustom.remove(key) }
                }
                self.requested = nil
                localError = nil
            }
        }
        if requested == nil { keyboardUpdate = false }
        if let message = snapshot.error?.message, message != previousError { announce(message) }
    }

    // MARK: Derived state

    func shown<T>(_ key: String, _ confirmed: T) -> T { requested?[key] as? T ?? confirmed }
    func shownBool(_ key: String) -> Bool { shown(key, state.bool(key)) }

    var musicDisabled: Bool { !state.ready || state.musicBusy || requested != nil }
    var focusDisabled: Bool {
        !state.ready || state.focusLocked || (requested.map { !$0.keys.allSatisfy { $0 == "brainFMEnabled" } } ?? false)
    }
    func toggleDisabled(_ key: String) -> Bool { !state.ready || (requested != nil && requested?[key] == nil) }
    var busy: Bool { !state.ready || requested != nil }
    var provider: SettingsProvider? { state.providers.first { $0.id == state.musicSource } }
    var errorMessage: String? { localError ?? state.error?.message }
    var saveStatus: String { !state.ready ? "loading" : errorMessage != nil ? "error" : requested != nil ? "pending" : "saved" }
    var saveLabel: String {
        ["loading": "Loading…", "error": "Not saved", "pending": "Saving…", "saved": state.saved ? "Saved" : "Ready"][saveStatus]!
    }
    var shortcutIsDefault: Bool { state.shortcut.map { $0.keyCode == 37 && $0.modifiers == 6144 } ?? false }
    var focusNotificationNote: String {
        let status = state.focusNotificationStatus
        if status == "diagnostic", !state.focusNotificationsEnabled { return "" }
        return ["denied": "Notifications are blocked in System Settings → Notifications → Lilt.",
                "error": "The timer notification could not be scheduled.",
                "diagnostic": "System notifications are disabled in this test."][status] ?? ""
    }
    var brainFMMessage: String {
        !state.brainFMInstalled ? "Install the Brain.fm Mac app to use focus music."
            : !state.brainFMPermission ? "Allow Lilt in Accessibility to control Brain.fm." : "Brain.fm is ready."
    }

    func menuOptions(_ key: String) -> [MenuOption] {
        var shownState = state
        if key == "displayID" { shownState.displayID = shown(key, state.displayID) }
        else if key == "shelfLongDays" { shownState.shelfLongDays = shown(key, state.shelfLongDays) }
        else { shownState.shelfShortDays = shown(key, state.shelfShortDays) }
        return SettingsValues.menuOptions(key, shownState)
    }

    func menuValue(_ key: String) -> String { key == "displayID" ? shown(key, state.displayID) : String(shown(key, state.days(key))) }
    func menuLabel(_ key: String) -> String { menuOptions(key).first { $0.value == menuValue(key) }?.label ?? "" }
    /// Retention menus end with a "Custom…" entry, represented by the value `custom`.
    func menuItems(_ key: String) -> [MenuOption] {
        menuOptions(key) + (key == "displayID" ? [] : [MenuOption(value: "custom", label: "Custom…")])
    }

    // MARK: Sections

    func setSection(_ next: SettingsSection, animate: Bool = true) {
        if recordingShortcut { post(["action": "shortcutCancelRecording"]) }
        closeMenu(animate: false)
        update(animated: animate) { section = next }
    }

    func moveSection(by offset: Int) {
        let all = SettingsSection.allCases
        setSection(all[(all.firstIndex(of: section)! + offset + all.count) % all.count], animate: false)
    }

    // MARK: Changes

    func sendChanges(_ changes: [String: Any], keyboard: Bool = false) {
        guard state.ready, requested == nil else { return }
        let locked = changes.keys.contains { key in
            key == "musicSource" ? state.musicBusy : ["focusMinutes", "focusActivity", "brainFMEnabled"].contains(key) && state.focusLocked
        }
        guard !locked, !changes.allSatisfy({ state.matches($0.key, $0.value) }) else { return }
        localError = nil
        requested = changes
        keyboardUpdate = keyboard
        post(["action": "settingsUpdate", "changes": changes])
        requestTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.requested != nil else { return }
            self.requested = nil
            self.keyboardUpdate = false
            self.localError = "Lilt did not confirm the change. Try again."
            self.announce(self.localError!)
        }
        requestTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + requestTimeout, execute: timer)
    }

    func selectSource(_ id: String, keyboard: Bool = false) { sendChanges(["musicSource": id], keyboard: keyboard) }
    func selectActivity(_ id: String, keyboard: Bool = false) { sendChanges(["focusActivity": id], keyboard: keyboard) }
    func toggle(_ key: String, keyboard: Bool = false) { sendChanges([key: !state.bool(key)], keyboard: keyboard) }

    func toggleFocusNotifications() {
        if state.focusNotificationsEnabled { sendChanges(["focusNotificationsEnabled": false]) }
        else { post(["action": "focusNotificationPermission"]) }
    }

    func act(_ action: String) { post(["action": action]) }

    // MARK: Duration

    func choosePreset(_ minutes: Int) {
        durationDraft = nil
        durationError = nil
        sendChanges(["focusMinutes": minutes])
    }

    /// Text fields echo programmatic values back; an unchanged echo must not clear a validation error.
    func editDuration(_ text: String) {
        guard text != (durationDraft ?? String(state.focusMinutes)) else { return }
        durationDraft = text
        durationError = nil
    }

    func commitDuration(keyboard: Bool = false) {
        guard let draft = durationDraft else { return }
        guard let minutes = SettingsValues.duration(draft) else {
            durationError = "Choose a whole number from 1 to 180."
            announce(durationError!)
            return
        }
        if minutes == state.focusMinutes { durationDraft = nil; return }
        sendChanges(["focusMinutes": minutes], keyboard: keyboard)
    }

    func cancelDuration() {
        durationDraft = nil
        durationError = nil
    }

    // MARK: Shelf retention

    func editRetention(_ key: String, _ text: String) {
        guard text != (retentionDrafts[key] ?? String(state.days(key))) else { return }
        retentionDrafts[key] = text
        retentionErrors[key] = nil
    }

    func commitRetention(_ key: String) {
        let raw = retentionDrafts[key] ?? String(state.days(key))
        guard let days = SettingsValues.retention(raw) else {
            retentionErrors[key] = "Choose a whole number from 1 to 3650."
            announce(retentionErrors[key]!)
            return
        }
        retentionErrors[key] = nil
        if days == state.days(key) { retentionDrafts[key] = nil; retentionCustom.remove(key); return }
        sendChanges([key: days], keyboard: true)
    }

    func cancelRetention(_ key: String) {
        retentionDrafts[key] = nil
        retentionCustom.remove(key)
        retentionErrors[key] = nil
    }

    // MARK: Menus

    func toggleMenu(_ key: String, last: Bool = false, animate: Bool = true) {
        if openMenu == key { closeMenu(animate: animate); return }
        closeMenu(animate: false)
        guard !busy else { return }
        let items = menuItems(key)
        update(animated: animate) {
            openMenu = key
            menuHighlight = last ? items.count - 1 : items.firstIndex { $0.value == menuValue(key) } ?? 0
        }
    }

    func closeMenu(animate: Bool = true) {
        guard openMenu != nil else { return }
        update(animated: animate) {
            openMenu = nil
            menuHighlight = nil
        }
    }

    func chooseMenuItem(_ value: String, keyboard: Bool = false) {
        guard let key = openMenu else { return }
        if value == "custom" {
            closeMenu(animate: false)
            retentionCustom.insert(key)
            retentionDrafts[key] = nil
            return
        }
        closeMenu(animate: !keyboard)
        sendChanges([key: key == "displayID" ? value : Int(value) ?? 0], keyboard: keyboard)
    }

    func menuContains(_ point: CGPoint) -> Bool {
        guard let key = openMenu else { return false }
        return [menuFrames[key], menuFrames["menu"]].contains { $0?.contains(point) == true }
    }

    /// Keyboard handling while a menu is open. Returns true when the key was consumed.
    func menuKey(_ key: String) -> Bool {
        guard let menu = openMenu else { return false }
        let items = menuItems(menu)
        let index = menuHighlight ?? 0
        switch key {
        case "down": menuHighlight = (index + 1) % items.count
        case "up": menuHighlight = (index - 1 + items.count) % items.count
        case "home": menuHighlight = 0
        case "end": menuHighlight = items.count - 1
        case "return": chooseMenuItem(items[index].value, keyboard: true)
        case "escape": closeMenu()
        case "tab": closeMenu(animate: false); return false
        default: return false
        }
        return true
    }

    // MARK: Shortcut

    func toggleShortcutRecording() { post(["action": recordingShortcut ? "shortcutCancelRecording" : "shortcutRecord"]) }
    func resetShortcut() { sendChanges(["shortcut": ["keyCode": 37, "modifiers": 6144]]) }

    /// Escape dismisses the innermost transient state first, then closes the window.
    func escape() {
        if openMenu != nil { closeMenu() }
        else if durationDraft != nil || durationError != nil { cancelDuration() }
        else if !retentionCustom.isEmpty { retentionCustom.forEach(cancelRetention) }
        else { post(["action": "settingsClose"]) }
    }

    func inspect() -> [String: Any] {
        // Typed separately: older Swift toolchains time out inferring this literal inline.
        let local: [String: Any] = [
            "section": section.rawValue, "requested": requested as Any? ?? NSNull(), "localError": localError as Any? ?? NSNull(),
            "recordingShortcut": recordingShortcut, "shortcutRecordingError": shortcutRecordingError, "reducedMotion": reducedMotion,
            "openMenu": openMenu as Any? ?? NSNull(), "menuItems": openMenu.map { menuItems($0).map(\.value) } as Any? ?? NSNull(),
            "durationDraft": durationDraft as Any? ?? NSNull(), "durationError": durationError as Any? ?? NSNull(),
            "retentionCustom": retentionCustom.sorted(), "retentionErrors": retentionErrors,
            "saveStatus": saveStatus, "saveLabel": saveLabel, "errors": [String]()
        ]
        return state.inspect.merging(local) { $1 }
    }

    private func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
