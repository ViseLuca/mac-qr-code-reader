import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key combination for a global hotkey, in Carbon terms (virtual key code and modifier mask).
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    /// The combination pressed in `event`, or nil if it cannot be a global shortcut: without ⌘, ⌥ or ⌃
    /// it would swallow normal typing (function keys excepted), and keys like Return or the arrows are left alone.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers)

        let isFunctionKey = Self.functionKeys[keyCode] != nil
        guard isFunctionKey || modifiers & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        guard isFunctionKey || keyCode == UInt32(kVK_Space) || Self.layoutCharacter(keyCode) != nil else { return nil }
    }

    /// As macOS menus show it, e.g. "⌥⇧C".
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    /// For showing the shortcut next to its menu item.
    var keyboardShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        if let number = Self.functionKeys[keyCode] {
            guard let scalar = Unicode.Scalar(NSF1FunctionKey + number - 1) else { return nil }
            key = KeyEquivalent(Character(scalar))
        } else if keyCode == UInt32(kVK_Space) {
            key = .space
        } else if let character = Self.layoutCharacter(keyCode)?.lowercased().first {
            key = KeyEquivalent(character)
        } else {
            return nil
        }
        var eventModifiers: SwiftUI.EventModifiers = []
        if modifiers & UInt32(controlKey) != 0 { eventModifiers.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { eventModifiers.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { eventModifiers.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { eventModifiers.insert(.command) }
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }

    private var keyName: String {
        if let number = Self.functionKeys[keyCode] { return "F\(number)" }
        if keyCode == UInt32(kVK_Space) { return String(localized: "Space", comment: "Space bar") }
        return Self.layoutCharacter(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    private static let functionKeys: [UInt32: Int] = [
        UInt32(kVK_F1): 1, UInt32(kVK_F2): 2, UInt32(kVK_F3): 3, UInt32(kVK_F4): 4,
        UInt32(kVK_F5): 5, UInt32(kVK_F6): 6, UInt32(kVK_F7): 7, UInt32(kVK_F8): 8,
        UInt32(kVK_F9): 9, UInt32(kVK_F10): 10, UInt32(kVK_F11): 11, UInt32(kVK_F12): 12,
    ]

    /// The character the key types with no modifiers in the current keyboard layout (so "Z" on a QWERTZ
    /// layout is shown as Z), or nil for keys that type nothing visible.
    private static func layoutCharacter(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                           characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return text.isEmpty ? nil : text
    }
}

/// What a global shortcut does.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case viewfinder, region, camera

    var id: Self { self }

    var title: String {
        switch self {
        case .viewfinder: String(localized: "Screen Viewfinder")
        case .region: String(localized: "Select Area")
        case .camera: String(localized: "Webcam")
        }
    }

    var defaultShortcut: Shortcut {
        let keyCode = switch self {
        case .viewfinder: kVK_ANSI_Q
        case .region: kVK_ANSI_A
        case .camera: kVK_ANSI_C
        }
        return Shortcut(keyCode: keyCode, modifiers: optionKey | shiftKey)
    }
}
