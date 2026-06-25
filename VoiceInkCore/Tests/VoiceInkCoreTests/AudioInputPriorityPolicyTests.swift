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

    func testMacOSAudioDeviceChangeRequestPreservesNotificationContract() {
        XCTAssertEqual(
            VoiceInkMacOSAudioDeviceChangeRequest.deviceChangedNotificationName.rawValue,
            "AudioDeviceChanged"
        )
        XCTAssertEqual(
            VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName.rawValue,
            "audioDeviceSwitchRequired"
        )
        XCTAssertEqual(VoiceInkMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey, "newDeviceID")

        let userInfo = VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredUserInfo(deviceID: 42)
        XCTAssertEqual(userInfo[VoiceInkMacOSAudioDeviceChangeRequest.newDeviceIDUserInfoKey] as? UInt32, 42)

        let notification = Notification(
            name: VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName,
            userInfo: userInfo
        )
        XCTAssertEqual(VoiceInkMacOSAudioDeviceChangeRequest.newDeviceID(from: notification), 42)
        XCTAssertNil(
            VoiceInkMacOSAudioDeviceChangeRequest.newDeviceID(
                from: Notification(name: VoiceInkMacOSAudioDeviceChangeRequest.switchRequiredNotificationName)
            )
        )
    }

    func testAudioInputDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.unknownDeviceName, "Unknown Device")
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.systemDefaultModeMessage, "🎙️ Using System Default mode")
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.systemDefaultDeviceLookupFailedMessage(status: -1),
            "Failed to get system default device: -1"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.savedDeviceUnavailableMessage(uid: "old-uid"),
            "🎙️ Saved device UID old-uid is no longer available"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.currentDeviceUnavailableSelectingNewDeviceMessage,
            "🎙️ Current device unavailable, selecting new device..."
        )
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.noInputDevicesAvailableMessage, "No input devices available!")
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.autoSelectingNewDeviceMessage(name: "Studio Mic"),
            "🎙️ Auto-selecting new device: Studio Mic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.audioDevicesLoadFailedMessage(status: -2),
            "Error getting audio devices: -2"
        )
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.currentDeviceUnavailableMessage, "🎙️ Currently selected device is no longer available")
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.inputCapabilityCheckFailedMessage(deviceID: 42, status: -3),
            "Error checking input capability for device 42: -3"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.streamConfigurationLoadFailedMessage(deviceID: 43, status: -4),
            "Error getting stream configuration for device 43: -4"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.unavailableDeviceSelectionAttemptedMessage(deviceID: 44),
            "Attempted to select unavailable device: 44"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.selectedPrioritizedDeviceMessage(name: "USB Mic"),
            "🎙️ Selected prioritized device: USB Mic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.safeFallbackDeviceSelectedMessage(name: "USB Mic"),
            "🎙️ No built-in input found, auto-selecting safe non-Bluetooth device: USB Mic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.unsafeAutomaticDeviceRefusedMessage(name: "AirPods"),
            "🎙️ No safe automatic input found; refusing to auto-select AirPods"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.deviceChangeListenerAddFailedMessage(status: -5),
            "Failed to add device change listener: -5"
        )
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.deviceListChangeDetectedMessage, "🎙️ Device list change detected")
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.recordingDeviceUnavailableMessage(deviceID: 45),
            "🎙️ Recording device 45 no longer available - requesting switch"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.noPriorityDevicesAvailableFallbackMessage,
            "🎙️ No priority devices available, using fallback"
        )
        XCTAssertEqual(VoiceInkAudioInputDiagnostics.noAudioInputDevicesAvailableMessage, "No audio input devices available!")
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.devicePropertyLookupFailedMessage(selector: 46, deviceID: 47, status: -6),
            "Failed to get device property 46 for device 47: -6"
        )
        XCTAssertEqual(
            VoiceInkAudioInputDiagnostics.transportTypeLookupFailedMessage(deviceID: 48, status: -7),
            "Failed to get transport type for device 48: -7"
        )
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
        XCTAssertEqual(
            presentation.switchedDeviceNotificationTitle(deviceName: "Studio Display Microphone"),
            "Switched to: Studio Display Microphone"
        )
        XCTAssertEqual(
            presentation.usingDeviceNotificationTitle(deviceName: "Studio Display Microphone"),
            "Using: Studio Display Microphone"
        )
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

    func testAutomaticSelectionPolicyPreservesBuiltInDetection() {
        XCTAssertEqual(VoiceInkAudioInputAutomaticSelectionPolicy.builtInUIDMarker, "BuiltIn")
        XCTAssertEqual(VoiceInkAudioInputAutomaticSelectionPolicy.unsafeAirPodsNameMarker, "airpods")
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: true,
            uid: nil
        ))
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "AppleUSBAudioEngine:BuiltInMicrophone"
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isBuiltInDevice(
            transportIsBuiltIn: false,
            uid: "external-usb-mic"
        ))
    }

    func testAutomaticSelectionPolicyPreservesSafeDeviceClassification() {
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "MacBook Microphone",
            isBuiltIn: true,
            isBluetooth: true
        ))
        XCTAssertTrue(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "USB Studio Mic",
            isBuiltIn: false,
            isBluetooth: false
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Bluetooth Headset",
            isBuiltIn: false,
            isBluetooth: true
        ))
        XCTAssertFalse(VoiceInkAudioInputAutomaticSelectionPolicy.isSafeAutomaticDevice(
            name: "Felix AirPods Pro",
            isBuiltIn: false,
            isBluetooth: false
        ))
    }

    func testAutomaticSelectionPolicyPrefersSafePreferredDevice() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "usb", devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "usb", reason: .preferred)
        )
    }

    func testAutomaticSelectionPolicyFallsBackToBuiltInBeforeOtherSafeDevices() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "built-in", name: "Built-in", isBuiltIn: true, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "missing", devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "built-in", reason: .builtIn)
        )
    }

    func testAutomaticSelectionPolicyUsesSafeFallbackWhenBuiltInUnavailable() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: true),
            VoiceInkAudioInputAutomaticDevice(id: "usb", name: "USB Mic", isBuiltIn: false, isBluetooth: false)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(devices: devices),
            VoiceInkAudioInputAutomaticSelection(deviceID: "usb", reason: .safeFallback)
        )
    }

    func testAutomaticSelectionPolicyRefusesUnsafeAutomaticDevices() {
        let devices = [
            VoiceInkAudioInputAutomaticDevice(id: "airpods", name: "AirPods", isBuiltIn: false, isBluetooth: false),
            VoiceInkAudioInputAutomaticDevice(id: "headset", name: "Bluetooth Headset", isBuiltIn: false, isBluetooth: true)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputAutomaticSelectionPolicy.selection(preferred: "headset", devices: devices),
            VoiceInkAudioInputAutomaticSelection<String>(deviceID: nil, reason: .unavailable)
        )
    }

    func testSelectionPolicyResolvesCurrentDeviceByMode() {
        let availableDevices = [
            VoiceInkAudioInputAvailableDevice(id: "built-in", uid: "built-in-uid", name: "Built-in"),
            VoiceInkAudioInputAvailableDevice(id: "usb", uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            VoiceInkAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 1),
            VoiceInkAudioInputPriorityDevice(id: "built-in-uid", name: "Built-in", priority: 2)
        ]

        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .systemDefault,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic",
                systemDefaultDeviceID: "system-default"
            ),
            "system-default"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .systemDefault,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic",
                systemDefaultDeviceID: nil
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "usb",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: "missing",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .custom,
                selectedDeviceID: nil,
                selectedDeviceIsAvailable: true,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "usb"
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.currentDeviceID(
                inputMode: .prioritized,
                selectedDeviceID: "built-in",
                prioritizedDevices: [
                    VoiceInkAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: "automatic"
            ),
            "automatic"
        )
    }

    func testSelectionPolicyPreservesModeChangeSelectionBehavior() {
        let availableDevices = [
            VoiceInkAudioInputAvailableDevice(id: 1, uid: "built-in-uid", name: "Built-in"),
            VoiceInkAudioInputAvailableDevice(id: 2, uid: "usb-uid", name: "USB Mic")
        ]
        let priorityDevices = [
            VoiceInkAudioInputPriorityDevice(id: "usb-uid", name: "USB Mic", priority: 0)
        ]

        XCTAssertNil(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: 1,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertNil(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .systemDefault,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            )
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .custom,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: priorityDevices,
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            2
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.deviceIDToSelectWhenChangingMode(
                inputMode: .prioritized,
                selectedDeviceID: nil,
                prioritizedDevices: [
                    VoiceInkAudioInputPriorityDevice(id: "missing-uid", name: "Missing", priority: 0)
                ],
                availableDevices: availableDevices,
                automaticDeviceID: 1
            ),
            1
        )
    }

    func testSelectionPolicyPlansRecordingDeviceSwitches() {
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "usb", usedPriorityFallback: false)
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .prioritized,
                priorityDeviceID: nil,
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: true)
        )
        XCTAssertEqual(
            VoiceInkAudioInputSelectionPolicy.recordingSwitchPlan(
                inputMode: .custom,
                priorityDeviceID: "usb",
                automaticDeviceID: "automatic"
            ),
            VoiceInkAudioInputRecordingSwitchPlan(deviceID: "automatic", usedPriorityFallback: false)
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
