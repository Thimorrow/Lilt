import Foundation
import CoreFoundation

struct LiltSettings: Codable, Equatable {
    var musicSource: MusicSource = .spotify
    var brainFMEnabled = false
    var focusMinutes = 25
    var focusActivity: FocusActivity = .deepWork

    var payload: [String: Any] {
        ["musicSource": musicSource.rawValue, "sourceName": musicSource.title,
         "brainFMEnabled": brainFMEnabled, "focusMinutes": focusMinutes,
         "focusActivity": focusActivity.rawValue]
    }

    func applying(_ changes: [String: Any]) throws -> Self {
        let allowed: Set<String> = ["musicSource", "brainFMEnabled", "focusMinutes", "focusActivity"]
        guard !changes.isEmpty, Set(changes.keys).isSubset(of: allowed) else { throw SettingsError.invalid }
        var result = self
        if let value = changes["musicSource"] {
            guard let raw = value as? String, let source = MusicSource(rawValue: raw) else { throw SettingsError.invalid }
            result.musicSource = source
        }
        if let value = changes["brainFMEnabled"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw SettingsError.invalid }
            result.brainFMEnabled = number.boolValue
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
        return result
    }
}

struct SettingsError: Error, Equatable {
    let code: String
    let message: String
    static let invalid = Self(code: "invalid", message: "Choose a music source, a focus activity and a duration from 1 to 180 minutes.")
    static let storage = Self(code: "storage", message: "Settings could not be saved. Check your disk space and try again.")
    static let musicBusy = Self(code: "music_busy", message: "Wait for the current player command to finish before switching sources.")
    static let focusBusy = Self(code: "focus_busy", message: "End or reset your focus session before changing its defaults or Brain.fm connection.")
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
            guard (1...180).contains(saved.focusMinutes) else { throw SettingsError.invalid }
            value = saved
        } catch {
            self.error = SettingsError(code: "settings_read", message: "Saved settings could not be read. Choose your settings again to save a new configuration.")
        }
    }

    @discardableResult
    func save(_ value: LiltSettings) -> Bool {
        guard (1...180).contains(value.focusMinutes) else { error = .invalid; return false }
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
