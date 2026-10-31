import AppKit
import Foundation

struct MeldControlError: Error, Equatable {
    let code: String
    let message: String
    static let offline = Self(code: "offline", message: "Meld is not running. Open Meld to connect.")
    static let missing = Self(code: "missingBridge", message: "Rebuild Lilt with its Android bridge to connect Meld.")
    static let wrongDevice = Self(code: "wrongDevice", message: "The Android connection does not belong to Meld.")
    static let unavailable = Self(code: "unavailable", message: "Meld could not be read. Open Meld and try again.")
    static let timeout = Self(code: "notConfirmed", message: "Meld did not confirm the command. Try again or open Meld.")
    static let unsupported = Self(code: "unsupportedAction", message: "This action is not available for the current Meld track.")

    static func bridge(_ code: String) -> Self {
        switch code {
        case "notConfirmed": return .timeout
        case "unsupportedAction": return .unsupported
        case "noSession": return Self(code: code, message: "Choose a song in Meld first.")
        case "ambiguousSession": return Self(code: code, message: "More than one Meld player was found. Open a single player.")
        case "playbackError": return Self(code: code, message: "Meld reported a playback error. Open Meld to choose another version or song.")
        default: return .unavailable
        }
    }
}

enum MeldCommand: String, Codable, CaseIterable { case play, pause, next, previous }

struct MeldReading: Codable, Equatable {
    enum Availability: String, Codable { case checking, ready, offline, empty, unavailable, disabled }
    var availability: Availability = .checking
    var id = ""
    var title = ""
    var artist = ""
    var album = ""
    var queueID = ""
    var duration: Double = 0
    var elapsed: Double = 0
    var playing = false
    var buffering = false
    var speed: Double = 1
    var cover: String?
    var canPlay = false
    var canPause = false
    var canNext = false
    var canPrevious = false
    var confirmedCommand: MeldCommand?

    func allows(_ command: MeldCommand) -> Bool {
        guard availability == .ready else { return false }
        switch command {
        case .play: return canPlay
        case .pause: return canPause
        case .next: return canNext
        case .previous: return canPrevious
        }
    }

    func confirms(_ command: MeldCommand, before: MeldReading) -> Bool {
        guard availability == .ready else { return false }
        // The helper confirms against its fresh pre-command state, avoiding a stale poll comparison.
        if confirmedCommand == command { return true }
        switch command {
        case .play: return playing
        case .pause: return !playing && !buffering
        case .next: return id != before.id || queueID != before.queueID
        case .previous: return id != before.id || queueID != before.queueID || (before.elapsed > 1.5 && elapsed < 1.5)
        }
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256_000,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = raw["availability"] as? String, let availability = Availability(rawValue: value) else { throw MeldControlError.unavailable }
        if availability == .empty { return Self(availability: .empty) }
        if availability == .unavailable { throw MeldControlError.bridge(raw["code"] as? String ?? "") }
        guard availability == .ready, raw["package"] as? String == "com.meld.app" else { throw MeldControlError.unavailable }
        var reading = try JSONDecoder().decode(Self.self, from: data)
        guard !reading.id.isEmpty, !reading.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reading.duration.isFinite, reading.elapsed.isFinite, reading.speed.isFinite else { throw MeldControlError.unavailable }
        reading.duration = max(0, reading.duration)
        reading.elapsed = max(0, reading.elapsed)
        if reading.duration > 0 { reading.elapsed = min(reading.duration, reading.elapsed) }
        reading.speed = max(0, min(4, reading.speed))
        if reading.buffering { reading.playing = false }
        if let cover = reading.cover,
           (!cover.hasPrefix("data:image/jpeg;base64,") || cover.count > 90_000 || Data(base64Encoded: String(cover.dropFirst(23))) == nil) { reading.cover = nil }
        return reading
    }

    var payload: [String: Any] {
        ["availability": availability.rawValue, "id": id, "title": title, "artist": artist, "album": album, "queueID": queueID,
         "duration": duration, "elapsed": elapsed, "playing": playing, "buffering": buffering, "speed": speed,
         "cover": cover as Any? ?? NSNull(), "canPlay": canPlay, "canPause": canPause, "canNext": canNext, "canPrevious": canPrevious]
    }
}

protocol MeldControlling: AnyObject {
    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void)
    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void)
}

final class MeldController: MeldControlling {
    private let queue = DispatchQueue(label: "local.lilt.meld", qos: .utility)
    private let sdk = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk")
    private var bridgePushed = false
    private static let device = "emulator-5580"
    private static let remoteBridge = "/data/local/tmp/lilt-meld-bridge.jar"

    var applicationURL: URL? {
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Meld.app")
        guard Bundle(url: local)?.bundleIdentifier == "de.thimofej.local.meld-android" else { return nil }
        return local
    }

    func openPlayer(completion: @escaping (Result<Void, MeldControlError>) -> Void) {
        queue.async { [self] in
            let result: Result<Void, MeldControlError>
            do {
                let name = try adb(["emu", "avd", "name"], timeout: 2)
                guard String(data: name, encoding: .utf8)?.split(whereSeparator: \.isNewline).first == "Meld" else { throw MeldControlError.wrongDevice }
                let output = try adb(["shell", "am", "start", "-n", "com.meld.app/com.metrolist.music.MainActivityAlias"], timeout: 3)
                guard !(String(data: output, encoding: .utf8) ?? "").contains("Error:") else { throw MeldControlError.unavailable }
                result = .success(())
            } catch let error as MeldControlError { result = .failure(error) }
            catch { result = .failure(.unavailable) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { execute("snapshot", completion: completion) }
    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { execute(command.rawValue, completion: completion) }

    private func execute(_ command: String, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        queue.async { [self] in
            let result: Result<MeldReading, MeldControlError>
            do {
                let name = try adb(["emu", "avd", "name"], timeout: 2)
                guard String(data: name, encoding: .utf8)?.split(whereSeparator: \.isNewline).first == "Meld" else { throw MeldControlError.wrongDevice }
                guard let jar = Bundle.main.url(forResource: "MeldBridge", withExtension: "jar") else { throw MeldControlError.missing }
                if !bridgePushed {
                    _ = try adb(["push", jar.path, Self.remoteBridge], timeout: 3)
                    bridgePushed = true
                }
                let data = try adb(["shell", "CLASSPATH=\(Self.remoteBridge)", "app_process", "/system/bin", "MeldBridge", command], timeout: 5)
                let reading = try MeldReading.decode(data)
                if command != "snapshot", reading.confirmedCommand?.rawValue != command { throw MeldControlError.timeout }
                result = .success(reading)
            } catch let error as MeldControlError {
                if error == .offline || error == .unavailable { bridgePushed = false }
                result = .failure(error)
            } catch { bridgePushed = false; result = .failure(.unavailable) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func adb(_ arguments: [String], timeout: TimeInterval) throws -> Data {
        let executable = sdk.appendingPathComponent("platform-tools/adb")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw MeldControlError.offline }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-s", Self.device] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ADB_SERVER_SOCKET"] = "tcp:localhost:5040"
        environment["ANDROID_USER_HOME"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Meld Android/android").path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let expiration = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiration)
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 256_000 {
                process.terminate()
                break
            }
        }
        process.waitUntilExit()
        expiration.cancel()
        guard data.count <= 256_000, process.terminationStatus == 0 else { throw MeldControlError.offline }
        return data
    }
}

final class MusicCoordinator {
    private(set) var reading = MeldReading()
    private(set) var pending: MeldCommand?
    private(set) var error: MeldControlError?
    var onChange: (() -> Void)?
    private let player: MeldControlling
    private var timer: Timer?
    private var polling = false
    private var generation = UUID()
    private var commandStarted = false

    init(player: MeldControlling) { self.player = player }

    var snapshot: [String: Any] {
        var result = reading.payload
        result["pending"] = pending?.rawValue as Any? ?? NSNull()
        result["error"] = error.map { ["code": $0.code, "message": $0.message] } as Any? ?? NSNull()
        return result
    }

    func startObserving() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.recheck() }
        RunLoop.main.add(timer!, forMode: .common)
        recheck()
    }

    func stop() { timer?.invalidate(); timer = nil; generation = UUID(); pending = nil; polling = false; commandStarted = false }

    func recheck() {
        guard !polling, pending == nil else { return }
        polling = true
        let token = generation
        player.inspect { [weak self] result in
            guard let self, self.generation == token else { return }
            self.polling = false
            if self.pending != nil { self.runPending(); return }
            switch result {
            case .success(let reading): self.reading = reading; if self.error?.code != "notConfirmed" { self.error = nil }
            case .failure(let error): self.fail(error)
            }
            self.onChange?()
        }
    }

    func request(_ command: MeldCommand) {
        guard pending == nil else { return }
        guard reading.allows(command) else { error = .unsupported; onChange?(); return }
        pending = command
        error = nil
        onChange?()
        if !polling { runPending() }
    }

    private func runPending() {
        guard let command = pending, !commandStarted else { return }
        commandStarted = true
        let before = reading
        let token = generation
        player.perform(command) { [weak self] result in
            guard let self, self.generation == token, self.pending == command else { return }
            self.pending = nil
            self.commandStarted = false
            switch result {
            case .success(let reading):
                self.reading = reading
                if !reading.confirms(command, before: before) { self.fail(.timeout) }
                else { self.error = nil }
            case .failure(let error): self.fail(error)
            }
            self.onChange?()
        }
    }

    func report(_ error: MeldControlError) { fail(error); onChange?() }

    private func fail(_ error: MeldControlError) {
        self.error = error
        reading.playing = false
        reading.buffering = false
        reading.availability = error == .offline ? .offline : .unavailable
    }
}

final class DisabledMeld: MeldControlling {
    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { completion(.success(MeldReading(availability: .disabled))) }
    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { completion(.failure(.unavailable)) }
}

final class SimulatedMeld: MeldControlling {
    var reading = MeldReading(availability: .ready, id: "fixture-1", title: "Test song", artist: "Test artist", queueID: "1", duration: 200, elapsed: 12, canPlay: true, canPause: true, canNext: true, canPrevious: true)
    var failure: MeldControlError?
    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        completion(failure.map { .failure($0) } ?? .success(reading))
    }
    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        if let failure { completion(.failure(failure)); return }
        switch command {
        case .play: reading.playing = true
        case .pause: reading.playing = false
        case .next, .previous:
            reading.id = reading.id == "fixture-1" ? "fixture-2" : "fixture-1"
            reading.title = reading.id == "fixture-1" ? "Test song" : "Another test song"
            reading.elapsed = 0
        }
        completion(.success(reading))
    }
}
