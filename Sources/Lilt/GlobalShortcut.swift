import Carbon.HIToolbox
import AppKit

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32 = UInt32(kVK_ANSI_L)
    var modifiers: UInt32 = UInt32(controlKey | optionKey)

    static let modifierMask = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    static let specialKeys: [UInt32: String] = [36: "↩", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    var isValid: Bool {
        (keyCode <= 50 && keyCode != 48 || Self.specialKeys[keyCode] != nil)
            && modifiers & ~Self.modifierMask == 0 && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    var keyLabel: String {
        if let label = Self.specialKeys[keyCode] { return label }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
            var deadKey: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, characters.count, &length, &characters)
            if result == noErr, length > 0 { return String(utf16CodeUnits: characters, count: length).uppercased() }
        }
        return "Key \(keyCode)"
    }

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        for (carbon, cocoa): (Int, NSEvent.ModifierFlags) in [(controlKey, .control), (optionKey, .option), (shiftKey, .shift), (cmdKey, .command)] {
            if modifiers & UInt32(carbon) != 0 { result.insert(cocoa) }
        }
        return result
    }

    init(keyCode: UInt32 = UInt32(kVK_ANSI_L), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = 0
        for (cocoa, carbon): (NSEvent.ModifierFlags, Int) in [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if event.modifierFlags.contains(cocoa) { modifiers |= UInt32(carbon) }
        }
    }
}

/// Carbon hot keys need no Accessibility permission.
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: KeyboardShortcut?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    var isRegistered: Bool { hotKey != nil }

    /// Returns false when macOS refuses the key combination, for example because another app owns it.
    @discardableResult
    func setEnabled(_ enabled: Bool, shortcut: KeyboardShortcut = KeyboardShortcut()) -> Bool {
        guard enabled else { unregister(); return true }
        guard shortcut.isValid else { return false }
        if hotKey != nil, registeredShortcut == shortcut { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return noErr }
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action()
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: OSType(0x4C49_4C54), id: 1) // "LILT"
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                  GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        unregister()
        hotKey = replacement
        registeredShortcut = shortcut
        return true
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredShortcut = nil
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
