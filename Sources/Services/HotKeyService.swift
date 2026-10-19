import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey with Carbon's RegisterEventHotKey (no permissions needed)
/// and forwards both pressed and released events, which push-to-talk relies on.
final class HotKeyService {
    static let shared = HotKeyService()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                HotKeyService.shared.onPress?()
            } else {
                HotKeyService.shared.onRelease?()
            }
            return noErr
        }, types.count, &types, nil, &handlerRef)
    }

    /// Registers the hotkey; returns a user-facing error message on failure.
    func register(keyCode: Int, modifiers: Int) -> String? {
        unregister()
        if Self.isSystemShortcut(keyCode: keyCode, modifiers: modifiers) {
            return "This shortcut is already used by macOS. Pick another one."
        }
        let id = EventHotKeyID(signature: OSType(0x4853_5754), id: 1) // 'HSWT'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        switch status {
        case noErr: return nil
        case OSStatus(eventHotKeyExistsErr): return "This shortcut is already taken by another app."
        default: return "Couldn't register the shortcut (error \(status))."
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Checks the enabled system-wide symbolic hotkeys (Spotlight, Mission Control, …).
    static func isSystemShortcut(keyCode: Int, modifiers: Int) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        let mask = cmdKey | shiftKey | optionKey | controlKey
        return entries.contains { entry in
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                  let code = (entry["kHISymbolicHotKeyCode"] as? NSNumber)?.intValue,
                  let mods = (entry["kHISymbolicHotKeyModifiers"] as? NSNumber)?.intValue else { return false }
            return code == keyCode && (mods & mask) == (modifiers & mask)
        }
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.shift) { mods |= shiftKey }
        return mods
    }

    static func display(keyName: String, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func keyName(for event: NSEvent) -> String {
        if let f = functionKeys[Int(event.keyCode)] { return f }
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
