import Foundation
import Security

/// A Slack message addressed to the user: any direct/group message, or a channel message that mentions them.
struct SlackMessage: Equatable {
    let user: String
    let channel: String
    let direct: Bool
    let text: String

    static func from(event: [String: Any], me: String) -> SlackMessage? {
        guard event["type"] as? String == "message", let user = event["user"] as? String, user != me,
              let channel = event["channel"] as? String, let text = event["text"] as? String else { return nil }
        // Edits, deletions, joins and other system subtypes are not new messages.
        if let subtype = event["subtype"] as? String, !["thread_broadcast", "file_share"].contains(subtype) { return nil }
        let direct = ["im", "mpim"].contains(event["channel_type"] as? String ?? "")
        guard direct || (!me.isEmpty && text.contains("<@\(me)")) else { return nil }
        return SlackMessage(user: user, channel: channel, direct: direct, text: text)
    }

    /// User IDs referenced as `<@U123>` or `<@U123|name>`.
    static func mentions(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "<@([A-Z0-9]+)(?:\\|[^>]*)?>")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Slack mrkdwn to plain text: mentions, channels, links and HTML escapes.
    static func plain(_ text: String, names: [String: String]) -> String {
        let regex = try! NSRegularExpression(pattern: "<([^<>]+)>")
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let parts = text[inner].split(separator: "|", maxSplits: 1).map(String.init)
            let target = parts[0], label = parts.count > 1 ? parts[1] : nil
            if target.hasPrefix("@") { result += "@" + (names[String(target.dropFirst())] ?? label ?? "someone") }
            else if target.hasPrefix("#") { result += "#" + (label ?? "channel") }
            else if target.hasPrefix("!") { result += "@" + (label ?? String(target.dropFirst()).components(separatedBy: "^")[0]) }
            else { result += label ?? target }
            last = whole.upperBound
        }
        result += text[last...]
        return result.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SlackTokens: Codable, Equatable {
    let app: String
    let user: String

    /// Trust boundary: pasted text. Only the documented token shapes are accepted.
    init?(app: String, user: String) {
        let app = app.trimmingCharacters(in: .whitespacesAndNewlines), user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = { (token: String, prefix: String) in
            token.hasPrefix(prefix) && token.count <= 300 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        guard valid(app, "xapp-"), valid(user, "xoxp-") else { return nil }
        self.app = app
        self.user = user
    }
}

/// Tokens live only in the login Keychain, never in settings.json.
enum SlackKeychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "Lilt Slack", kSecAttrAccount as String: "tokens"]

    static func read() -> SlackTokens? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let stored = try? JSONDecoder().decode(SlackTokens.self, from: data) else { return nil }
        return SlackTokens(app: stored.app, user: stored.user)
    }

    static func save(_ tokens: SlackTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// The user's own Slack app over Socket Mode: the app-level token opens the socket, the user token
/// receives the user's message events and reads names and avatars. Message text stays in memory.
/// Called on the main thread; every asynchronous continuation hops back to the main actor.
final class SlackClient {
    enum Status: Equatable {
        case off, connecting, connected(String), failed(String)

        var code: String {
            switch self {
            case .off: return "off"
            case .connecting: return "connecting"
            case .connected: return "connected"
            case .failed: return "failed"
            }
        }

        var message: String {
            switch self {
            case .off: return ""
            case .connecting: return "Connecting…"
            case .connected(let team): return "Connected to \(team)."
            case .failed(let reason): return reason
            }
        }
    }

    private struct SlackError: Error { let code: String }
    private static let fatal: Set<String> = ["invalid_auth", "not_authed", "account_inactive", "token_revoked", "token_expired",
                                             "missing_scope", "not_allowed_token_type", "invalid_token"]

    var onStatus: ((Status) -> Void)?
    var onMessage: ((NotificationBanner) -> Void)?
    private(set) var status = Status.off { didSet { if status != oldValue { onStatus?(status) } } }
    private let session = URLSession(configuration: .ephemeral)
    private var tokens: SlackTokens?
    private var socket: URLSessionWebSocketTask?
    private var me = ""
    private var users: [String: (name: String, image: Data?)] = [:]
    private var channels: [String: String] = [:]
    private var generation = 0
    private var failures = 0
    private var pingTimer: Timer?

    func start(_ tokens: SlackTokens) {
        stop()
        self.tokens = tokens
        connect(generation)
    }

    func stop() {
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        tokens = nil
        users.removeAll()
        channels.removeAll()
        failures = 0
        status = .off
    }

    private func connect(_ generation: Int) {
        guard let tokens, generation == self.generation else { return }
        if case .connected = status {} else { status = .connecting }
        Task { @MainActor in
            do {
                let auth = try await call("auth.test", token: tokens.user)
                let open = try await call("apps.connections.open", token: tokens.app, post: true)
                guard generation == self.generation else { return }
                guard let raw = open["url"] as? String, let url = URL(string: raw), url.scheme == "wss" else { throw SlackError(code: "no_socket_url") }
                me = auth["user_id"] as? String ?? ""
                let socket = session.webSocketTask(with: url)
                self.socket?.cancel(with: .goingAway, reason: nil)
                self.socket = socket
                socket.resume()
                failures = 0
                status = .connected(auth["team"] as? String ?? "Slack")
                schedulePing(socket, generation)
                receive(socket, generation)
            } catch let error as SlackError where Self.fatal.contains(error.code) {
                guard generation == self.generation else { return }
                status = .failed("Slack rejected the tokens (\(error.code)). Check the app's scopes and paste new tokens.")
            } catch {
                reconnect(generation)
            }
        }
    }

    private func reconnect(_ generation: Int) {
        guard generation == self.generation, tokens != nil else { return }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        pingTimer?.invalidate()
        let delays: [TimeInterval] = [1, 3, 10, 30, 60]
        let delay = delays[min(failures, delays.count - 1)]
        failures += 1
        if failures > 2 { status = .failed("Slack is unreachable. Retrying…") }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.connect(generation) }
    }

    private func schedulePing(_ socket: URLSessionWebSocketTask, _ generation: Int) {
        pingTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self, weak socket] _ in
            socket?.sendPing { error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.reconnect(generation) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    @MainActor private func receive(_ socket: URLSessionWebSocketTask, _ generation: Int) {
        Task { @MainActor in
            while generation == self.generation, socket === self.socket {
                guard let message = try? await socket.receive() else {
                    if generation == self.generation, socket === self.socket { reconnect(generation) }
                    return
                }
                guard case .string(let text) = message, let envelope = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
                if let id = envelope["envelope_id"] as? String,
                   let ack = try? JSONSerialization.data(withJSONObject: ["envelope_id": id]), let body = String(data: ack, encoding: .utf8) {
                    socket.send(.string(body)) { _ in }
                }
                switch envelope["type"] as? String {
                case "disconnect":
                    // Slack rotates sockets; open the replacement before this one closes.
                    connect(generation)
                    return
                case "events_api":
                    if let event = (envelope["payload"] as? [String: Any])?["event"] as? [String: Any],
                       let message = SlackMessage.from(event: event, me: me) { present(message, generation) }
                default: break
                }
            }
        }
    }

    @MainActor private func present(_ message: SlackMessage, _ generation: Int) {
        Task { @MainActor in
            let sender = await user(message.user)
            var names: [String: String] = [:]
            for id in SlackMessage.mentions(message.text).prefix(5) { names[id] = id == me ? "you" : await user(id).name }
            let place = message.direct ? "Slack" : "Slack · #\(await channel(message.channel))"
            guard generation == self.generation else { return }
            onMessage?(NotificationBanner(source: place, title: sender.name, body: SlackMessage.plain(message.text, names: names), image: sender.image))
        }
    }

    @MainActor private func user(_ id: String) async -> (name: String, image: Data?) {
        if let cached = users[id] { return cached }
        let info = (try? await call("users.info", token: tokens?.user ?? "", query: ["user": id]))?["user"] as? [String: Any]
        let profile = info?["profile"] as? [String: Any]
        let name = [profile?["display_name"], profile?["real_name"], info?["name"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "Someone"
        var image: Data?
        if let raw = profile?["image_72"] as? String, let url = URL(string: raw), url.scheme == "https",
           let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 { image = data }
        if users.count > 300 { users.removeAll() }
        users[id] = (name, image)
        return (name, image)
    }

    @MainActor private func channel(_ id: String) async -> String {
        if let cached = channels[id] { return cached }
        let name = ((try? await call("conversations.info", token: tokens?.user ?? "", query: ["channel": id]))?["channel"] as? [String: Any])?["name"] as? String ?? "channel"
        channels[id] = name
        return name
    }

    private func call(_ method: String, token: String, post: Bool = false, query: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://slack.com/api/\(method)")!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = post ? "POST" : "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SlackError(code: "invalid_response") }
        guard json["ok"] as? Bool == true else { throw SlackError(code: json["error"] as? String ?? "unknown") }
        return json
    }
}
