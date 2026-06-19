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
}
