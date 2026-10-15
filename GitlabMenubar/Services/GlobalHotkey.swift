//
//  GlobalHotkey.swift
//  GitlabMenubar
//

import Carbon.HIToolbox

/// System-wide hotkey via Carbon `RegisterEventHotKey` — unlike an `NSEvent` global
/// monitor, it needs no Accessibility permission.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// Shown in Settings; keep in sync with `keyCode`/`modifiers`.
    static let displayString = "⌥⌘G"

    private let keyCode = UInt32(kVK_ANSI_G)
    private let modifiers = UInt32(optionKey | cmdKey)

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns false when the combination is already taken by another app.
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }

        let id = EventHotKeyID(signature: OSType(0x474C_4D42), id: 1) // "GLMB"
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
