import Carbon.HIToolbox

/// ⌃⌥L toggles the notch from any app. Carbon hot keys need no Accessibility permission.
final class GlobalShortcut {
    static let label = "⌃⌥L"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    var isRegistered: Bool { hotKey != nil }

    /// Returns false when macOS refuses the key combination, for example because another app owns it.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled else { unregister(); return true }
        if hotKey != nil { return true }
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
        return RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), id,
                                   GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
