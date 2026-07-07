import Foundation
import VoiceInkCore

final class AudioInputPolicyPublicAPITests: XCTestCase {
    func testFoldedAudioInputPolicySymbolsExposePublicAPI() {
        XCTAssertEqual(VoiceInkAudioInputMode.defaultMode, .custom)
        XCTAssertEqual(VoiceInkAudioInputMode.allCases, [.systemDefault, .custom, .prioritized])
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.iconSystemName, "list.number")

        let prioritizedDevices = [
            VoiceInkAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "built-in-uid", name: "Built-in", priority: 1)
        ]
        let availableDevices = [
            VoiceInkAudioInputAvailableDevice(id: 1, uid: "built-in-uid", name: "Built-in"),
            VoiceInkAudioInputAvailableDevice(id: 2, uid: "usb-uid", name: "USB Mic")
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            2
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: prioritizedDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            2
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                prioritizedDevices: prioritizedDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: 2, usedPriorityFallback: false)
        )

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(
                devices: [
                    VoiceInkAudioInputAutomaticDevice(
                        id: 2,
                        name: "USB Mic",
                        isBuiltIn: false,
                        isBluetooth: false
                    )
                ]
            ),
            VoiceInkAudioInputAutomaticSelection(deviceID: 2, reason: .safeFallback)
        )
        XCTAssertTrue(
            VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
                name: "Built-in Microphone",
                isBuiltIn: true,
                isBluetooth: true
            )
        )

        XCTAssertEqual(
            VoiceInkAudioInputPreference.registeredDefaults[VoiceInkAudioInputPreference.inputModeKey] as? String,
            VoiceInkAudioInputMode.defaultMode.rawValue
        )
        XCTAssertEqual(
            VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredUserInfo(deviceID: 42)[VoiceInkMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey] as? UInt32,
            42
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.autoSelectingNewDeviceMessage(name: "USB Mic"),
            "🎙️ Auto-selecting new device: USB Mic"
        )
        XCTAssertEqual(
            VoiceInkMacOSAudioInputSettingsPresentation.macOS.usingDeviceNotificationTitle(deviceName: "USB Mic"),
            "Using: USB Mic"
        )
    }
}
