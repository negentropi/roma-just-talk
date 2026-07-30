import AppKit
import Carbon.HIToolbox
import Testing
@testable import VoiceInk

extension VoiceInkTests {
    @Test func secureInputBlocksSpecialModifierShortcutUntilRelease() async {
        let monitor = ShortcutMonitor()
        var secureInputEnabled = true
        var keyDownCount = 0
        var keyUpCount = 0
        var contextChangeCount = 0

        ShortcutMonitor.configureSecureEventInputClientForTesting(
            SecureEventInputState.Client(isEnabled: { secureInputEnabled })
        )
        defer {
            monitor.stop()
            ShortcutMonitor.resetSecureEventInputClientForTesting()
        }

        monitor.configureForTesting(
            shortcuts: [
                .primaryRecording: .modifierOnly(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift]
                )
            ],
            secureInputBlockedActions: [.primaryRecording],
            handlesModifierOnlyShortcutsInEventTap: true,
            onKeyDown: { _, _ in keyDownCount += 1 },
            onKeyUp: { _, _, _ in keyUpCount += 1 },
            onPressContextChanged: { _, _ in contextChangeCount += 1 }
        )

        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 1
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 2
        )

        await drainSecureInputMainQueue()
        #expect(keyDownCount == 0)
        #expect(keyUpCount == 0)
        #expect(contextChangeCount == 0)

        secureInputEnabled = false
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift],
            eventTime: 3
        )
        monitor.handleEventTapFlagsChangedForTesting(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            eventTime: 4
        )

        await drainSecureInputMainQueue()
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    private func drainSecureInputMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
