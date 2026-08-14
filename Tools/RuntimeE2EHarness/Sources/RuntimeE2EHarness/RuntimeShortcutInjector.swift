import ApplicationServices
import Foundation
import RuntimeE2ECore

struct RuntimeShortcutEventResult: Codable {
    let kind: String
    let keyCode: UInt16
    let postedAtSystemUptime: Double
}

enum RuntimeShortcutInjector {
    static let leftShiftKeyCode: UInt16 = 56

    static func postLeftShiftDown() throws -> RuntimeShortcutEventResult {
        try postModifierDown(.leftShift)
    }

    static func postLeftShiftUp() throws -> RuntimeShortcutEventResult {
        try postModifierUp(.leftShift)
    }

    static func postModifierDown(
        _ shortcut: RuntimeModifierShortcut
    ) throws -> RuntimeShortcutEventResult {
        try postModifier(
            keyCode: shortcut.keyCode,
            flags: flags(for: shortcut.modifierFlag),
            isDown: true,
            kind: "keyDown"
        )
    }

    static func postModifierUp(
        _ shortcut: RuntimeModifierShortcut
    ) throws -> RuntimeShortcutEventResult {
        try postModifier(
            keyCode: shortcut.keyCode,
            flags: [],
            isDown: false,
            kind: "keyUp"
        )
    }

    static func postKeyDown(
        keyCode: UInt16,
        flags: CGEventFlags
    ) throws -> RuntimeShortcutEventResult {
        try postKey(keyCode: keyCode, flags: flags, isDown: true, kind: "keyDown")
    }

    static func postKeyUp(
        keyCode: UInt16,
        flags: CGEventFlags
    ) throws -> RuntimeShortcutEventResult {
        try postKey(keyCode: keyCode, flags: flags, isDown: false, kind: "keyUp")
    }

    static func postPointerEvent(
        type: CGEventType,
        point: CGPoint,
        flags: CGEventFlags = []
    ) throws {
        guard AXIsProcessTrusted() else {
            throw RuntimeShortcutInjectorError.accessibilityNotGranted
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  mouseEventSource: source,
                  mouseType: type,
                  mouseCursorPosition: point,
                  mouseButton: .left
              ) else {
            throw RuntimeShortcutInjectorError.eventCreationFailed
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x524f4d41)
        event.post(tap: .cghidEventTap)
    }

    static func flags(for modifier: RuntimeModifierFlag) -> CGEventFlags {
        switch modifier {
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .function: .maskSecondaryFn
        }
    }

    private static func postModifier(
        keyCode: UInt16,
        flags: CGEventFlags,
        isDown: Bool,
        kind: String
    ) throws -> RuntimeShortcutEventResult {
        guard AXIsProcessTrusted() else {
            throw RuntimeShortcutInjectorError.accessibilityNotGranted
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: isDown
              ) else {
            throw RuntimeShortcutInjectorError.eventCreationFailed
        }
        event.type = .flagsChanged
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x524f4d41)
        let postedAt = ProcessInfo.processInfo.systemUptime
        event.post(tap: .cghidEventTap)
        return RuntimeShortcutEventResult(
            kind: kind,
            keyCode: keyCode,
            postedAtSystemUptime: postedAt
        )
    }

    private static func postKey(
        keyCode: UInt16,
        flags: CGEventFlags,
        isDown: Bool,
        kind: String
    ) throws -> RuntimeShortcutEventResult {
        guard AXIsProcessTrusted() else {
            throw RuntimeShortcutInjectorError.accessibilityNotGranted
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(keyCode),
                  keyDown: isDown
              ) else {
            throw RuntimeShortcutInjectorError.eventCreationFailed
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x524f4d41)
        let postedAt = ProcessInfo.processInfo.systemUptime
        event.post(tap: .cghidEventTap)
        return RuntimeShortcutEventResult(
            kind: kind,
            keyCode: keyCode,
            postedAtSystemUptime: postedAt
        )
    }
}

enum RuntimeShortcutInjectorError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case eventCreationFailed

    var description: String {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility is not granted to the runtime harness"
        case .eventCreationFailed:
            return "Could not create synthetic input event"
        }
    }
}
