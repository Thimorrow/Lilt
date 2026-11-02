import AppKit

// Agent hooks run `Lilt --notify <agent>`: write the message for the running app and exit without UI.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--notify" {
    exit(AgentInbox.runCommand(Array(CommandLine.arguments.dropFirst(2))))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
