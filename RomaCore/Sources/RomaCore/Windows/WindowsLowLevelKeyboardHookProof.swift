import CWindowsSupport
import Foundation

public struct WindowsLowLevelKeyboardHookChord: Equatable, Hashable, Sendable {
    public var virtualKeyCode: UInt32
    public var requiredModifiers: UInt32
    public var displayName: String

    public init(
        virtualKeyCode: UInt32,
        requiredModifiers: UInt32,
        displayName: String
    ) {
        self.virtualKeyCode = virtualKeyCode
        self.requiredModifiers = requiredModifiers
        self.displayName = displayName
    }

    public static let proofHold = WindowsLowLevelKeyboardHookChord(
        virtualKeyCode: 0x52,
        requiredModifiers: UInt32(ROMA_WINDOWS_KEYBOARD_MOD_CONTROL | ROMA_WINDOWS_KEYBOARD_MOD_SHIFT),
        displayName: "Ctrl+Shift+R"
    )
}

public struct WindowsLowLevelKeyboardHookResult: Equatable, Hashable, Sendable {
    public var observedEvents: UInt32

    public init(observedEvents: UInt32) {
        self.observedEvents = observedEvents
    }

    public var observedKeyDown: Bool {
        observedEvents & UInt32(ROMA_WINDOWS_KEYBOARD_EVENT_KEY_DOWN) != 0
    }

    public var observedKeyUp: Bool {
        observedEvents & UInt32(ROMA_WINDOWS_KEYBOARD_EVENT_KEY_UP) != 0
    }
}

public enum WindowsLowLevelKeyboardHookError: Error, LocalizedError, Equatable {
    case unsupported
    case installFailed(lastError: UInt32)
    case messageLoopFailed
    case timeout(observedEvents: UInt32)
    case invalidResult(observedEvents: UInt32)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Windows low-level keyboard hooks are not available on this platform."
        case .installFailed(let lastError):
            return "SetWindowsHookEx(WH_KEYBOARD_LL) failed with GetLastError=\(lastError)."
        case .messageLoopFailed:
            return "The Windows keyboard hook message loop failed."
        case .timeout(let observedEvents):
            return "Timed out waiting for hold proof events; observedEvents=\(observedEvents)."
        case .invalidResult(let observedEvents):
            return "Keyboard hook proof did not observe both keydown and keyup; observedEvents=\(observedEvents)."
        }
    }
}

public enum WindowsLowLevelKeyboardHookProof {
    public static var isRuntimeAvailable: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    public static func waitForHold(
        chord: WindowsLowLevelKeyboardHookChord = .proofHold,
        timeoutMilliseconds: UInt32 = RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds
    ) throws -> WindowsLowLevelKeyboardHookResult {
        try waitForEvent(
            chord: chord,
            targetEvent: UInt32(ROMA_WINDOWS_KEYBOARD_EVENT_KEY_DOWN | ROMA_WINDOWS_KEYBOARD_EVENT_KEY_UP),
            timeoutMilliseconds: timeoutMilliseconds,
            requireKeyDown: true,
            requireKeyUp: true
        )
    }

    public static func waitForHoldWindow(
        chord: WindowsLowLevelKeyboardHookChord = .proofHold,
        timeoutMilliseconds: UInt32 = RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds,
        onKeyDown: @escaping @Sendable () -> Void
    ) throws -> WindowsLowLevelKeyboardHookResult {
        #if os(Windows)
        var observedEvents: UInt32 = 0
        var lastError: UInt32 = 0
        let callbackBox = WindowsLowLevelKeyboardHookCallbackBox(onKeyDown: onKeyDown)
        let status = withExtendedLifetime(callbackBox) {
            roma_windows_keyboard_wait_for_hold_window(
                chord.virtualKeyCode,
                chord.requiredModifiers,
                timeoutMilliseconds,
                { context in
                    guard let context else { return }
                    let box = Unmanaged<WindowsLowLevelKeyboardHookCallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    box.onKeyDown()
                },
                Unmanaged.passUnretained(callbackBox).toOpaque(),
                &observedEvents,
                &lastError
            )
        }

        return try makeResult(
            status: status,
            observedEvents: observedEvents,
            lastError: lastError,
            requireKeyDown: true,
            requireKeyUp: true
        )
        #else
        _ = onKeyDown
        throw WindowsLowLevelKeyboardHookError.unsupported
        #endif
    }

    public static func waitForKeyDown(
        chord: WindowsLowLevelKeyboardHookChord = .proofHold,
        timeoutMilliseconds: UInt32 = RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds
    ) throws -> WindowsLowLevelKeyboardHookResult {
        try waitForEvent(
            chord: chord,
            targetEvent: UInt32(ROMA_WINDOWS_KEYBOARD_EVENT_KEY_DOWN),
            timeoutMilliseconds: timeoutMilliseconds,
            requireKeyDown: true,
            requireKeyUp: false
        )
    }

    public static func waitForKeyUp(
        chord: WindowsLowLevelKeyboardHookChord = .proofHold,
        timeoutMilliseconds: UInt32 = RomaWindowsAgentConfiguration.defaultHoldTimeoutMilliseconds
    ) throws -> WindowsLowLevelKeyboardHookResult {
        try waitForEvent(
            chord: chord,
            targetEvent: UInt32(ROMA_WINDOWS_KEYBOARD_EVENT_KEY_UP),
            timeoutMilliseconds: timeoutMilliseconds,
            requireKeyDown: false,
            requireKeyUp: true
        )
    }

    private static func waitForEvent(
        chord: WindowsLowLevelKeyboardHookChord,
        targetEvent: UInt32,
        timeoutMilliseconds: UInt32,
        requireKeyDown: Bool,
        requireKeyUp: Bool
    ) throws -> WindowsLowLevelKeyboardHookResult {
        var observedEvents: UInt32 = 0
        var lastError: UInt32 = 0
        let status = roma_windows_keyboard_wait_for_event(
            chord.virtualKeyCode,
            chord.requiredModifiers,
            targetEvent,
            timeoutMilliseconds,
            &observedEvents,
            &lastError
        )

        return try makeResult(
            status: status,
            observedEvents: observedEvents,
            lastError: lastError,
            requireKeyDown: requireKeyDown,
            requireKeyUp: requireKeyUp
        )
    }

    private static func makeResult(
        status: roma_windows_keyboard_status_t,
        observedEvents: UInt32,
        lastError: UInt32,
        requireKeyDown: Bool,
        requireKeyUp: Bool
    ) throws -> WindowsLowLevelKeyboardHookResult {
        switch status {
        case ROMA_WINDOWS_KEYBOARD_OK:
            let result = WindowsLowLevelKeyboardHookResult(observedEvents: observedEvents)
            guard (!requireKeyDown || result.observedKeyDown),
                  (!requireKeyUp || result.observedKeyUp) else {
                throw WindowsLowLevelKeyboardHookError.invalidResult(observedEvents: observedEvents)
            }
            return result
        case ROMA_WINDOWS_KEYBOARD_UNSUPPORTED:
            throw WindowsLowLevelKeyboardHookError.unsupported
        case ROMA_WINDOWS_KEYBOARD_INSTALL_FAILED:
            throw WindowsLowLevelKeyboardHookError.installFailed(lastError: lastError)
        case ROMA_WINDOWS_KEYBOARD_MESSAGE_LOOP_FAILED:
            throw WindowsLowLevelKeyboardHookError.messageLoopFailed
        case ROMA_WINDOWS_KEYBOARD_TIMEOUT:
            throw WindowsLowLevelKeyboardHookError.timeout(observedEvents: observedEvents)
        default:
            throw WindowsLowLevelKeyboardHookError.messageLoopFailed
        }
    }
}

private final class WindowsLowLevelKeyboardHookCallbackBox: @unchecked Sendable {
    let onKeyDown: @Sendable () -> Void

    init(onKeyDown: @escaping @Sendable () -> Void) {
        self.onKeyDown = onKeyDown
    }
}
