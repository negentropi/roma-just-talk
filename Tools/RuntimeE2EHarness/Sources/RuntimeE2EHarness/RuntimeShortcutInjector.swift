import ApplicationServices
import Foundation

struct RuntimeShortcutEventResult: Codable {
    let kind: String
    let keyCode: UInt16
    let postedAtSystemUptime: Double
}

enum RuntimeShortcutInjector {
    static let leftShiftKeyCode: UInt16 = 56

    static func postLeftShiftDown() throws -> RuntimeShortcutEventResult {
        try postModifier(
            keyCode: leftShiftKeyCode,
            flags: .maskShift,
            kind: "keyDown"
        )
    }

    static func postLeftShiftUp() throws -> RuntimeShortcutEventResult {
        try postModifier(
            keyCode: leftShiftKeyCode,
            flags: [],
            kind: "keyUp"
        )
    }

    private static func postModifier(
        keyCode: UInt16,
        flags: CGEventFlags,
        kind: String
    ) throws -> RuntimeShortcutEventResult {
        guard AXIsProcessTrusted() else {
            throw RuntimeShortcutInjectorError.accessibilityNotGranted
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: !flags.isEmpty
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
}

enum RuntimeShortcutInjectorError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case eventCreationFailed

    var description: String {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility is not granted to the runtime harness"
        case .eventCreationFailed:
            return "Could not create synthetic left-Shift event"
        }
    }
}
