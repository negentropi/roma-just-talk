import Foundation
@testable import VoiceInkCore

final class AudioInputPriorityPolicyTests: XCTestCase {
    func testAudioInputModePreservesRawValuesDefaultAndOrder() {
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.rawValue, "System Default")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.rawValue, "Custom Device")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.rawValue, "Prioritized")
        XCTAssertEqual(VoiceInkAudioInputMode.defaultMode, .custom)
        XCTAssertEqual(VoiceInkAudioInputMode.allCases, [.systemDefault, .custom, .prioritized])
    }

    func testAudioInputPreferencePreservesStorageKeysDefaultsAndRoundTrips() {
        XCTAssertEqual(VoiceInkAudioInputPreference.inputModeKey, "audioInputMode")
        XCTAssertEqual(VoiceInkAudioInputPreference.selectedDeviceUIDKey, "selectedAudioDeviceUID")
        XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevicesKey, "prioritizedDevices")
        XCTAssertEqual(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceIDKey, "lastUsedMicrophoneDeviceID")
        XCTAssertEqual(
            VoiceInkAudioInputPreference.registeredDefaults[VoiceInkAudioInputPreference.inputModeKey] as? String,
            VoiceInkAudioInputMode.defaultMode.rawValue
        )

        withIsolatedDefaults { defaults in
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .custom)

            defaults.set("invalid", forKey: VoiceInkAudioInputPreference.inputModeKey)
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .custom)

            VoiceInkAudioInputPreference.saveInputMode(.prioritized, to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.inputMode(from: defaults), .prioritized)

            XCTAssertNil(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults))
            VoiceInkAudioInputPreference.saveSelectedDeviceUID("usb-mic", to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults), "usb-mic")
            VoiceInkAudioInputPreference.clearSelectedDeviceUID(from: defaults)
            XCTAssertNil(VoiceInkAudioInputPreference.selectedDeviceUID(from: defaults))

            let devices = [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
            ]

            XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevices(from: defaults), [])
            VoiceInkAudioInputPreference.savePrioritizedDevices(devices, to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.prioritizedDevices(from: defaults), devices)

            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
            XCTAssertTrue(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            VoiceInkAudioInputPreference.saveLastUsedMicrophoneDeviceID("123", to: defaults)
            XCTAssertEqual(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults), "123")
            XCTAssertFalse(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "123", in: defaults))
            XCTAssertTrue(VoiceInkAudioInputPreference.shouldAnnounceMicrophoneChange(to: "456", in: defaults))
            VoiceInkAudioInputPreference.clearLastUsedMicrophoneDeviceID(from: defaults)
            XCTAssertNil(VoiceInkAudioInputPreference.lastUsedMicrophoneDeviceID(from: defaults))
        }
    }

    func testAudioInputModePreservesSettingsPresentation() {
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.title, "System Default")
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.iconSystemName, "display")
        XCTAssertEqual(VoiceInkAudioInputMode.systemDefault.description, "Use your Mac's default input")

        XCTAssertEqual(VoiceInkAudioInputMode.custom.title, "Custom Device")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.iconSystemName, "mic.circle.fill")
        XCTAssertEqual(VoiceInkAudioInputMode.custom.description, "Select a specific input device")

        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.title, "Prioritized")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.iconSystemName, "list.number")
        XCTAssertEqual(VoiceInkAudioInputMode.prioritized.description, "Set up device priority order")
    }

    func testMacOSAudioInputSettingsPresentationPreservesCopyAndIcons() {
        let presentation = VoiceInkMacOSAudioInputSettingsPresentation.macOS

        XCTAssertEqual(presentation.heroSystemImageName, "waveform")
        XCTAssertEqual(presentation.heroTitle, "Audio Input")
        XCTAssertEqual(presentation.heroDescription, "Configure your microphone preferences")
        XCTAssertEqual(presentation.inputModeSectionTitle, "Input Mode")
        XCTAssertEqual(presentation.currentDeviceSectionTitle, "Current Device")
        XCTAssertEqual(presentation.currentDeviceSystemImageName, "display")
        XCTAssertEqual(presentation.noDeviceAvailableText, "No device available")
        XCTAssertEqual(presentation.activeStatusTitle, "Active")
        XCTAssertEqual(presentation.activeStatusSystemImageName, "wave.3.right")
        XCTAssertEqual(presentation.availableDevicesSectionTitle, "Available Devices")
        XCTAssertEqual(presentation.refreshButtonTitle, "Refresh")
        XCTAssertEqual(presentation.refreshButtonSystemImageName, "arrow.clockwise")
        XCTAssertEqual(presentation.prioritizedDevicesSectionTitle, "Prioritized Devices")
        XCTAssertEqual(
            presentation.prioritizedDevicesDescription,
            "Devices will be used in order of priority. If a device is unavailable, the next one will be tried. If no prioritized device is available, the built-in microphone will be used."
        )
        XCTAssertEqual(presentation.noPrioritizedDevicesText, "No prioritized devices")
        XCTAssertEqual(presentation.noAdditionalDevicesText, "No additional devices available")
        XCTAssertEqual(presentation.emptyDevicesSystemImageName, "mic.slash.circle.fill")
        XCTAssertEqual(presentation.emptyDevicesTitle, "No Audio Devices")
        XCTAssertEqual(presentation.emptyDevicesDescription, "Connect an audio input device to get started")
        XCTAssertEqual(presentation.unavailableStatusTitle, "Unavailable")
        XCTAssertEqual(presentation.unavailableStatusSystemImageName, "exclamationmark.triangle")
        XCTAssertEqual(presentation.addPrioritySystemImageName, "plus.circle.fill")
        XCTAssertEqual(presentation.removePrioritySystemImageName, "minus.circle.fill")
        XCTAssertEqual(presentation.moveUpSystemImageName, "chevron.up")
        XCTAssertEqual(presentation.moveDownSystemImageName, "chevron.down")
        XCTAssertEqual(presentation.unprioritizedPriorityPlaceholder, "-")
    }

    func testMacOSAudioInputSettingsPresentationFormatsPriorityDisplay() {
        let presentation = VoiceInkMacOSAudioInputSettingsPresentation.macOS

        XCTAssertEqual(presentation.priorityDisplayText(for: 0), "1")
        XCTAssertEqual(presentation.priorityDisplayText(for: 4), "5")
    }

    func testAddingPriorityDeviceAppendsNextPriorityAndKeepsDuplicatesNoOp() {
        let existing = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 3)
        ]

        let added = VoiceInkAudioInputPriorityPolicy.addDevice(
            uid: "studio",
            name: "Studio Mic",
            to: existing
        )

        XCTAssertEqual(
            added,
            existing + [
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 4)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.addDevice(uid: "usb", name: "Duplicate", to: existing),
            existing
        )
    }

    func testRemovingPriorityDeviceReindexesRemainingDevices() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.removeDevice(id: "usb", from: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1)
            ]
        )
    }

    func testMovingPriorityDeviceSwapsAndReindexesWithinBounds() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "studio", direction: .up, in: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 1),
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .down, in: devices),
            [
                VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 0),
                VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 1),
                VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2)
            ]
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "built-in", direction: .up, in: devices),
            devices
        )
        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.moveDevice(id: "missing", direction: .down, in: devices),
            devices
        )
    }

    func testFirstAvailablePriorityDeviceUsesPriorityOrder() {
        let devices = [
            VoiceInkAudioInputPriorityDevice(id: "studio", name: "Studio Mic", priority: 2),
            VoiceInkAudioInputPriorityDevice(id: "built-in", name: "Built-in", priority: 0),
            VoiceInkAudioInputPriorityDevice(id: "usb", name: "USB Mic", priority: 1)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: ["studio", "usb"]
            ),
            "usb"
        )
        XCTAssertNil(
            VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: devices,
                availableDeviceIDs: []
            )
        )
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.AudioInputPriorityPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
