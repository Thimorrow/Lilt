import AppKit

// Agent hooks run `Lilt --notify <agent>`: write the message for the running app and exit without UI.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--notify" {
    exit(AgentInbox.runCommand(Array(CommandLine.arguments.dropFirst(2))))
}

// Scripted Slack setup: `Lilt --slack-connect` reads the app-level and the user token as two stdin lines.
// Saving from Lilt's own binary keeps the Keychain item readable by Lilt without a password prompt.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--slack-connect" {
    let lines = String(decoding: FileHandle.standardInput.readData(ofLength: 4_096), as: UTF8.self)
        .split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count == 2, let tokens = SlackTokens(app: lines[0], user: lines[1]), SlackKeychain.save(tokens) else {
        FileHandle.standardError.write(Data("Expected an xapp- and an xoxp- token on two lines.\n".utf8))
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
