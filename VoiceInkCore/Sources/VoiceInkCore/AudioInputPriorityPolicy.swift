import Foundation

public enum VoiceInkAudioInputMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case systemDefault = "System Default"
    case custom = "Custom Device"
    case prioritized = "Prioritized"

    public var id: Self { self }

    public static let defaultMode: Self = .custom

    public var title: String {
        rawValue
    }

    public var iconSystemName: String {
        switch self {
        case .systemDefault:
            return "display"
        case .custom:
            return "mic.circle.fill"
        case .prioritized:
            return "list.number"
        }
    }

    public var description: String {
        switch self {
        case .systemDefault:
            return "Use your Mac's default input"
        case .custom:
            return "Select a specific input device"
        case .prioritized:
            return "Set up device priority order"
        }
    }
}

public struct VoiceInkAudioInputPriorityDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let priority: Int

    public init(id: String, name: String, priority: Int) {
        self.id = id
        self.name = name
        self.priority = priority
    }
}

public enum VoiceInkAudioInputPreference {
    public static let inputModeKey = "audioInputMode"
    public static let selectedDeviceUIDKey = "selectedAudioDeviceUID"
    public static let prioritizedDevicesKey = "prioritizedDevices"
    public static let lastUsedMicrophoneDeviceIDKey = "lastUsedMicrophoneDeviceID"

    public static var registeredDefaults: [String: Any] {
        [
            inputModeKey: VoiceInkAudioInputMode.defaultMode.rawValue
        ]
    }

    public static func inputMode(from defaults: UserDefaults = .standard) -> VoiceInkAudioInputMode {
        guard let rawValue = defaults.string(forKey: inputModeKey),
              let mode = VoiceInkAudioInputMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveInputMode(_ mode: VoiceInkAudioInputMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: inputModeKey)
    }

    public static func selectedDeviceUID(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: selectedDeviceUIDKey)
    }

    public static func saveSelectedDeviceUID(_ uid: String, to defaults: UserDefaults = .standard) {
        defaults.set(uid, forKey: selectedDeviceUIDKey)
    }

    public static func clearSelectedDeviceUID(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: selectedDeviceUIDKey)
    }

    public static func prioritizedDevices(from defaults: UserDefaults = .standard) -> [VoiceInkAudioInputPriorityDevice] {
        guard let data = defaults.data(forKey: prioritizedDevicesKey),
              let devices = try? JSONDecoder().decode([VoiceInkAudioInputPriorityDevice].self, from: data) else {
            return []
        }

        return devices
    }

    public static func savePrioritizedDevices(
        _ devices: [VoiceInkAudioInputPriorityDevice],
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: prioritizedDevicesKey)
    }

    public static func lastUsedMicrophoneDeviceID(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: lastUsedMicrophoneDeviceIDKey)
    }

    public static func saveLastUsedMicrophoneDeviceID(
        _ deviceID: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(deviceID, forKey: lastUsedMicrophoneDeviceIDKey)
    }

    public static func shouldAnnounceMicrophoneChange(
        to deviceID: String,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        deviceID != lastUsedMicrophoneDeviceID(from: defaults)
    }

    public static func clearLastUsedMicrophoneDeviceID(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastUsedMicrophoneDeviceIDKey)
    }
}

public enum VoiceInkMacOSAudioDeviceChangeRequest {
    public static let deviceChangedNotificationName = Notification.Name("AudioDeviceChanged")
    public static let switchRequiredNotificationName = Notification.Name("audioDeviceSwitchRequired")
    public static let newDeviceIDUserInfoKey = "newDeviceID"

    public static func switchRequiredUserInfo(deviceID: UInt32) -> [AnyHashable: Any] {
        [newDeviceIDUserInfoKey: deviceID]
    }

    public static func newDeviceID(from notification: Notification) -> UInt32? {
        notification.userInfo?[newDeviceIDUserInfoKey] as? UInt32
    }
}

public enum VoiceInkAudioInputPriorityMoveDirection: Equatable, Sendable {
    case up
    case down
}

public enum VoiceInkAudioInputPriorityPolicy {
    public static func sortedDevices(
        _ devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        devices.sorted { $0.priority < $1.priority }
    }

    public static func reindexed(
        _ devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        devices.enumerated().map { index, device in
            VoiceInkAudioInputPriorityDevice(id: device.id, name: device.name, priority: index)
        }
    }

    public static func addDevice(
        uid: String,
        name: String,
        to devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        guard !devices.contains(where: { $0.id == uid }) else {
            return devices
        }

        let nextPriority = (devices.map(\.priority).max() ?? -1) + 1
        return devices + [
            VoiceInkAudioInputPriorityDevice(id: uid, name: name, priority: nextPriority)
        ]
    }

    public static func removeDevice(
        id: String,
        from devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        reindexed(devices.filter { $0.id != id })
    }

    public static func moveDevice(
        id: String,
        direction: VoiceInkAudioInputPriorityMoveDirection,
        in devices: [VoiceInkAudioInputPriorityDevice]
    ) -> [VoiceInkAudioInputPriorityDevice] {
        guard let currentIndex = devices.firstIndex(where: { $0.id == id }) else {
            return devices
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = currentIndex + 1
        }

        guard devices.indices.contains(targetIndex) else {
            return devices
        }

        var movedDevices = devices
        movedDevices.swapAt(currentIndex, targetIndex)
        return reindexed(movedDevices)
    }

    public static func firstAvailablePriorityDeviceID(
        in devices: [VoiceInkAudioInputPriorityDevice],
        availableDeviceIDs: Set<String>
    ) -> String? {
        sortedDevices(devices).first { availableDeviceIDs.contains($0.id) }?.id
    }
}

public struct VoiceInkAudioInputAutomaticDevice<ID: Equatable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let name: String
    public let isBuiltIn: Bool
    public let isBluetooth: Bool

    public init(
        id: ID,
        name: String,
        isBuiltIn: Bool,
        isBluetooth: Bool
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isBluetooth = isBluetooth
    }
}

public enum VoiceInkAudioInputAutomaticSelectionReason: Equatable, Sendable {
    case preferred
    case builtIn
    case safeFallback
    case unavailable
}

public struct VoiceInkAudioInputAutomaticSelection<ID: Equatable & Sendable>: Equatable, Sendable {
    public let deviceID: ID?
    public let reason: VoiceInkAudioInputAutomaticSelectionReason

    public init(
        deviceID: ID?,
        reason: VoiceInkAudioInputAutomaticSelectionReason
    ) {
        self.deviceID = deviceID
        self.reason = reason
    }
}

public enum VoiceInkAudioInputAutomaticSelectionPolicy {
    public static let builtInUIDMarker = "BuiltIn"
    public static let unsafeAirPodsNameMarker = "airpods"

    public static func isBuiltInDevice(
        transportIsBuiltIn: Bool,
        uid: String?
    ) -> Bool {
        transportIsBuiltIn || (uid?.localizedCaseInsensitiveContains(builtInUIDMarker) == true)
    }

    public static func isSafeAutomaticDevice(
        name: String,
        isBuiltIn: Bool,
        isBluetooth: Bool
    ) -> Bool {
        if isBuiltIn {
            return true
        }

        return !isBluetooth && !name.localizedCaseInsensitiveContains(unsafeAirPodsNameMarker)
    }

    public static func selection<ID: Equatable & Sendable>(
        preferred preferredDeviceID: ID? = nil,
        devices: [VoiceInkAudioInputAutomaticDevice<ID>]
    ) -> VoiceInkAudioInputAutomaticSelection<ID> {
        if let preferredDeviceID,
           let preferredDevice = devices.first(where: { $0.id == preferredDeviceID }),
           isSafeAutomaticDevice(preferredDevice) {
            return VoiceInkAudioInputAutomaticSelection(deviceID: preferredDevice.id, reason: .preferred)
        }

        if let builtInDevice = devices.first(where: \.isBuiltIn) {
            return VoiceInkAudioInputAutomaticSelection(deviceID: builtInDevice.id, reason: .builtIn)
        }

        if let safeDevice = devices.first(where: isSafeAutomaticDevice) {
            return VoiceInkAudioInputAutomaticSelection(deviceID: safeDevice.id, reason: .safeFallback)
        }

        return VoiceInkAudioInputAutomaticSelection(deviceID: nil, reason: .unavailable)
    }

    private static func isSafeAutomaticDevice<ID: Equatable & Sendable>(
        _ device: VoiceInkAudioInputAutomaticDevice<ID>
    ) -> Bool {
        isSafeAutomaticDevice(
            name: device.name,
            isBuiltIn: device.isBuiltIn,
            isBluetooth: device.isBluetooth
        )
    }
}

public struct VoiceInkMacOSAudioInputSettingsPresentation: Equatable, Sendable {
    public let heroSystemImageName: String
    public let heroTitle: String
    public let heroDescription: String
    public let inputModeSectionTitle: String
    public let currentDeviceSectionTitle: String
    public let currentDeviceSystemImageName: String
    public let noDeviceAvailableText: String
    public let activeStatusTitle: String
    public let activeStatusSystemImageName: String
    public let availableDevicesSectionTitle: String
    public let refreshButtonTitle: String
    public let refreshButtonSystemImageName: String
    public let prioritizedDevicesSectionTitle: String
    public let prioritizedDevicesDescription: String
    public let noPrioritizedDevicesText: String
    public let noAdditionalDevicesText: String
    public let emptyDevicesSystemImageName: String
    public let emptyDevicesTitle: String
    public let emptyDevicesDescription: String
    public let unavailableStatusTitle: String
    public let unavailableStatusSystemImageName: String
    public let addPrioritySystemImageName: String
    public let removePrioritySystemImageName: String
    public let moveUpSystemImageName: String
    public let moveDownSystemImageName: String
    public let unprioritizedPriorityPlaceholder: String

    public static let macOS = VoiceInkMacOSAudioInputSettingsPresentation(
        heroSystemImageName: "waveform",
        heroTitle: "Audio Input",
        heroDescription: "Configure your microphone preferences",
        inputModeSectionTitle: "Input Mode",
        currentDeviceSectionTitle: "Current Device",
        currentDeviceSystemImageName: "display",
        noDeviceAvailableText: "No device available",
        activeStatusTitle: "Active",
        activeStatusSystemImageName: "wave.3.right",
        availableDevicesSectionTitle: "Available Devices",
        refreshButtonTitle: "Refresh",
        refreshButtonSystemImageName: "arrow.clockwise",
        prioritizedDevicesSectionTitle: "Prioritized Devices",
        prioritizedDevicesDescription: "Devices will be used in order of priority. If a device is unavailable, the next one will be tried. If no prioritized device is available, the built-in microphone will be used.",
        noPrioritizedDevicesText: "No prioritized devices",
        noAdditionalDevicesText: "No additional devices available",
        emptyDevicesSystemImageName: "mic.slash.circle.fill",
        emptyDevicesTitle: "No Audio Devices",
        emptyDevicesDescription: "Connect an audio input device to get started",
        unavailableStatusTitle: "Unavailable",
        unavailableStatusSystemImageName: "exclamationmark.triangle",
        addPrioritySystemImageName: "plus.circle.fill",
        removePrioritySystemImageName: "minus.circle.fill",
        moveUpSystemImageName: "chevron.up",
        moveDownSystemImageName: "chevron.down",
        unprioritizedPriorityPlaceholder: "-"
    )

    public func priorityDisplayText(for zeroBasedPriority: Int) -> String {
        "\(zeroBasedPriority + 1)"
    }
}
