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

public struct VoiceInkAudioInputAvailableDevice<ID: Equatable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let uid: String
    public let name: String

    public init(id: ID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
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

public enum VoiceInkAudioInputDiagnostics {
    public static let unknownDeviceName = "Unknown Device"
    public static let systemDefaultModeMessage = "🎙️ Using System Default mode"
    public static let currentDeviceUnavailableSelectingNewDeviceMessage = "🎙️ Current device unavailable, selecting new device..."
    public static let currentDeviceUnavailableMessage = "🎙️ Currently selected device is no longer available"
    public static let noInputDevicesAvailableMessage = "No input devices available!"
    public static let noAudioInputDevicesAvailableMessage = "No audio input devices available!"
    public static let deviceListChangeDetectedMessage = "🎙️ Device list change detected"
    public static let noPriorityDevicesAvailableFallbackMessage = "🎙️ No priority devices available, using fallback"

    public static func systemDefaultDeviceLookupFailedMessage(status: Int32) -> String {
        "Failed to get system default device: \(status)"
    }

    public static func savedDeviceUnavailableMessage(uid: String) -> String {
        "🎙️ Saved device UID \(uid) is no longer available"
    }

    public static func autoSelectingNewDeviceMessage(name: String) -> String {
        "🎙️ Auto-selecting new device: \(name)"
    }

    public static func audioDevicesLoadFailedMessage(status: Int32) -> String {
        "Error getting audio devices: \(status)"
    }

    public static func inputCapabilityCheckFailedMessage(deviceID: UInt32, status: Int32) -> String {
        "Error checking input capability for device \(deviceID): \(status)"
    }

    public static func streamConfigurationLoadFailedMessage(deviceID: UInt32, status: Int32) -> String {
        "Error getting stream configuration for device \(deviceID): \(status)"
    }

    public static func unavailableDeviceSelectionAttemptedMessage(deviceID: UInt32) -> String {
        "Attempted to select unavailable device: \(deviceID)"
    }

    public static func selectedPrioritizedDeviceMessage(name: String) -> String {
        "🎙️ Selected prioritized device: \(name)"
    }

    public static func safeFallbackDeviceSelectedMessage(name: String) -> String {
        "🎙️ No built-in input found, auto-selecting safe non-Bluetooth device: \(name)"
    }

    public static func unsafeAutomaticDeviceRefusedMessage(name: String) -> String {
        "🎙️ No safe automatic input found; refusing to auto-select \(name)"
    }

    public static func deviceChangeListenerAddFailedMessage(status: Int32) -> String {
        "Failed to add device change listener: \(status)"
    }

    public static func recordingDeviceUnavailableMessage(deviceID: UInt32) -> String {
        "🎙️ Recording device \(deviceID) no longer available - requesting switch"
    }

    public static func devicePropertyLookupFailedMessage(selector: UInt32, deviceID: UInt32, status: Int32) -> String {
        "Failed to get device property \(selector) for device \(deviceID): \(status)"
    }

    public static func transportTypeLookupFailedMessage(deviceID: UInt32, status: Int32) -> String {
        "Failed to get transport type for device \(deviceID): \(status)"
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

    public static func firstAvailablePriorityDevice<ID: Equatable & Sendable>(
        in devices: [VoiceInkAudioInputPriorityDevice],
        availableDevices: [VoiceInkAudioInputAvailableDevice<ID>]
    ) -> VoiceInkAudioInputAvailableDevice<ID>? {
        for device in sortedDevices(devices) {
            if let availableDevice = availableDevices.first(where: { $0.uid == device.id }) {
                return availableDevice
            }
        }

        return nil
    }

    public static func firstAvailablePriorityDeviceID<ID: Equatable & Sendable>(
        in devices: [VoiceInkAudioInputPriorityDevice],
        availableDevices: [VoiceInkAudioInputAvailableDevice<ID>]
    ) -> ID? {
        firstAvailablePriorityDevice(in: devices, availableDevices: availableDevices)?.id
    }
}

public struct VoiceInkAudioInputRecordingSwitchPlan<ID: Equatable & Sendable>: Equatable, Sendable {
    public let deviceID: ID?
    public let usedPriorityFallback: Bool

    public init(deviceID: ID?, usedPriorityFallback: Bool) {
        self.deviceID = deviceID
        self.usedPriorityFallback = usedPriorityFallback
    }
}

public enum VoiceInkAudioInputSelectionPolicy {
    public static func currentDeviceID<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        selectedDeviceID: ID?,
        selectedDeviceIsAvailable: Bool,
        priorityDeviceID: ID?,
        automaticDeviceID: ID?,
        systemDefaultDeviceID: ID? = nil
    ) -> ID? {
        switch inputMode {
        case .systemDefault:
            return systemDefaultDeviceID ?? automaticDeviceID
        case .custom:
            if selectedDeviceIsAvailable, let selectedDeviceID {
                return selectedDeviceID
            }

            return automaticDeviceID
        case .prioritized:
            return priorityDeviceID ?? automaticDeviceID
        }
    }

    public static func currentDeviceID<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        selectedDeviceID: ID?,
        prioritizedDevices: [VoiceInkAudioInputPriorityDevice],
        availableDevices: [VoiceInkAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?,
        systemDefaultDeviceID: ID? = nil
    ) -> ID? {
        currentDeviceID(
            inputMode: inputMode,
            selectedDeviceID: selectedDeviceID,
            selectedDeviceIsAvailable: selectedDeviceID.map { selectedDeviceID in
                availableDevices.contains(where: { $0.id == selectedDeviceID })
            } ?? false,
            priorityDeviceID: VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID,
            systemDefaultDeviceID: systemDefaultDeviceID
        )
    }

    public static func deviceIDToSelectWhenChangingMode<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        selectedDeviceID: ID?,
        priorityDeviceID: ID?,
        automaticDeviceID: ID?
    ) -> ID? {
        guard selectedDeviceID == nil else { return nil }

        switch inputMode {
        case .systemDefault:
            return nil
        case .custom:
            return automaticDeviceID
        case .prioritized:
            return priorityDeviceID ?? automaticDeviceID
        }
    }

    public static func deviceIDToSelectWhenChangingMode<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        selectedDeviceID: ID?,
        prioritizedDevices: [VoiceInkAudioInputPriorityDevice],
        availableDevices: [VoiceInkAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?
    ) -> ID? {
        deviceIDToSelectWhenChangingMode(
            inputMode: inputMode,
            selectedDeviceID: selectedDeviceID,
            priorityDeviceID: VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID
        )
    }

    public static func recordingSwitchPlan<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        priorityDeviceID: ID?,
        automaticDeviceID: ID?
    ) -> VoiceInkAudioInputRecordingSwitchPlan<ID> {
        guard inputMode == .prioritized else {
            return VoiceInkAudioInputRecordingSwitchPlan(deviceID: automaticDeviceID, usedPriorityFallback: false)
        }

        if let priorityDeviceID {
            return VoiceInkAudioInputRecordingSwitchPlan(deviceID: priorityDeviceID, usedPriorityFallback: false)
        }

        return VoiceInkAudioInputRecordingSwitchPlan(deviceID: automaticDeviceID, usedPriorityFallback: true)
    }

    public static func recordingSwitchPlan<ID: Equatable & Sendable>(
        inputMode: VoiceInkAudioInputMode,
        prioritizedDevices: [VoiceInkAudioInputPriorityDevice],
        availableDevices: [VoiceInkAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?
    ) -> VoiceInkAudioInputRecordingSwitchPlan<ID> {
        recordingSwitchPlan(
            inputMode: inputMode,
            priorityDeviceID: VoiceInkAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID
        )
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

    public func switchedDeviceNotificationTitle(deviceName: String) -> String {
        "Switched to: \(deviceName)"
    }

    public func usingDeviceNotificationTitle(deviceName: String) -> String {
        "Using: \(deviceName)"
    }
}
