import XCTest
@testable import Lilt

final class AgentInboxTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func testClaudeStopHookUsesLastMessageProjectAndT3Host() throws {
        let input = Data(###"{"hook_event_name":"Stop","cwd":"/Users/me/Lilt","last_assistant_message":"## Done\n**Fixed** the `build`. See [docs](https://x.y)."}"###.utf8)
        let terminal = try XCTUnwrap(AgentInbox.parse(agent: "claude", input: input, environment: [:], now: now))
        XCTAssertEqual(terminal, AgentMessage(source: "Claude Code", project: "Lilt", message: "Done Fixed the build. See docs.",
                                              app: "com.anthropic.claudefordesktop", created: now))
        let t3 = try XCTUnwrap(AgentInbox.parse(agent: "claude", input: input, environment: ["T3CODE_THREAD_ID": "1"], now: now))
        XCTAssertEqual(t3.source, "T3 Code · Claude Code")
        XCTAssertEqual(t3.app, "com.t3tools.t3code")
    }

    func testClaudeFallsBackToTranscriptsLastAssistantText() throws {
        let transcript = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"old"}]}}
        {"type":"user","message":{"content":"next"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"All tests pass."}]}}
        {"type":"system"}
        """
        let input = Data(#"{"cwd":"/tmp/p","transcript_path":"/tmp/t.jsonl"}"#.utf8)
        let message = try XCTUnwrap(AgentInbox.parse(agent: "claude", input: input, environment: [:], now: now) { _ in Data(transcript.utf8) })
        XCTAssertEqual(message.message, "All tests pass.")
        let empty = try XCTUnwrap(AgentInbox.parse(agent: "claude", input: input, environment: [:], now: now) { _ in nil })
        XCTAssertEqual(empty.message, "Finished")
    }

    func testCodexOnlyHandlesFinishedTurnsAndUnknownInputIsIgnored() {
        let done = Data(#"{"type":"agent-turn-complete","cwd":"/w/api","last-assistant-message":"Merged."}"#.utf8)
        XCTAssertEqual(AgentInbox.parse(agent: "codex", input: done, environment: [:], now: now)?.project, "api")
        XCTAssertNil(AgentInbox.parse(agent: "codex", input: Data(#"{"type":"other"}"#.utf8), environment: [:]))
        XCTAssertNil(AgentInbox.parse(agent: "other", input: done, environment: [:]))
        XCTAssertNil(AgentInbox.parse(agent: "claude", input: Data("not json".utf8), environment: [:]))
    }

    func testWriteDrainDeletesFilesAndDropsStaleOrOversized() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fresh = AgentMessage(source: "Codex", project: "p", message: "m", app: "", created: now)
        AgentInbox.write(fresh, to: directory)
        AgentInbox.write(AgentMessage(source: "Codex", project: "old", message: "m", app: "", created: now.addingTimeInterval(-601)), to: directory)
        try Data(repeating: 0x20, count: AgentInbox.fileLimit + 1).write(to: directory.appendingPathComponent("big.json"))
        try Data("{".utf8).write(to: directory.appendingPathComponent("broken.json"))
        XCTAssertEqual(AgentInbox.drain(directory, now: now), [fresh])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testCommandWritesIntoDataDirectoryAndAlwaysSucceeds() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("lilt-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: data) }
        let json = #"{"type":"agent-turn-complete","cwd":"/w/x","last-assistant-message":"ok"}"#
        XCTAssertEqual(AgentInbox.runCommand(["codex", "--data-dir", data.path, json], environment: [:]), 0)
        XCTAssertEqual(AgentInbox.drain(AgentInbox.directory(data)).map(\.project), ["x"])
        XCTAssertEqual(AgentInbox.runCommand(["codex", "--data-dir", data.path], environment: [:]), 0)
        XCTAssertEqual(AgentInbox.runCommand([], environment: [:]), 0)
    }
}

final class SlackMessageTests: XCTestCase {
    func testOnlyDirectMessagesAndMentionsFromOthers() {
        let dm: [String: Any] = ["type": "message", "user": "U2", "channel": "D1", "channel_type": "im", "text": "hi"]
        XCTAssertEqual(SlackMessage.from(event: dm, me: "U1"), SlackMessage(user: "U2", channel: "D1", direct: true, text: "hi"))
        XCTAssertNil(SlackMessage.from(event: dm.merging(["user": "U1"]) { $1 }, me: "U1"))
        XCTAssertNil(SlackMessage.from(event: dm.merging(["subtype": "message_changed"]) { $1 }, me: "U1"))
        XCTAssertNotNil(SlackMessage.from(event: dm.merging(["subtype": "file_share"]) { $1 }, me: "U1"))
        let channel: [String: Any] = ["type": "message", "user": "U2", "channel": "C1", "channel_type": "channel", "text": "lunch?"]
        XCTAssertNil(SlackMessage.from(event: channel, me: "U1"))
        XCTAssertEqual(SlackMessage.from(event: channel.merging(["text": "<@U1> lunch?"]) { $1 }, me: "U1")?.direct, false)
        XCTAssertNil(SlackMessage.from(event: channel.merging(["text": "<@U1> lunch?"]) { $1 }, me: ""))
    }

    func testPlainTextResolvesMentionsLinksAndEscapes() {
        let text = "<@U1> see <https://a.b/c|the doc> &amp; <https://x.y> in <#C9|general> <!here> 1 &lt; 2\n\nok"
        XCTAssertEqual(SlackMessage.mentions(text), ["U1"])
        XCTAssertEqual(SlackMessage.plain(text, names: ["U1": "you"]), "@you see the doc & https://x.y in #general @here 1 < 2 ok")
        XCTAssertEqual(SlackMessage.plain("<@U7|anna> hi", names: [:]), "@anna hi")
    }

    func testTokensAcceptOnlyDocumentedShapes() {
        XCTAssertNotNil(SlackTokens(app: " xapp-1-A0-123-abc\n", user: "xoxp-1-2-3-abc"))
        XCTAssertNil(SlackTokens(app: "xoxp-1", user: "xoxp-1"))
        XCTAssertNil(SlackTokens(app: "xapp-1", user: "xoxb-1"))
        XCTAssertNil(SlackTokens(app: "xapp-1 2", user: "xoxp-1"))
        XCTAssertNil(SlackTokens(app: "xapp-" + String(repeating: "a", count: 300), user: "xoxp-1"))
    }
}
