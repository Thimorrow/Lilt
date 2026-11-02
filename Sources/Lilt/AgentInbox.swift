import Foundation

/// A finished coding-agent turn. `Lilt --notify <agent>` writes one small file into
/// `<data dir>/inbox/`; the running app shows it once and deletes it.
struct AgentMessage: Codable, Equatable {
    var source: String
    var project: String
    var message: String
    /// Bundle identifier whose app icon the banner shows.
    var app: String
    var created: Date
}

enum AgentInbox {
    static let fileLimit = 64_000

    static func directory(_ dataDirectory: URL) -> URL { dataDirectory.appendingPathComponent("inbox", isDirectory: true) }

    // MARK: Command line (runs inside the agent's hook, never blocks or fails it)

    /// `arguments` follow `--notify`: `<claude|codex> [--data-dir DIR] [json]`.
    static func runCommand(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) -> Int32 {
        var args = arguments
        guard !args.isEmpty else { return 0 }
        let agent = args.removeFirst()
        var data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lilt", isDirectory: true)
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            data = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            args.removeSubrange(index...index + 1)
        }
        // Codex passes its JSON as the last argument; Claude Code writes it to stdin and closes it.
        let input: Data
        if let json = args.last(where: { $0.hasPrefix("{") }) { input = Data(json.utf8) }
        else if agent == "claude" { input = FileHandle.standardInput.readData(ofLength: 2_000_000) }
        else { return 0 }
        if let message = parse(agent: agent, input: input, environment: environment) { write(message, to: directory(data)) }
        return 0
    }

    static func parse(agent: String, input: Data, environment: [String: String], now: Date = Date(),
                      transcript: (URL) -> Data? = readTail) -> AgentMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return nil }
        let name: String
        let app: String
        var text: String?
        switch agent {
        case "claude":
            name = "Claude Code"
            app = "com.anthropic.claudefordesktop"
            text = json["last_assistant_message"] as? String
            if text?.isEmpty ?? true, let path = json["transcript_path"] as? String {
                text = transcript(URL(fileURLWithPath: path)).flatMap(lastAssistantText)
            }
        case "codex":
            guard json["type"] as? String == "agent-turn-complete" else { return nil }
            name = "Codex"
            app = "com.openai.codex"
            text = json["last-assistant-message"] as? String
        default:
            return nil
        }
        let t3 = environment["T3CODE_THREAD_ID"] != nil
        let cwd = json["cwd"] as? String ?? ""
        let message = plain(text ?? "")
        return AgentMessage(source: t3 ? "T3 Code · \(name)" : name,
                            project: cwd.isEmpty ? name : URL(fileURLWithPath: cwd).lastPathComponent,
                            message: message.isEmpty ? "Finished" : String(message.prefix(1_000)),
                            app: t3 ? "com.t3tools.t3code" : app, created: now)
    }

    /// Claude Code transcript: JSON lines; the last assistant entry's text blocks are the final answer.
    static func lastAssistantText(_ data: Data) -> String? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  entry["type"] as? String == "assistant",
                  let content = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return nil
    }

    static func readTail(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        return try? handle.readToEnd()
    }

    /// Markdown to one readable line: the banner has two lines and no rich text.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        for (pattern, template) in [("```[\\s\\S]*?```", " "), ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
                                    ("(?m)^\\s{0,3}(#{1,6}|[-*+]|\\d+\\.|>)\\s+", ""), ("\\*\\*|__|`", ""), ("\\s+", " ")] {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ message: AgentMessage, to directory: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let data = try? encoder.encode(message) else { return }
        // Write then rename so the app never reads a half-written file. The prefix doubles as the marker
        // `scripts/agent-hook.sh` looks for before calling a Lilt binary with `--notify`.
        let temporary = directory.appendingPathComponent(".lilt-agent-inbox-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent("\(UUID().uuidString).json"))
        } catch { try? FileManager.default.removeItem(at: temporary) }
    }

    // MARK: App side

    /// Oldest first; every read file is deleted. Messages older than ten minutes (Lilt was not running) are dropped.
    static func drain(_ directory: URL, now: Date = Date(), limit: Int = 5) -> [AgentMessage] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return [] }
        let created = { (url: URL) in (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var messages: [AgentMessage] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { created($0) < created($1) }).prefix(limit) {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= fileLimit,
                  let data = try? Data(contentsOf: file), let message = try? decoder.decode(AgentMessage.self, from: data),
                  abs(now.timeIntervalSince(message.created)) < 600 else { continue }
            messages.append(message)
        }
        return messages
    }
}
