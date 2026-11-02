import Foundation
import CoreFoundation

struct LiltSettings: Codable, Equatable {
    var musicSource: MusicSource = .spotify
    var brainFMEnabled = false
    var notificationBannersEnabled = false
    var focusMinutes = 25
    var focusActivity: FocusActivity = .deepWork
    var shelfShortDays = 7
    var shelfLongDays = 30
    var displayID = ""
    var focusSound = true
    var shortcutEnabled = true
    var shortcut = KeyboardShortcut()
    var focusNotificationsEnabled = false

    var payload: [String: Any] {
        ["musicSource": musicSource.rawValue, "sourceName": musicSource.title,
         "notificationBannersEnabled": notificationBannersEnabled, "brainFMEnabled": brainFMEnabled, "focusMinutes": focusMinutes,
         "focusActivity": focusActivity.rawValue, "shelfShortDays": shelfShortDays,
         "shelfLongDays": shelfLongDays, "displayID": displayID,
         "focusSound": focusSound, "shortcutEnabled": shortcutEnabled,
         "shortcut": ["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers],
         "focusNotificationsEnabled": focusNotificationsEnabled]
    }

    func applying(_ changes: [String: Any]) throws -> Self {
        let allowed: Set<String> = ["musicSource", "notificationBannersEnabled", "brainFMEnabled", "focusMinutes", "focusActivity", "shelfShortDays", "shelfLongDays", "displayID", "focusSound", "shortcutEnabled", "shortcut", "focusNotificationsEnabled"]
        guard !changes.isEmpty, Set(changes.keys).isSubset(of: allowed) else { throw SettingsError.invalid }
        var result = self
        if let value = changes["displayID"] {
            guard let id = value as? String, id.isEmpty || UUID(uuidString: id) != nil else { throw SettingsError.invalid }
            result.displayID = id
        }
        if let value = changes["musicSource"] {
            guard let raw = value as? String, let source = MusicSource(rawValue: raw) else { throw SettingsError.invalid }
            result.musicSource = source
        }
        if let value = changes["shortcut"] {
            guard let value = value as? [String: Any], Set(value.keys) == ["keyCode", "modifiers"] else { throw SettingsError.invalidShortcut }
            func integer(_ key: String) throws -> UInt32 {
                guard let number = value[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                      number.doubleValue >= 0, number.doubleValue <= Double(UInt32.max) else { throw SettingsError.invalidShortcut }
                return number.uint32Value
            }
            let shortcut = try KeyboardShortcut(keyCode: integer("keyCode"), modifiers: integer("modifiers"))
            guard shortcut.isValid else { throw SettingsError.invalidShortcut }
            result.shortcut = shortcut
        }
        for key in ["notificationBannersEnabled", "brainFMEnabled", "focusSound", "shortcutEnabled", "focusNotificationsEnabled"] {
            if let value = changes[key] {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw SettingsError.invalid }
                if key == "notificationBannersEnabled" { result.notificationBannersEnabled = number.boolValue }
                else if key == "brainFMEnabled" { result.brainFMEnabled = number.boolValue }
                else if key == "focusSound" { result.focusSound = number.boolValue }
                else if key == "focusNotificationsEnabled" { result.focusNotificationsEnabled = number.boolValue }
                else { result.shortcutEnabled = number.boolValue }
            }
        }
        if let value = changes["focusMinutes"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                  (1...180).contains(number.doubleValue) else { throw SettingsError.invalid }
            result.focusMinutes = number.intValue
        }
        if let value = changes["focusActivity"] {
            guard let raw = value as? String, let activity = FocusActivity(rawValue: raw) else { throw SettingsError.invalid }
            result.focusActivity = activity
        }
        for key in ["shelfShortDays", "shelfLongDays"] {
            if let value = changes[key] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                      (1...3650).contains(number.doubleValue) else { throw SettingsError.invalid }
                if key == "shelfShortDays" { result.shelfShortDays = number.intValue }
                else { result.shelfLongDays = number.intValue }
            }
        }
        return result
    }
}

extension LiltSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationBannersEnabled = container.contains(.notificationBannersEnabled)
            ? try container.decode(Bool.self, forKey: .notificationBannersEnabled) : false
        musicSource = try container.decode(MusicSource.self, forKey: .musicSource)
        brainFMEnabled = try container.decode(Bool.self, forKey: .brainFMEnabled)
        focusMinutes = try container.decode(Int.self, forKey: .focusMinutes)
        focusActivity = try container.decode(FocusActivity.self, forKey: .focusActivity)
        shelfShortDays = try container.decodeIfPresent(Int.self, forKey: .shelfShortDays) ?? 7
        shelfLongDays = try container.decodeIfPresent(Int.self, forKey: .shelfLongDays) ?? 30
        displayID = try container.decodeIfPresent(String.self, forKey: .displayID) ?? ""
        focusSound = try container.decodeIfPresent(Bool.self, forKey: .focusSound) ?? true
        shortcutEnabled = try container.decodeIfPresent(Bool.self, forKey: .shortcutEnabled) ?? true
        shortcut = container.contains(.shortcut) ? try container.decode(KeyboardShortcut.self, forKey: .shortcut) : KeyboardShortcut()
        focusNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusNotificationsEnabled) ?? false
    }
}

struct SettingsError: Error, Equatable {
    let code: String
    let message: String
    static let invalid = Self(code: "invalid", message: "Choose valid settings. Focus duration must be 1 to 180 minutes and Shelf duration 1 to 3650 days.")
    static let storage = Self(code: "storage", message: "Settings could not be saved. Check your disk space and try again.")
    static let musicBusy = Self(code: "music_busy", message: "Wait for the current player command to finish before switching sources.")
    static let loginItem = Self(code: "login_item", message: "Lilt could not change its login item. Move Lilt to Applications and try again.")
    static let loginApproval = Self(code: "login_approval", message: "Allow Lilt in System Settings → General → Login Items.")
    static let focusBusy = Self(code: "focus_busy", message: "End or reset your focus session before changing its defaults or Brain.fm connection.")
    static let invalidShortcut = Self(code: "invalid_shortcut", message: "Choose a key with Control, Option or Command.")
    static let shortcutConflict = Self(code: "shortcut_conflict", message: "Another app uses this shortcut. Your previous shortcut is unchanged.")
    var payload: [String: String] { ["code": code, "message": message] }
}

final class SettingsStore {
    private(set) var value: LiltSettings
    private(set) var error: SettingsError?
    private let file: URL

    init(file: URL, focusFile: URL? = nil) {
        self.file = file
        var defaults = LiltSettings()
        if let focusFile, let data = try? Data(contentsOf: focusFile),
           let session = try? JSONDecoder().decode(FocusSession.self, from: data),
           (60...10800).contains(session.duration), session.duration.isMultiple(of: 60) {
            defaults.focusMinutes = session.duration / 60
            defaults.focusActivity = session.activity
        }
        value = defaults
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try JSONDecoder().decode(LiltSettings.self, from: Data(contentsOf: file))
            guard (1...180).contains(saved.focusMinutes), (1...3650).contains(saved.shelfShortDays),
                  (1...3650).contains(saved.shelfLongDays), saved.shortcut.isValid,
                  saved.displayID.isEmpty || UUID(uuidString: saved.displayID) != nil else { throw SettingsError.invalid }
            value = saved
        } catch {
            self.error = SettingsError(code: "settings_read", message: "Saved settings could not be read. Choose your settings again to save a new configuration.")
        }
    }

    @discardableResult
    func save(_ value: LiltSettings) -> Bool {
        guard (1...180).contains(value.focusMinutes), (1...3650).contains(value.shelfShortDays),
              (1...3650).contains(value.shelfLongDays), value.shortcut.isValid,
              value.displayID.isEmpty || UUID(uuidString: value.displayID) != nil else { error = .invalid; return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            self.value = value
            error = nil
            return true
        } catch {
            self.error = .storage
            return false
        }
    }
}
