import AppKit
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MusicSource: String, Codable, CaseIterable {
    case spotify, appleMusic, meld

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .meld: return "Meld"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        case .meld: return "de.thimofej.local.meld-android"
        }
    }

    func error(_ code: String) -> MeldControlError {
        let message: String
        switch code {
        case "notInstalled": message = "Install \(title) to use it with Lilt."
        case "offline": message = "\(title) is not running. Open \(title) to connect."
        case "permission", "permissionRequired": message = "Allow Lilt to control \(title) in System Settings → Privacy & Security → Automation."
        case "empty": message = "Choose a song in \(title) first."
        case "notConfirmed": message = "\(title) did not confirm the command. Open the player and try again."
        case "unsupportedAction": message = "This action is not available for the current \(title) track."
        default: message = "\(title) could not be read. Open the player and try again."
        }
        return MeldControlError(code: code, message: message)
    }
}

protocol DirectMusicTransport: AnyObject {
    var applicationURL: URL? { get }
    var isRunning: Bool { get }
    func permission(ask: Bool) -> OSStatus
    func read(deadline: Date) throws -> MeldReading
    func send(_ command: MeldCommand, deadline: Date) throws
}

final class DirectMusicController: MeldControlling {
    let source: MusicSource
    private let transport: DirectMusicTransport
    private let queue: DispatchQueue
    private let permissionLock = NSLock()
    private var cachedPermissionStatus = OSStatus(errAEEventWouldRequireUserConsent)
    private var refreshingPermission = false

    init(source: MusicSource, transport: DirectMusicTransport? = nil) {
        self.source = source
        self.transport = transport ?? AppleEventMusicTransport(source: source)
        queue = DispatchQueue(label: "local.lilt.music.\(source.rawValue)", qos: .utility)
    }

    var applicationURL: URL? { transport.applicationURL }
    var isRunning: Bool { transport.isRunning }
    var permissionStatus: OSStatus {
        guard transport.isRunning else { return OSStatus(procNotFound) }
        permissionLock.lock()
        let status = cachedPermissionStatus
        let refresh = !refreshingPermission
        refreshingPermission = true
        permissionLock.unlock()
        if refresh {
            queue.async { [self] in
                let latest = transport.permission(ask: false)
                permissionLock.lock()
                cachedPermissionStatus = latest
                refreshingPermission = false
                permissionLock.unlock()
            }
        }
        return status
    }

    func connect(completion: @escaping (Result<Void, MeldControlError>) -> Void) {
        queue.async { [self] in
            let result: Result<Void, MeldControlError>
            do { try validate(ask: true); result = .success(()) }
            catch let error as MeldControlError { result = .failure(error) }
            catch { result = .failure(source.error("unavailable")) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        execute(command: nil, completion: completion)
    }

    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        execute(command: command, completion: completion)
    }

    private func validate(ask: Bool) throws {
        guard source != .meld, transport.applicationURL != nil else { throw source.error("notInstalled") }
        guard transport.isRunning else { throw source.error("offline") }
        let status = transport.permission(ask: ask)
        permissionLock.lock(); cachedPermissionStatus = status; permissionLock.unlock()
        guard status == noErr else {
            throw source.error(status == errAEEventWouldRequireUserConsent ? "permissionRequired" : status == errAEEventNotPermitted ? "permission" : "unavailable")
        }
    }

    private func execute(command: MeldCommand?, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) {
        queue.async { [self] in
            let result: Result<MeldReading, MeldControlError>
            do {
                try validate(ask: false)
                let deadline = Date().addingTimeInterval(command == nil ? 4 : 7)
                let before = try transport.read(deadline: deadline)
                if let command {
                    guard before.allows(command) else { throw source.error("unsupportedAction") }
                    try validate(ask: false)
                    try transport.send(command, deadline: deadline)
                    var after = try transport.read(deadline: deadline)
                    while !after.confirms(command, before: before), Date().addingTimeInterval(0.2) < deadline {
                        Thread.sleep(forTimeInterval: 0.12)
                        after = try transport.read(deadline: deadline)
                    }
                    guard after.confirms(command, before: before) else { throw source.error("notConfirmed") }
                    after.confirmedCommand = command
                    result = .success(after)
                } else { result = .success(before) }
            } catch let error as MeldControlError { result = .failure(error) }
            catch { result = .failure(source.error("unavailable")) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

private func fourCC(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}

struct MusicScriptingDefinition {
    var properties: [String: OSType] = [:]
    var commands: [String: (AEEventClass, AEEventID)] = [:]

    init(data: Data) throws {
        let parser = XMLParser(data: data)
        let reader = DefinitionReader()
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw CocoaError(.fileReadCorruptFile) }
        properties = reader.properties
        commands = reader.commands
    }

    private final class DefinitionReader: NSObject, XMLParserDelegate {
        var properties: [String: OSType] = [:]
        var commands: [String: (AEEventClass, AEEventID)] = [:]

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            guard let name = attributes["name"], let code = attributes["code"] else { return }
            if elementName == "property", code.utf8.count == 4 { properties[name] = fourCC(code) }
            if elementName == "command", code.utf8.count == 8 {
                commands[name] = (fourCC(String(code.prefix(4))), fourCC(String(code.suffix(4))))
            }
        }
    }
}

final class AppleEventMusicTransport: DirectMusicTransport {
    let source: MusicSource
    private var definition: MusicScriptingDefinition?
    private var definitionURL: URL?
    private var artworkID = ""
    private var artwork: String?

    init(source: MusicSource) { self.source = source }

    var applicationURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) { return url }
        let name = source == .appleMusic ? "Music.app" : "Spotify.app"
        let candidates = [URL(fileURLWithPath: "/System/Applications/\(name)"), URL(fileURLWithPath: "/Applications/\(name)"),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name)")]
        return candidates.first { Bundle(url: $0)?.bundleIdentifier == source.bundleIdentifier }
    }
    var isRunning: Bool { runningApplication != nil }
    private var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first { !$0.isTerminated }
    }

    func permission(ask: Bool) -> OSStatus {
        guard let application = runningApplication else { return OSStatus(procNotFound) }
        let target = NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }

    private func scriptingDefinition() throws -> MusicScriptingDefinition {
        guard let appURL = applicationURL, let bundle = Bundle(url: appURL) else { throw source.error("notInstalled") }
        if let definition, definitionURL == appURL { return definition }
        let relative = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String
        let candidates = [relative, source == .appleMusic ? "com.apple.Music.sdef" : "Spotify.sdef", "applescript/Spotify.sdef"].compactMap { $0 }
        for name in candidates {
            guard let resources = bundle.resourceURL else { continue }
            let file = resources.appendingPathComponent(name).standardizedFileURL
            guard file.path.hasPrefix(resources.standardizedFileURL.path + "/"), let data = try? Data(contentsOf: file), data.count <= 1_000_000 else { continue }
            if let parsed = try? MusicScriptingDefinition(data: data) {
                definition = parsed; definitionURL = appURL
                return parsed
            }
        }
        throw source.error("unavailable")
    }

    func read(deadline: Date) throws -> MeldReading {
        let dictionary = try scriptingDefinition()
        guard let application = runningApplication else { throw source.error("offline") }
        let pid = application.processIdentifier
        let stateCode = dictionary.properties["player state"] ?? fourCC("pPlS")
        let trackCode = dictionary.properties["current track"] ?? fourCC("pTrk")
        let state = try get(property: stateCode, pid: pid, deadline: deadline).enumCodeValue
        guard [fourCC("kPSP"), fourCC("kPSp"), fourCC("kPSS"), fourCC("kPSF"), fourCC("kPSR")].contains(state) else { throw source.error("unavailable") }
        let track = propertySpecifier(trackCode)
        let properties: NSAppleEventDescriptor
        do { properties = try get(property: fourCC("pALL"), container: track, pid: pid, deadline: deadline) }
        catch let error as NSError where error.code == -1728 {
            return MeldReading(availability: .empty)
        }
        let position = try get(property: dictionary.properties["player position"] ?? fourCC("pPos"), pid: pid, deadline: deadline).doubleValue
        var result = try Self.reading(source: source, properties: properties, definition: dictionary, state: state, position: position)
        if result.id != artworkID {
            artworkID = result.id
            artwork = nil
            if source == .appleMusic, result.availability == .ready, Date().addingTimeInterval(0.5) < deadline {
                let firstArtwork = NSAppleEventDescriptor.record()
                firstArtwork.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("cArt")), forKeyword: fourCC("want"))
                firstArtwork.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC("indx")), forKeyword: fourCC("form"))
                firstArtwork.setDescriptor(NSAppleEventDescriptor(int32: 1), forKeyword: fourCC("seld"))
                firstArtwork.setDescriptor(track, forKeyword: fourCC("from"))
                if let item = firstArtwork.coerce(toDescriptorType: fourCC("obj ")),
                   let image = try? get(property: fourCC("pRaw"), container: item, pid: pid, deadline: deadline) {
                    artwork = Self.thumbnail(image.data)
                }
            } else if source == .spotify, result.availability == .ready,
                      let artworkCode = dictionary.properties["artwork url"],
                      let rawURL = properties.forKeyword(artworkCode)?.stringValue,
                      let url = URL(string: rawURL), url.scheme == "https", url.host == "i.scdn.co",
                      url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                      Date().addingTimeInterval(0.4) < deadline,
                      let data = MusicArtworkDownload().load(url, timeout: min(0.8, deadline.timeIntervalSinceNow)) {
                artwork = Self.thumbnail(data)
            }
        }
        result.cover = artwork
        return result
    }

    static func reading(source: MusicSource, properties: NSAppleEventDescriptor, definition: MusicScriptingDefinition, state: OSType, position: Double) throws -> MeldReading {
        func value(_ name: String, fallback: String) -> NSAppleEventDescriptor? {
            properties.forKeyword(definition.properties[name] ?? fourCC(fallback))
        }
        let title = value("name", fallback: "pnam")?.stringValue ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return MeldReading(availability: .empty) }
        let artist = value("artist", fallback: "pArt")?.stringValue ?? ""
        let album = value("album", fallback: "pAlb")?.stringValue ?? ""
        let duration = (value("duration", fallback: "pDur")?.doubleValue ?? 0) / (source == .spotify ? 1000 : 1)
        guard duration.isFinite, position.isFinite else { throw source.error("unavailable") }
        let persistent = value("persistent ID", fallback: "pPIS")?.stringValue
        let idDescriptor = value("id", fallback: "ID  ")
        let id = persistent ?? idDescriptor?.stringValue ?? "\(title)\u{1f}\(artist)\u{1f}\(album)"
        return MeldReading(availability: .ready, id: "\(source.rawValue):\(id)", title: title, artist: artist, album: album,
                           queueID: id, duration: max(0, duration), elapsed: max(0, duration > 0 ? min(duration, position) : position),
                           playing: state == fourCC("kPSP"), canPlay: true, canPause: true, canNext: true, canPrevious: true)
    }

    func send(_ command: MeldCommand, deadline: Date) throws {
        let dictionary = try scriptingDefinition()
        let name: String
        switch command { case .play: name = "play"; case .pause: name = "pause"; case .next: name = "next track"; case .previous: name = "previous track" }
        guard let codes = dictionary.commands[name] else { throw source.error("unsupportedAction") }
        guard let application = runningApplication else { throw source.error("offline") }
        _ = try event(eventClass: codes.0, eventID: codes.1, pid: application.processIdentifier, directObject: nil, deadline: deadline)
    }

    private func propertySpecifier(_ property: OSType, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.record()
        descriptor.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC("prop")), forKeyword: fourCC("want"))
        descriptor.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC("prop")), forKeyword: fourCC("form"))
        descriptor.setDescriptor(NSAppleEventDescriptor(typeCode: property), forKeyword: fourCC("seld"))
        descriptor.setDescriptor(container, forKeyword: fourCC("from"))
        return descriptor.coerce(toDescriptorType: fourCC("obj "))!
    }

    private func get(property: OSType, container: NSAppleEventDescriptor = .null(), pid: pid_t, deadline: Date) throws -> NSAppleEventDescriptor {
        try event(eventClass: fourCC("core"), eventID: fourCC("getd"), pid: pid, directObject: propertySpecifier(property, container: container), deadline: deadline)
    }

    private func event(eventClass: AEEventClass, eventID: AEEventID, pid: pid_t, directObject: NSAppleEventDescriptor?, deadline: Date) throws -> NSAppleEventDescriptor {
        guard let application = runningApplication, application.processIdentifier == pid else { throw source.error("offline") }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw source.error("notConfirmed") }
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let directObject { event.setParam(directObject, forKeyword: keyDirectObject) }
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: min(0.8, remaining)) }
        catch let error as NSError {
            if error.code == Int(errAEEventNotPermitted) { throw source.error("permission") }
            throw error
        }
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
            if error.int32Value == errAEEventNotPermitted { throw source.error("permission") }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }

    static func thumbnail(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= 4_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                        kCGImageSourceThumbnailMaxPixelSize: 160,
                                                                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), buffer.length <= 65_000 else { return nil }
        return "data:image/jpeg;base64," + (buffer as Data).base64EncodedString()
    }
}

private final class MusicArtworkDownload: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var data = Data()
    private var successful = false
    private let done = DispatchSemaphore(value: 0)

    func load(_ url: URL, timeout: TimeInterval) -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: url)
        task.resume()
        let finished = done.wait(timeout: .now() + timeout) == .success
        task.cancel()
        session.invalidateAndCancel()
        lock.lock(); defer { lock.unlock() }
        return finished && successful ? data : nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let valid = (response as? HTTPURLResponse)?.statusCode == 200
            && response.mimeType?.hasPrefix("image/") == true
            && response.expectedContentLength <= 2_000_000
        completionHandler(valid ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        let valid = data.count + chunk.count <= 2_000_000
        if valid { data.append(chunk) }
        lock.unlock()
        if !valid { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); successful = error == nil && !data.isEmpty; lock.unlock()
        done.signal()
    }
}
