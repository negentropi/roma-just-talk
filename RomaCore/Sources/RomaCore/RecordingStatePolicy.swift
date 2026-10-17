import Foundation

public enum RomaRecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}

public enum RomaAudioMeterLevel {
    public static let defaultMinimumDecibels: Float = -60
    public static let defaultMaximumDecibels: Float = 0
    public static let defaultPreviousLevelWeight: Float = 0.6
    public static let defaultLevelHistoryLimit = 40
    public static let macOSUpdateIntervalMilliseconds = 17
    public static let iOSUpdateInterval: TimeInterval = 0.1
    public static let macOSVisualizerAnimationMinimumInterval: TimeInterval = 0.016
    public static let macOSVisualizerBarCount = 15
    public static let macOSVisualizerBarWidth: Double = 3
    public static let macOSVisualizerBarSpacing: Double = 2
    public static let macOSVisualizerMinimumBarHeight: Double = 4
    public static let macOSVisualizerMaximumBarHeight: Double = 28
    public static let macOSVisualizerPhaseStep: Double = 0.4
    public static let macOSVisualizerWaveFrequency: Double = 8
    public static let macOSVisualizerAmplitudeExponent: Double = 0.7
    public static let macOSVisualizerCenterBoostDropoff: Double = 0.4
    public static let iOSVisualizerBarCount = 8
    public static let iOSVisualizerBarSpacing: Double = 3
    public static let iOSVisualizerBarMinimumWidth: Double = 2
    public static let iOSVisualizerHorizontalPadding: Double = 2
    public static let iOSVisualizerWidthInset: Double = 16
    public static let iOSVisualizerFrameHeight: Double = 48
    public static let iOSVisualizerMinimumBarHeight: Double = 4
    public static let iOSVisualizerAnimationDuration: TimeInterval = 0.12
    public static let visualizerAccessibilityLabel = "Audio level visualizer"

    public static func normalizedLevel(
        forDecibels decibels: Float,
        minimumDecibels: Float = defaultMinimumDecibels,
        maximumDecibels: Float = defaultMaximumDecibels
    ) -> Float {
        guard maximumDecibels > minimumDecibels else {
            return decibels >= maximumDecibels ? 1 : 0
        }

        if decibels < minimumDecibels {
            return 0
        }

        if decibels >= maximumDecibels {
            return 1
        }

        return (decibels - minimumDecibels) / (maximumDecibels - minimumDecibels)
    }

    public static func smoothedLevel(
        previous: Float,
        current: Float,
        previousWeight: Float = defaultPreviousLevelWeight
    ) -> Float {
        let clampedPreviousWeight = min(max(previousWeight, 0), 1)
        return previous * clampedPreviousWeight + current * (1 - clampedPreviousWeight)
    }

    public static func boundedHistory(
        appending level: Float,
        to history: [Float],
        limit: Int = defaultLevelHistoryLimit
    ) -> [Float] {
        guard limit > 0 else {
            return []
        }

        let updatedHistory = history + [level]
        guard updatedHistory.count > limit else {
            return updatedHistory
        }

        return Array(updatedHistory.suffix(limit))
    }

    public static func macOSMeterUpdatePlan(
        averageDecibels: Float,
        peakDecibels: Float,
        previousSmoothedAverage: Float,
        previousSmoothedPeak: Float
    ) -> RomaMacOSAudioMeterUpdatePlan {
        let normalizedAverage = normalizedLevel(forDecibels: averageDecibels)
        let normalizedPeak = normalizedLevel(forDecibels: peakDecibels)

        return RomaMacOSAudioMeterUpdatePlan(
            smoothedAverage: smoothedLevel(previous: previousSmoothedAverage, current: normalizedAverage),
            smoothedPeak: smoothedLevel(previous: previousSmoothedPeak, current: normalizedPeak)
        )
    }

    public static func iOSMeterHistoryUpdatePlan(
        averageDecibels: Float,
        previousHistory: [Float]
    ) -> RomaIOSAudioMeterHistoryUpdatePlan {
        let visibleLevel = normalizedLevel(forDecibels: averageDecibels)
        return RomaIOSAudioMeterHistoryUpdatePlan(
            normalizedLevel: visibleLevel,
            levelsHistory: boundedHistory(appending: visibleLevel, to: previousHistory)
        )
    }

    public static func visualizerLevel(
        forBarAt index: Int,
        levels: [Float],
        barCount: Int = iOSVisualizerBarCount
    ) -> Float {
        guard index >= 0, !levels.isEmpty, barCount > 0 else {
            return 0
        }

        let span = max(1, min(levels.count, barCount))
        let step = max(1, levels.count / span)
        let sourceIndex = max(0, levels.count - 1 - index * step)
        let sourceLevel = levels[sourceIndex]
        return max(0, min(1, sourceLevel))
    }

    public static func iOSVisualizerBarWidth(
        containerWidth: Double,
        barCount: Int = iOSVisualizerBarCount,
        spacing: Double = iOSVisualizerBarSpacing,
        widthInset: Double = iOSVisualizerWidthInset,
        minimumWidth: Double = iOSVisualizerBarMinimumWidth
    ) -> Double {
        guard barCount > 0 else { return minimumWidth }
        return max(minimumWidth, (containerWidth - widthInset) / Double(barCount) - spacing)
    }

    public static func iOSVisualizerBarHeight(
        forBarAt index: Int,
        levels: [Float],
        containerHeight: Double,
        barCount: Int = iOSVisualizerBarCount,
        minimumHeight: Double = iOSVisualizerMinimumBarHeight
    ) -> Double {
        let level = Double(visualizerLevel(forBarAt: index, levels: levels, barCount: barCount))
        return minimumHeight + (containerHeight - minimumHeight) * level
    }

    public static func macOSVisualizerBarHeight(
        forBarAt index: Int,
        time: TimeInterval,
        averagePower: Double,
        isActive: Bool,
        barCount: Int = macOSVisualizerBarCount,
        minimumHeight: Double = macOSVisualizerMinimumBarHeight,
        maximumHeight: Double = macOSVisualizerMaximumBarHeight
    ) -> Double {
        guard isActive, index >= 0, index < barCount, barCount > 1, maximumHeight > minimumHeight else {
            return minimumHeight
        }

        let amplitude = max(0, min(1, pow(averagePower, macOSVisualizerAmplitudeExponent)))
        let phase = Double(index) * macOSVisualizerPhaseStep
        let wave = sin(time * macOSVisualizerWaveFrequency + phase) * 0.5 + 0.5
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        let centerBoost = 1.0 - centerDistance * macOSVisualizerCenterBoostDropoff

        return max(minimumHeight, minimumHeight + amplitude * wave * centerBoost * (maximumHeight - minimumHeight))
    }
}

public struct RomaMacOSAudioMeterUpdatePlan: Equatable, Sendable {
    public let smoothedAverage: Float
    public let smoothedPeak: Float

    public init(smoothedAverage: Float, smoothedPeak: Float) {
        self.smoothedAverage = smoothedAverage
        self.smoothedPeak = smoothedPeak
    }
}

public struct RomaIOSAudioMeterHistoryUpdatePlan: Equatable, Sendable {
    public let normalizedLevel: Float
    public let levelsHistory: [Float]

    public init(normalizedLevel: Float, levelsHistory: [Float]) {
        self.normalizedLevel = normalizedLevel
        self.levelsHistory = levelsHistory
    }
}

public enum RomaAudioInputMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
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

public struct RomaAudioInputPriorityDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let priority: Int

    public init(id: String, name: String, priority: Int) {
        self.id = id
        self.name = name
        self.priority = priority
    }
}

public struct RomaAudioInputAvailableDevice<ID: Equatable & Sendable>: Equatable, Sendable {
    public let id: ID
    public let uid: String
    public let name: String

    public init(id: ID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public enum RomaAudioInputPreference {
    public static let inputModeKey = "audioInputMode"
    public static let selectedDeviceUIDKey = "selectedAudioDeviceUID"
    public static let prioritizedDevicesKey = "prioritizedDevices"
    public static let lastUsedMicrophoneDeviceIDKey = "lastUsedMicrophoneDeviceID"

    public static var registeredDefaults: [String: Any] {
        [
            inputModeKey: RomaAudioInputMode.defaultMode.rawValue
        ]
    }

    public static func inputMode(from defaults: UserDefaults = .standard) -> RomaAudioInputMode {
        guard let rawValue = defaults.string(forKey: inputModeKey),
              let mode = RomaAudioInputMode(rawValue: rawValue) else {
            return .defaultMode
        }

        return mode
    }

    public static func saveInputMode(_ mode: RomaAudioInputMode, to defaults: UserDefaults = .standard) {
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

    public static func prioritizedDevices(from defaults: UserDefaults = .standard) -> [RomaAudioInputPriorityDevice] {
        guard let data = defaults.data(forKey: prioritizedDevicesKey),
              let devices = try? JSONDecoder().decode([RomaAudioInputPriorityDevice].self, from: data) else {
            return []
        }

        return devices
    }

    public static func savePrioritizedDevices(
        _ devices: [RomaAudioInputPriorityDevice],
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

public enum RomaMacOSAudioDeviceChangeRequest {
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

public enum RomaAudioInputDiagnostics {
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

public enum RomaAudioInputPriorityMoveDirection: Equatable, Sendable {
    case up
    case down
}

public enum RomaAudioInputPriorityPolicy {
    public static func sortedDevices(
        _ devices: [RomaAudioInputPriorityDevice]
    ) -> [RomaAudioInputPriorityDevice] {
        devices.sorted { $0.priority < $1.priority }
    }

    public static func reindexed(
        _ devices: [RomaAudioInputPriorityDevice]
    ) -> [RomaAudioInputPriorityDevice] {
        devices.enumerated().map { index, device in
            RomaAudioInputPriorityDevice(id: device.id, name: device.name, priority: index)
        }
    }

    public static func addDevice(
        uid: String,
        name: String,
        to devices: [RomaAudioInputPriorityDevice]
    ) -> [RomaAudioInputPriorityDevice] {
        guard !devices.contains(where: { $0.id == uid }) else {
            return devices
        }

        let nextPriority = (devices.map(\.priority).max() ?? -1) + 1
        return devices + [
            RomaAudioInputPriorityDevice(id: uid, name: name, priority: nextPriority)
        ]
    }

    public static func removeDevice(
        id: String,
        from devices: [RomaAudioInputPriorityDevice]
    ) -> [RomaAudioInputPriorityDevice] {
        reindexed(devices.filter { $0.id != id })
    }

    public static func moveDevice(
        id: String,
        direction: RomaAudioInputPriorityMoveDirection,
        in devices: [RomaAudioInputPriorityDevice]
    ) -> [RomaAudioInputPriorityDevice] {
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
        in devices: [RomaAudioInputPriorityDevice],
        availableDeviceIDs: Set<String>
    ) -> String? {
        sortedDevices(devices).first { availableDeviceIDs.contains($0.id) }?.id
    }

    public static func firstAvailablePriorityDevice<ID: Equatable & Sendable>(
        in devices: [RomaAudioInputPriorityDevice],
        availableDevices: [RomaAudioInputAvailableDevice<ID>]
    ) -> RomaAudioInputAvailableDevice<ID>? {
        for device in sortedDevices(devices) {
            if let availableDevice = availableDevices.first(where: { $0.uid == device.id }) {
                return availableDevice
            }
        }

        return nil
    }

    public static func firstAvailablePriorityDeviceID<ID: Equatable & Sendable>(
        in devices: [RomaAudioInputPriorityDevice],
        availableDevices: [RomaAudioInputAvailableDevice<ID>]
    ) -> ID? {
        firstAvailablePriorityDevice(in: devices, availableDevices: availableDevices)?.id
    }
}

public struct RomaAudioInputRecordingSwitchPlan<ID: Equatable & Sendable>: Equatable, Sendable {
    public let deviceID: ID?
    public let usedPriorityFallback: Bool

    public init(deviceID: ID?, usedPriorityFallback: Bool) {
        self.deviceID = deviceID
        self.usedPriorityFallback = usedPriorityFallback
    }
}

public enum RomaAudioInputSelectionPolicy {
    public static func currentDeviceID<ID: Equatable & Sendable>(
        inputMode: RomaAudioInputMode,
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
        inputMode: RomaAudioInputMode,
        selectedDeviceID: ID?,
        prioritizedDevices: [RomaAudioInputPriorityDevice],
        availableDevices: [RomaAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?,
        systemDefaultDeviceID: ID? = nil
    ) -> ID? {
        currentDeviceID(
            inputMode: inputMode,
            selectedDeviceID: selectedDeviceID,
            selectedDeviceIsAvailable: selectedDeviceID.map { selectedDeviceID in
                availableDevices.contains(where: { $0.id == selectedDeviceID })
            } ?? false,
            priorityDeviceID: RomaAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID,
            systemDefaultDeviceID: systemDefaultDeviceID
        )
    }

    public static func deviceIDToSelectWhenChangingMode<ID: Equatable & Sendable>(
        inputMode: RomaAudioInputMode,
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
        inputMode: RomaAudioInputMode,
        selectedDeviceID: ID?,
        prioritizedDevices: [RomaAudioInputPriorityDevice],
        availableDevices: [RomaAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?
    ) -> ID? {
        deviceIDToSelectWhenChangingMode(
            inputMode: inputMode,
            selectedDeviceID: selectedDeviceID,
            priorityDeviceID: RomaAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID
        )
    }

    public static func recordingSwitchPlan<ID: Equatable & Sendable>(
        inputMode: RomaAudioInputMode,
        priorityDeviceID: ID?,
        automaticDeviceID: ID?
    ) -> RomaAudioInputRecordingSwitchPlan<ID> {
        guard inputMode == .prioritized else {
            return RomaAudioInputRecordingSwitchPlan(deviceID: automaticDeviceID, usedPriorityFallback: false)
        }

        if let priorityDeviceID {
            return RomaAudioInputRecordingSwitchPlan(deviceID: priorityDeviceID, usedPriorityFallback: false)
        }

        return RomaAudioInputRecordingSwitchPlan(deviceID: automaticDeviceID, usedPriorityFallback: true)
    }

    public static func recordingSwitchPlan<ID: Equatable & Sendable>(
        inputMode: RomaAudioInputMode,
        prioritizedDevices: [RomaAudioInputPriorityDevice],
        availableDevices: [RomaAudioInputAvailableDevice<ID>],
        automaticDeviceID: ID?
    ) -> RomaAudioInputRecordingSwitchPlan<ID> {
        recordingSwitchPlan(
            inputMode: inputMode,
            priorityDeviceID: RomaAudioInputPriorityPolicy.firstAvailablePriorityDeviceID(
                in: prioritizedDevices,
                availableDevices: availableDevices
            ),
            automaticDeviceID: automaticDeviceID
        )
    }
}

public struct RomaAudioInputAutomaticDevice<ID: Equatable & Sendable>: Equatable, Sendable {
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

public enum RomaAudioInputAutomaticSelectionReason: Equatable, Sendable {
    case preferred
    case builtIn
    case safeFallback
    case unavailable
}

public struct RomaAudioInputAutomaticSelection<ID: Equatable & Sendable>: Equatable, Sendable {
    public let deviceID: ID?
    public let reason: RomaAudioInputAutomaticSelectionReason

    public init(
        deviceID: ID?,
        reason: RomaAudioInputAutomaticSelectionReason
    ) {
        self.deviceID = deviceID
        self.reason = reason
    }
}

public enum RomaAudioInputAutomaticSelectionPolicy {
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
        devices: [RomaAudioInputAutomaticDevice<ID>]
    ) -> RomaAudioInputAutomaticSelection<ID> {
        if let preferredDeviceID,
           let preferredDevice = devices.first(where: { $0.id == preferredDeviceID }),
           isSafeAutomaticDevice(preferredDevice) {
            return RomaAudioInputAutomaticSelection(deviceID: preferredDevice.id, reason: .preferred)
        }

        if let builtInDevice = devices.first(where: \.isBuiltIn) {
            return RomaAudioInputAutomaticSelection(deviceID: builtInDevice.id, reason: .builtIn)
        }

        if let safeDevice = devices.first(where: isSafeAutomaticDevice) {
            return RomaAudioInputAutomaticSelection(deviceID: safeDevice.id, reason: .safeFallback)
        }

        return RomaAudioInputAutomaticSelection(deviceID: nil, reason: .unavailable)
    }

    private static func isSafeAutomaticDevice<ID: Equatable & Sendable>(
        _ device: RomaAudioInputAutomaticDevice<ID>
    ) -> Bool {
        isSafeAutomaticDevice(
            name: device.name,
            isBuiltIn: device.isBuiltIn,
            isBluetooth: device.isBluetooth
        )
    }
}

public struct RomaMacOSAudioInputSettingsPresentation: Equatable, Sendable {
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

    public static let macOS = RomaMacOSAudioInputSettingsPresentation(
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


fileprivate enum RomaRecorderUIToggleAction: Equatable, Sendable {
    case toggleRecord
    case cancelRecording
    case dismissRecorder
}

public enum RomaRecordingPermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

enum RomaRecordingPermissionAction: Equatable, Sendable {
    case startRecording
    case requestPermission
    case presentPermissionDenied

    func applyRuntimeState(
        startRecording: @escaping () -> Void,
        presentPermissionDenied: @escaping () -> Void,
        requestPermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentPermissionDenied:
            presentPermissionDenied()
        case .requestPermission:
            requestPermission { granted in
                RomaRecordingPermissionPolicy.plan(afterPermissionRequestGranted: granted)
                    .applyRuntimeState(
                        startRecording: startRecording,
                        presentPermissionDenied: presentPermissionDenied,
                        requestPermission: requestPermission
                    )
            }
        }
    }
}

public struct RomaRecordingPermissionPlan: Sendable {
    private let action: RomaRecordingPermissionAction

    init(action: RomaRecordingPermissionAction) {
        self.action = action
    }

    public func applyRuntimeState(
        startRecording: @escaping () -> Void,
        presentPermissionDenied: @escaping () -> Void,
        requestPermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        action.applyRuntimeState(
            startRecording: startRecording,
            presentPermissionDenied: presentPermissionDenied,
            requestPermission: requestPermission
        )
    }
}

enum RomaRecordingPermissionSettingsAction: Equatable, Sendable {
    case openSettings(URL)
    case ignore

    func applyRuntimeState(openSettings: (URL) -> Void) {
        switch self {
        case .openSettings(let url):
            openSettings(url)
        case .ignore:
            return
        }
    }
}

public struct RomaRecordingPermissionSettingsPlan: Sendable {
    private let action: RomaRecordingPermissionSettingsAction

    init(action: RomaRecordingPermissionSettingsAction) {
        self.action = action
    }

    public func applyRuntimeState(openSettings: (URL) -> Void) {
        action.applyRuntimeState(openSettings: openSettings)
    }
}

public enum RomaRecordingPermissionPolicy {
    public static func plan(for status: RomaRecordingPermissionStatus) -> RomaRecordingPermissionPlan {
        switch status {
        case .granted:
            return RomaRecordingPermissionPlan(action: .startRecording)
        case .denied:
            return RomaRecordingPermissionPlan(action: .presentPermissionDenied)
        case .undetermined:
            return RomaRecordingPermissionPlan(action: .requestPermission)
        }
    }

    public static func plan(afterPermissionRequestGranted isGranted: Bool) -> RomaRecordingPermissionPlan {
        RomaRecordingPermissionPlan(
            action: isGranted ? .startRecording : .presentPermissionDenied
        )
    }

    public static func settingsOpenPlan(
        settingsURL: URL?,
        canOpenURL: (URL) -> Bool
    ) -> RomaRecordingPermissionSettingsPlan {
        guard let settingsURL, canOpenURL(settingsURL) else {
            return RomaRecordingPermissionSettingsPlan(action: .ignore)
        }

        return RomaRecordingPermissionSettingsPlan(
            action: .openSettings(settingsURL)
        )
    }
}

public struct RomaRecorderProcessingPresentation: Equatable, Sendable {
    public let label: String
    public let progressAnimationInterval: TimeInterval

    public init(
        label: String,
        progressAnimationInterval: TimeInterval
    ) {
        self.label = label
        self.progressAnimationInterval = progressAnimationInterval
    }
}

public struct RomaRecordingFlowState: Equatable, Sendable {
    public static let durationUpdateInterval: TimeInterval = 0.1

    public private(set) var recordingState: RomaRecordingState
    public private(set) var animate: Bool
    public private(set) var isRecordingSheetPresented: Bool
    public private(set) var currentDuration: TimeInterval

    public init(
        recordingState: RomaRecordingState = .idle,
        animate: Bool = false,
        isRecordingSheetPresented: Bool = false,
        currentDuration: TimeInterval = 0
    ) {
        self.recordingState = recordingState
        self.animate = animate
        self.isRecordingSheetPresented = isRecordingSheetPresented
        self.currentDuration = currentDuration
    }

    public mutating func prepareRecordingStart() {
        recordingState = .recording
        animate = true
    }

    public mutating func completeRecordingStart() {
        currentDuration = 0
        isRecordingSheetPresented = true
    }

    public mutating func failRecordingStart() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func finishRecording() {
        recordingState = .idle
        animate = false
        isRecordingSheetPresented = false
    }

    public mutating func cancelRecording() {
        finishRecording()
        currentDuration = 0
    }

    public mutating func setRecordingSheetPresented(_ isPresented: Bool) {
        isRecordingSheetPresented = isPresented
    }

    public mutating func advanceDuration(by interval: TimeInterval = durationUpdateInterval) {
        currentDuration += interval
    }

    public func stopRecordingPlan(audioFileURL: String?) -> RomaRecordingStopPlan {
        var flowStateAfterStop = self
        flowStateAfterStop.finishRecording()

        return RomaRecordingStopPlan(
            flowStateAfterStop: flowStateAfterStop,
            pendingDraft: audioFileURL.map {
                RomaRecordingTranscriptionDraft.pending(
                    duration: currentDuration,
                    audioFileURL: $0
                )
            }
        )
    }

    public func cancelRecordingPlan() -> RomaRecordingCancelPlan {
        var flowStateAfterCancel = self
        flowStateAfterCancel.cancelRecording()
        return RomaRecordingCancelPlan(flowStateAfterCancel: flowStateAfterCancel)
    }
}

public struct RomaRecordingStopPlan: Equatable, Sendable {
    public let flowStateAfterStop: RomaRecordingFlowState
    public let pendingDraft: RomaRecordingTranscriptionDraft?

    public init(
        flowStateAfterStop: RomaRecordingFlowState,
        pendingDraft: RomaRecordingTranscriptionDraft?
    ) {
        self.flowStateAfterStop = flowStateAfterStop
        self.pendingDraft = pendingDraft
    }

    public func applyRuntimeState(
        stopRecorder: () -> Void,
        stopDurationTimer: () -> Void,
        setFlowState: (RomaRecordingFlowState) -> Void,
        updateRecordingState: (Bool) -> Void,
        insertPendingDraft: (RomaRecordingTranscriptionDraft) -> Void
    ) {
        stopRecorder()
        stopDurationTimer()
        setFlowState(flowStateAfterStop)
        updateRecordingState(false)

        if let pendingDraft {
            insertPendingDraft(pendingDraft)
        }
    }
}

public struct RomaRecordingCancelPlan: Equatable, Sendable {
    public let flowStateAfterCancel: RomaRecordingFlowState

    public init(flowStateAfterCancel: RomaRecordingFlowState) {
        self.flowStateAfterCancel = flowStateAfterCancel
    }

    public func applyRuntimeState(
        discardRecorder: () -> Void,
        stopDurationTimer: () -> Void,
        setFlowState: (RomaRecordingFlowState) -> Void,
        updateRecordingState: (Bool) -> Void
    ) {
        discardRecorder()
        stopDurationTimer()
        setFlowState(flowStateAfterCancel)
        updateRecordingState(false)
    }
}

public enum RomaAudioRecorderStopMode: Equatable, Sendable {
    case keepRecordingFile
    case discardRecordingFile
}

public struct RomaAudioRecorderStopPlan: Equatable, Sendable {
    private let shouldStopRecorder: Bool
    private let shouldInvalidateMeterTimer: Bool
    private let isRecordingAfterStop: Bool
    private let shouldClearAudioLevels: Bool
    private let shouldDeleteCurrentRecordingFile: Bool
    private let shouldClearCurrentRecordingURL: Bool
    private let shouldScheduleSessionDeactivation: Bool

    fileprivate init(
        shouldStopRecorder: Bool,
        shouldInvalidateMeterTimer: Bool,
        isRecordingAfterStop: Bool,
        shouldClearAudioLevels: Bool,
        shouldDeleteCurrentRecordingFile: Bool,
        shouldClearCurrentRecordingURL: Bool,
        shouldScheduleSessionDeactivation: Bool
    ) {
        self.shouldStopRecorder = shouldStopRecorder
        self.shouldInvalidateMeterTimer = shouldInvalidateMeterTimer
        self.isRecordingAfterStop = isRecordingAfterStop
        self.shouldClearAudioLevels = shouldClearAudioLevels
        self.shouldDeleteCurrentRecordingFile = shouldDeleteCurrentRecordingFile
        self.shouldClearCurrentRecordingURL = shouldClearCurrentRecordingURL
        self.shouldScheduleSessionDeactivation = shouldScheduleSessionDeactivation
    }

    public func applyRuntimeState(
        stopRecorder: () -> Void,
        invalidateMeterTimer: () -> Void,
        setIsRecording: (Bool) -> Void,
        clearAudioLevels: () -> Void,
        deleteCurrentRecordingFile: () -> Void,
        clearCurrentRecordingURL: () -> Void,
        scheduleSessionDeactivation: () -> Void
    ) {
        if shouldStopRecorder {
            stopRecorder()
        }
        if shouldInvalidateMeterTimer {
            invalidateMeterTimer()
        }
        setIsRecording(isRecordingAfterStop)
        if shouldClearAudioLevels {
            clearAudioLevels()
        }
        if shouldDeleteCurrentRecordingFile {
            deleteCurrentRecordingFile()
        }
        if shouldClearCurrentRecordingURL {
            clearCurrentRecordingURL()
        }
        if shouldScheduleSessionDeactivation {
            scheduleSessionDeactivation()
        }
    }
}

public enum RomaAudioRecorderStopPolicy {
    public static func plan(for mode: RomaAudioRecorderStopMode) -> RomaAudioRecorderStopPlan {
        RomaAudioRecorderStopPlan(
            shouldStopRecorder: true,
            shouldInvalidateMeterTimer: true,
            isRecordingAfterStop: false,
            shouldClearAudioLevels: true,
            shouldDeleteCurrentRecordingFile: mode == .discardRecordingFile,
            shouldClearCurrentRecordingURL: mode == .discardRecordingFile,
            shouldScheduleSessionDeactivation: true
        )
    }
}

public enum RomaAudioRecorderStartFailurePolicy {
    public static let returnedFalseErrorCode = 1001
    public static let errorDomainComponent = "AudioRecorder"
    public static let returnedFalseDescription = "Failed to start AVAudioRecorder. The record() method returned false. This often happens in the background if the audio session is not configured correctly or if there is a conflict with another app."

    public static var returnedFalseErrorDomain: String {
        RomaAppIdentity.errorDomain(component: errorDomainComponent)
    }

    public static var returnedFalseUserInfo: [String: String] {
        [NSLocalizedDescriptionKey: returnedFalseDescription]
    }

    public static func returnedFalseError() -> NSError {
        NSError(
            domain: returnedFalseErrorDomain,
            code: returnedFalseErrorCode,
            userInfo: returnedFalseUserInfo
        )
    }
}

public enum RomaMacOSCoreAudioRecorderDiagnostics {
    public static let assumedLatencySampleRate: Double = 48_000
    public static let unknownValueText = "Unknown"

    public enum TransportKind: Equatable, Sendable {
        case builtIn
        case usb
        case bluetooth
        case bluetoothLE
        case aggregate
        case virtual
        case pci
        case fireWire
        case displayPort
        case hdmi
        case avb
        case thunderbolt
        case other(UInt32)
        case unknown
    }

    public static func knownText(_ text: String?) -> String {
        text ?? unknownValueText
    }

    public static func transportText(_ transportKind: TransportKind) -> String {
        switch transportKind {
        case .builtIn:
            return "Built-in"
        case .usb:
            return "USB"
        case .bluetooth:
            return "Bluetooth"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .aggregate:
            return "Aggregate"
        case .virtual:
            return "Virtual"
        case .pci:
            return "PCI"
        case .fireWire:
            return "FireWire"
        case .displayPort:
            return "DisplayPort"
        case .hdmi:
            return "HDMI"
        case .avb:
            return "AVB"
        case .thunderbolt:
            return "Thunderbolt"
        case .other(let rawValue):
            return "Other (\(rawValue))"
        case .unknown:
            return unknownValueText
        }
    }

    public static func deviceInfoMessage(name: String, uid: String) -> String {
        "🎙️ Device info: name=\(name), uid=\(uid)"
    }

    public static func deviceDetailsMessage(transport: String, manufacturer: String) -> String {
        "🎙️ Device details: transport=\(transport), manufacturer=\(manufacturer)"
    }

    public static func bufferLatencyMilliseconds(bufferFrameSize: UInt32) -> Double {
        (Double(bufferFrameSize) / assumedLatencySampleRate) * 1_000
    }

    public static func bufferLatencyMessage(bufferFrameSize: UInt32) -> String {
        let latencyMilliseconds = bufferLatencyMilliseconds(bufferFrameSize: bufferFrameSize)
        return "🎙️ Buffer size: \(bufferFrameSize) frames, ~latency: \(String(format: "%.1f", latencyMilliseconds))ms"
    }
}

public struct RomaAppGroupRecordingState: Equatable, Sendable {
    public let isRecording: Bool
    public let shouldClearStaleState: Bool

    public init(isRecording: Bool, shouldClearStaleState: Bool) {
        self.isRecording = isRecording
        self.shouldClearStaleState = shouldClearStaleState
    }
}

public struct RomaAppGroupRecordingStateWritePlan: Equatable, Sendable {
    private let isRecording: Bool?
    private let lastRecordingTimestamp: TimeInterval

    init(isRecording: Bool?, lastRecordingTimestamp: TimeInterval) {
        self.isRecording = isRecording
        self.lastRecordingTimestamp = lastRecordingTimestamp
    }

    public func applyRuntimeState(
        setIsRecording: (Bool) -> Void,
        setLastRecordingTimestamp: (TimeInterval) -> Void
    ) {
        if let isRecording {
            setIsRecording(isRecording)
        }

        setLastRecordingTimestamp(lastRecordingTimestamp)
    }
}

public struct RomaAppGroupRecordingStateMutationPlan: Equatable, Sendable {
    private let writePlan: RomaAppGroupRecordingStateWritePlan
    private let darwinNotificationName: String

    init(
        writePlan: RomaAppGroupRecordingStateWritePlan,
        darwinNotificationName: String
    ) {
        self.writePlan = writePlan
        self.darwinNotificationName = darwinNotificationName
    }

    public func applyRuntimeState(
        applyWritePlan: (RomaAppGroupRecordingStateWritePlan) -> Void,
        postDarwinNotification: (String) -> Void
    ) {
        applyWritePlan(writePlan)
        postDarwinNotification(darwinNotificationName)
    }
}

public struct RomaAppGroupRecordingStateReadPlan: Equatable, Sendable {
    private let state: RomaAppGroupRecordingState
    private let staleStateRepairMutationPlan: RomaAppGroupRecordingStateMutationPlan?

    init(
        state: RomaAppGroupRecordingState,
        staleStateRepairMutationPlan: RomaAppGroupRecordingStateMutationPlan?
    ) {
        self.state = state
        self.staleStateRepairMutationPlan = staleStateRepairMutationPlan
    }

    public func applyRuntimeState(
        repairStaleState: (RomaAppGroupRecordingStateMutationPlan) -> Void
    ) -> RomaAppGroupRecordingState {
        if let staleStateRepairMutationPlan {
            repairStaleState(staleStateRepairMutationPlan)
        }

        return state
    }
}

public enum RomaAppGroupRecordingStatePolicy {
    public static let staleRecordingInterval: TimeInterval = 30

    public enum UserDefaultsKey {
        public static let isRecording = "isRecording"
        public static let lastRecordingTimestamp = "lastRecordingTimestamp"
    }

    public static func stopRequestedWritePlan(
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateWritePlan {
        RomaAppGroupRecordingStateWritePlan(
            isRecording: nil,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func stopRequestedMutationPlan(
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateMutationPlan {
        RomaAppGroupRecordingStateMutationPlan(
            writePlan: stopRequestedWritePlan(now: now),
            darwinNotificationName: RomaAppIdentity.iOSStopRecordingDarwinNotificationName
        )
    }

    public static func recordingStateWritePlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateWritePlan {
        RomaAppGroupRecordingStateWritePlan(
            isRecording: isRecording,
            lastRecordingTimestamp: now.timeIntervalSince1970
        )
    }

    public static func recordingStateMutationPlan(
        isRecording: Bool,
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateMutationPlan {
        RomaAppGroupRecordingStateMutationPlan(
            writePlan: recordingStateWritePlan(isRecording: isRecording, now: now),
            darwinNotificationName: RomaAppIdentity.iOSRecordingStateChangedDarwinNotificationName
        )
    }

    public static func state(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> RomaAppGroupRecordingState {
        guard storedIsRecording else {
            return RomaAppGroupRecordingState(
                isRecording: false,
                shouldClearStaleState: false
            )
        }

        let isStale = now.timeIntervalSince1970 - lastRecordingTimestamp > staleRecordingInterval
        return RomaAppGroupRecordingState(
            isRecording: !isStale,
            shouldClearStaleState: isStale
        )
    }

    public static func readPlan(
        storedIsRecording: Bool,
        lastRecordingTimestamp: TimeInterval,
        now: Date = Date()
    ) -> RomaAppGroupRecordingStateReadPlan {
        let currentState = state(
            storedIsRecording: storedIsRecording,
            lastRecordingTimestamp: lastRecordingTimestamp,
            now: now
        )
        let repairMutationPlan: RomaAppGroupRecordingStateMutationPlan?
        if currentState.shouldClearStaleState {
            repairMutationPlan = recordingStateMutationPlan(isRecording: false, now: now)
        } else {
            repairMutationPlan = nil
        }

        return RomaAppGroupRecordingStateReadPlan(
            state: currentState,
            staleStateRepairMutationPlan: repairMutationPlan
        )
    }
}

public enum RomaAppGroupRecordingDiagnostics {
    public static let staleRecordingStateClearedMessage = "Recording state appears stale, clearing it"

    public static func updatedRecordingStateMessage(isRecording: Bool) -> String {
        "Updated recording state: \(isRecording)"
    }
}

public enum RomaIOSRecordingCoordinationDiagnostics {
    public static let clearedStaleRecordingStateOnLaunchMessage = "Cleared stale recording state on app launch"
    public static let recordDeepLinkOpenedMessage = "URL scheme triggered: open app for recording"
    public static let keyboardRecordingRequestOpenedMessage = "App opened via keyboard extension - recording requested"
    public static let recordingManagerInitializedMessage = "RecordingManager initialized"
    public static let keyboardStopRecordingRequestedMessage = "Stop recording requested from keyboard extension"
}

public enum RomaKeyboardRecordingTiming {
    public static let appLaunchRecordingStartDelay: TimeInterval = 0.5
    public static let recordingStatusPollingInterval: TimeInterval = 0.5
    public static let openAppFallbackResetDelay: TimeInterval = 2.0
}

enum RomaLaunchRecordingRequestAction: Equatable, Sendable {
    case none
    case deferUntilOnboardingCompletes
    case startRecordingAfterLaunchDelay

    func applyRuntimeState(startRecordingAfterLaunchDelay: () -> Void) {
        switch self {
        case .none, .deferUntilOnboardingCompletes:
            return
        case .startRecordingAfterLaunchDelay:
            startRecordingAfterLaunchDelay()
        }
    }
}

public struct RomaLaunchRecordingRequestPlan: Sendable {
    private let action: RomaLaunchRecordingRequestAction

    init(action: RomaLaunchRecordingRequestAction) {
        self.action = action
    }

    public func applyRuntimeState(startRecordingAfterLaunchDelay: () -> Void) {
        action.applyRuntimeState(startRecordingAfterLaunchDelay: startRecordingAfterLaunchDelay)
    }
}

public struct RomaLaunchRecordingRequestState: Equatable, Sendable {
    public private(set) var hasPendingRecordingAfterOnboarding: Bool

    public init(hasPendingRecordingAfterOnboarding: Bool = false) {
        self.hasPendingRecordingAfterOnboarding = hasPendingRecordingAfterOnboarding
    }

    public mutating func requestRecording(
        hasCompletedOnboarding: Bool
    ) -> RomaLaunchRecordingRequestPlan {
        guard hasCompletedOnboarding else {
            hasPendingRecordingAfterOnboarding = true
            return RomaLaunchRecordingRequestPlan(action: .deferUntilOnboardingCompletes)
        }

        hasPendingRecordingAfterOnboarding = false
        return RomaLaunchRecordingRequestPlan(action: .startRecordingAfterLaunchDelay)
    }

    public mutating func consumePendingRecordingIfReady(
        hasCompletedOnboarding: Bool
    ) -> RomaLaunchRecordingRequestPlan {
        guard hasCompletedOnboarding, hasPendingRecordingAfterOnboarding else {
            return RomaLaunchRecordingRequestPlan(action: .none)
        }

        hasPendingRecordingAfterOnboarding = false
        return RomaLaunchRecordingRequestPlan(action: .startRecordingAfterLaunchDelay)
    }
}

public struct RomaKeyboardRecordingButtonPresentation: Equatable, Sendable {
    public let title: String
    public let systemImageName: String

    public init(title: String, systemImageName: String) {
        self.title = title
        self.systemImageName = systemImageName
    }

    public static let idle = RomaKeyboardRecordingButtonPresentation(
        title: " Record",
        systemImageName: "mic.fill"
    )

    public static let recording = RomaKeyboardRecordingButtonPresentation(
        title: " Stop",
        systemImageName: "stop.fill"
    )

    public static let openAppFallback = RomaKeyboardRecordingButtonPresentation(
        title: " Open \(RomaAppIdentity.displayName)",
        systemImageName: "app"
    )

    public static let transcribing = RomaKeyboardRecordingButtonPresentation(
        title: " Transcribing",
        systemImageName: "ellipsis"
    )

    public static let returnToOriginalField = RomaKeyboardRecordingButtonPresentation(
        title: " Return to Text Field",
        systemImageName: "arrow.uturn.backward"
    )

    public static let transcriptionFailed = RomaKeyboardRecordingButtonPresentation(
        title: " Try Again",
        systemImageName: "exclamationmark.triangle.fill"
    )

    public static let fullAccessRequired = RomaKeyboardRecordingButtonPresentation(
        title: " Enable Full Access",
        systemImageName: "lock.fill"
    )

    public static func current(isRecording: Bool) -> RomaKeyboardRecordingButtonPresentation {
        isRecording ? recording : idle
    }
}

enum RomaKeyboardRecordingButtonTapAction: Equatable, Sendable {
    case requestStopRecording
    case openMainAppForRecording
}

public struct RomaKeyboardRecordingButtonTapPlan: Sendable {
    private let action: RomaKeyboardRecordingButtonTapAction
    private let shouldRefreshButtonStateAfterAction: Bool

    init(
        action: RomaKeyboardRecordingButtonTapAction,
        shouldRefreshButtonStateAfterAction: Bool
    ) {
        self.action = action
        self.shouldRefreshButtonStateAfterAction = shouldRefreshButtonStateAfterAction
    }

    public func applyRuntimeState(
        requestStopRecording: () -> Void,
        openMainAppForRecording: () -> Void,
        refreshButtonState: () -> Void
    ) {
        switch action {
        case .requestStopRecording:
            requestStopRecording()
            if shouldRefreshButtonStateAfterAction {
                refreshButtonState()
            }
        case .openMainAppForRecording:
            openMainAppForRecording()
        }
    }
}

public enum RomaKeyboardRecordingButtonTapPolicy {
    public static func plan(isRecording: Bool) -> RomaKeyboardRecordingButtonTapPlan {
        if isRecording {
            return RomaKeyboardRecordingButtonTapPlan(
                action: .requestStopRecording,
                shouldRefreshButtonStateAfterAction: true
            )
        }

        return RomaKeyboardRecordingButtonTapPlan(
            action: .openMainAppForRecording,
            shouldRefreshButtonStateAfterAction: false
        )
    }
}

enum RomaKeyboardOpenAppAction: Equatable, Sendable {
    case openExtensionContext
    case openThroughApplicationOrResponderChain
    case finish
    case showFallback

    func applyRuntimeState(
        openExtensionContext: () -> Void,
        openThroughApplicationOrResponderChain: () -> Void,
        finish: () -> Void,
        showFallback: () -> Void
    ) {
        switch self {
        case .openExtensionContext:
            openExtensionContext()
        case .openThroughApplicationOrResponderChain:
            openThroughApplicationOrResponderChain()
        case .finish:
            finish()
        case .showFallback:
            showFallback()
        }
    }
}

enum RomaKeyboardOpenAppDiagnosticLevel: Equatable, Sendable {
    case notice
    case error
}

enum RomaKeyboardOpenAppDiagnosticTiming: Equatable, Sendable {
    case beforeAction
    case afterAction
}

struct RomaKeyboardOpenAppDiagnosticEvent: Equatable, Sendable {
    let level: RomaKeyboardOpenAppDiagnosticLevel
    let message: String

    init(level: RomaKeyboardOpenAppDiagnosticLevel, message: String) {
        self.level = level
        self.message = message
    }

    func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void
    ) {
        switch level {
        case .notice:
            logNotice(message)
        case .error:
            logError(message)
        }
    }
}

public struct RomaKeyboardOpenAppActionPlan: Sendable {
    private let action: RomaKeyboardOpenAppAction
    private let diagnosticEvent: RomaKeyboardOpenAppDiagnosticEvent?
    private let diagnosticTiming: RomaKeyboardOpenAppDiagnosticTiming

    init(
        action: RomaKeyboardOpenAppAction,
        diagnosticEvent: RomaKeyboardOpenAppDiagnosticEvent? = nil,
        diagnosticTiming: RomaKeyboardOpenAppDiagnosticTiming = .beforeAction
    ) {
        self.action = action
        self.diagnosticEvent = diagnosticEvent
        self.diagnosticTiming = diagnosticTiming
    }

    public func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void,
        openExtensionContext: () -> Void,
        openThroughApplicationOrResponderChain: () -> Void,
        finish: () -> Void,
        showFallback: () -> Void
    ) {
        if diagnosticTiming == .beforeAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }

        action.applyRuntimeState(
            openExtensionContext: openExtensionContext,
            openThroughApplicationOrResponderChain: openThroughApplicationOrResponderChain,
            finish: finish,
            showFallback: showFallback
        )

        if diagnosticTiming == .afterAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }
    }
}

enum RomaKeyboardOpenAppApplicationAction: Equatable, Sendable {
    case openViaApplication
    case openViaResponderChain

    func applyRuntimeState(
        openViaApplication: () -> Void,
        openViaResponderChain: () -> Void
    ) {
        switch self {
        case .openViaApplication:
            openViaApplication()
        case .openViaResponderChain:
            openViaResponderChain()
        }
    }
}

enum RomaKeyboardOpenAppResponderAction: Equatable, Sendable {
    case performResponderChainOpen
    case showFallback

    func applyRuntimeState(
        performResponderChainOpen: () -> Void,
        showFallback: () -> Void
    ) {
        switch self {
        case .performResponderChainOpen:
            performResponderChainOpen()
        case .showFallback:
            showFallback()
        }
    }
}

public struct RomaKeyboardOpenAppApplicationActionPlan: Sendable {
    private let action: RomaKeyboardOpenAppApplicationAction

    init(action: RomaKeyboardOpenAppApplicationAction) {
        self.action = action
    }

    public func applyRuntimeState(
        openViaApplication: () -> Void,
        openViaResponderChain: () -> Void
    ) {
        action.applyRuntimeState(
            openViaApplication: openViaApplication,
            openViaResponderChain: openViaResponderChain
        )
    }
}

public struct RomaKeyboardOpenAppResponderActionPlan: Sendable {
    private let action: RomaKeyboardOpenAppResponderAction
    private let diagnosticEvent: RomaKeyboardOpenAppDiagnosticEvent?
    private let diagnosticTiming: RomaKeyboardOpenAppDiagnosticTiming

    init(
        action: RomaKeyboardOpenAppResponderAction,
        diagnosticEvent: RomaKeyboardOpenAppDiagnosticEvent? = nil,
        diagnosticTiming: RomaKeyboardOpenAppDiagnosticTiming = .beforeAction
    ) {
        self.action = action
        self.diagnosticEvent = diagnosticEvent
        self.diagnosticTiming = diagnosticTiming
    }

    public func applyRuntimeState(
        logNotice: (String) -> Void,
        logError: (String) -> Void,
        performResponderChainOpen: () -> Void,
        showFallback: () -> Void
    ) {
        if diagnosticTiming == .beforeAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }

        action.applyRuntimeState(
            performResponderChainOpen: performResponderChainOpen,
            showFallback: showFallback
        )

        if diagnosticTiming == .afterAction {
            diagnosticEvent?.applyRuntimeState(logNotice: logNotice, logError: logError)
        }
    }
}

public enum RomaKeyboardOpenAppPolicy {
    private static func notice(_ message: String) -> RomaKeyboardOpenAppDiagnosticEvent {
        RomaKeyboardOpenAppDiagnosticEvent(level: .notice, message: message)
    }

    private static func error(_ message: String) -> RomaKeyboardOpenAppDiagnosticEvent {
        RomaKeyboardOpenAppDiagnosticEvent(level: .error, message: message)
    }

    public static func initialActionPlan(hasExtensionContext: Bool) -> RomaKeyboardOpenAppActionPlan {
        hasExtensionContext
            ? RomaKeyboardOpenAppActionPlan(action: .openExtensionContext)
            : RomaKeyboardOpenAppActionPlan(
                action: .openThroughApplicationOrResponderChain,
                diagnosticEvent: error(RomaKeyboardOpenAppDiagnostics.extensionContextUnavailable)
            )
    }

    public static func actionPlanAfterExtensionContextOpen(
        succeeded: Bool
    ) -> RomaKeyboardOpenAppActionPlan {
        succeeded
            ? RomaKeyboardOpenAppActionPlan(
                action: .finish,
                diagnosticEvent: notice(RomaKeyboardOpenAppDiagnostics.openedViaExtensionContext)
            )
            : RomaKeyboardOpenAppActionPlan(
                action: .openThroughApplicationOrResponderChain,
                diagnosticEvent: error(RomaKeyboardOpenAppDiagnostics.extensionContextOpenFailed)
            )
    }

    public static func applicationActionPlan(
        canOpenURL: Bool
    ) -> RomaKeyboardOpenAppApplicationActionPlan {
        RomaKeyboardOpenAppApplicationActionPlan(
            action: canOpenURL ? .openViaApplication : .openViaResponderChain
        )
    }

    public static func actionPlanAfterApplicationOpen(
        succeeded: Bool
    ) -> RomaKeyboardOpenAppActionPlan {
        succeeded
            ? RomaKeyboardOpenAppActionPlan(
                action: .finish,
                diagnosticEvent: notice(RomaKeyboardOpenAppDiagnostics.openedViaApplication)
            )
            : RomaKeyboardOpenAppActionPlan(
                action: .showFallback,
                diagnosticEvent: error(RomaKeyboardOpenAppDiagnostics.applicationOpenFailed)
            )
    }

    public static func responderActionPlan(
        hasResponder: Bool
    ) -> RomaKeyboardOpenAppResponderActionPlan {
        hasResponder
            ? RomaKeyboardOpenAppResponderActionPlan(
                action: .performResponderChainOpen,
                diagnosticEvent: notice(RomaKeyboardOpenAppDiagnostics.attemptedViaResponderChain),
                diagnosticTiming: .afterAction
            )
            : RomaKeyboardOpenAppResponderActionPlan(
                action: .showFallback,
                diagnosticEvent: error(RomaKeyboardOpenAppDiagnostics.allMethodsFailed)
            )
    }

}

public enum RomaKeyboardOpenAppDiagnostics {
    public static let extensionContextUnavailable = "extensionContext unavailable, trying alternative methods"
    public static let openedViaExtensionContext = "Opened main app via extensionContext"
    public static let extensionContextOpenFailed = "extensionContext.open failed, trying alternative methods"
    public static let openedViaApplication = "Opened main app via UIApplication.open"
    public static let applicationOpenFailed = "UIApplication.open failed"
    public static let attemptedViaResponderChain = "Attempted to open main app via responder chain"
    public static let allMethodsFailed = "All URL opening methods failed"
}

enum RomaKeyboardStopRecordingRequestAction: Equatable, Sendable {
    case handleStopRequest
    case ignore

    func applyRuntimeState(handleStopRequest: () -> Void) {
        switch self {
        case .handleStopRequest:
            handleStopRequest()
        case .ignore:
            return
        }
    }
}

public struct RomaKeyboardStopRecordingRequestPlan: Sendable {
    private let action: RomaKeyboardStopRecordingRequestAction

    init(action: RomaKeyboardStopRecordingRequestAction) {
        self.action = action
    }

    public func applyRuntimeState(handleStopRequest: () -> Void) {
        action.applyRuntimeState(handleStopRequest: handleStopRequest)
    }
}

public enum RomaKeyboardStopRecordingRequestPolicy {
    public static func plan(
        recordingState: RomaRecordingState
    ) -> RomaKeyboardStopRecordingRequestPlan {
        RomaKeyboardStopRecordingRequestPlan(
            action: recordingState.isActivelyRecording ? .handleStopRequest : .ignore
        )
    }
}

public enum RomaRecorderStyle: String, CaseIterable, Identifiable, Sendable {
    case none
    case notch
    case mini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .notch:
            return "Notch"
        case .mini:
            return "Mini"
        }
    }
}

enum RomaRecorderWindowKind: Equatable, Sendable {
    case none
    case notch
    case mini

    func applyRuntimeState(
        none: () -> Void,
        notch: () -> Void,
        mini: () -> Void
    ) {
        switch self {
        case .none:
            none()
        case .notch:
            notch()
        case .mini:
            mini()
        }
    }
}

public struct RomaMacOSRecorderStyleSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let pickerTitle: String

    public init(sectionTitle: String, pickerTitle: String) {
        self.sectionTitle = sectionTitle
        self.pickerTitle = pickerTitle
    }
}

public enum RomaRecorderStylePreference {
    public static let userDefaultsKey = "RecorderType"
    public static let defaultStyle: RomaRecorderStyle = .none
    public static let defaultRawValue = defaultStyle.rawValue
    public static let macOSSettingsPresentation = RomaMacOSRecorderStyleSettingsPresentation(
        sectionTitle: "Interface",
        pickerTitle: "Recorder Style"
    )

    public static func rawValue(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: userDefaultsKey) ?? defaultRawValue
    }

    public static func saveRawValue(
        _ rawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(rawValue, forKey: userDefaultsKey)
    }

    static func windowKind(forRawValue rawValue: String) -> RomaRecorderWindowKind {
        switch rawValue {
        case RomaRecorderStyle.none.rawValue:
            return .none
        case RomaRecorderStyle.notch.rawValue:
            return .notch
        default:
            return .mini
        }
    }

    public static func hasVisibleRecorder(rawValue: String) -> Bool {
        windowKind(forRawValue: rawValue) != .none
    }

    public static func applyWindowRuntimeState(
        forRawValue rawValue: String,
        none: () -> Void = {},
        notch: () -> Void,
        mini: () -> Void
    ) {
        windowKind(forRawValue: rawValue).applyRuntimeState(
            none: none,
            notch: notch,
            mini: mini
        )
    }
}

public struct RomaRecordingSheetPresentation: Equatable, Sendable {
    public let cancelButtonTitle: String
    public let stopButtonTitle: String
    public let stopButtonSystemImageName: String

    public static let iOS = RomaRecordingSheetPresentation(
        cancelButtonTitle: "Cancel",
        stopButtonTitle: "Stop Recording",
        stopButtonSystemImageName: "stop.fill"
    )
}

public struct RomaRecordingNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public let actionButtonTitle: String?

    public init(
        title: String,
        duration: TimeInterval = 3.0,
        actionButtonTitle: String? = nil
    ) {
        self.title = title
        self.duration = duration
        self.actionButtonTitle = actionButtonTitle
    }

    public static let noTranscriptionModelSelected = RomaRecordingNotificationPresentation(
        title: "No AI Model Selected"
    )

    public static let failedToStart = RomaRecordingNotificationPresentation(
        title: "Recording failed to start"
    )

    public static let microphonePermissionRequired = RomaRecordingNotificationPresentation(
        title: "Microphone permission required",
        duration: 8.0,
        actionButtonTitle: "Grant"
    )

    public static func runtimeFailure(localizedDescription: String) -> RomaRecordingNotificationPresentation {
        RomaRecordingNotificationPresentation(
            title: "Recording Failed: \(localizedDescription)"
        )
    }
}

public struct RomaRecordingAlertPresentation: Equatable, Identifiable, Sendable {
    enum Action: Equatable, Sendable {
        case dismiss
        case openSettings

        func runtimeAction(
            openSettings: @escaping () -> Void
        ) -> (() -> Void)? {
            switch self {
            case .dismiss:
                return nil
            case .openSettings:
                return openSettings
            }
        }
    }

    public static let microphoneInUseOSStatusCode = 561017449
    public static let iOSRecorderStartReturnedFalseDescription = RomaAudioRecorderStartFailurePolicy.returnedFalseDescription

    public let id: String
    public let title: String
    public let message: String
    public let primaryButtonTitle: String
    public let secondaryButtonTitle: String?
    let action: Action

    init(
        id: String,
        title: String,
        message: String,
        primaryButtonTitle: String = "OK",
        secondaryButtonTitle: String? = nil,
        action: Action = .dismiss
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.action = action
    }

    public func runtimeAction(
        openSettings: @escaping () -> Void
    ) -> (() -> Void)? {
        action.runtimeAction(openSettings: openSettings)
    }

    public static var noModesAvailable: RomaRecordingAlertPresentation {
        RomaRecordingAlertPresentation(
            id: "noModesAvailable",
            title: "No Modes Found",
            message: "Please create a new mode in Settings before recording."
        )
    }

    public static var microphonePermissionDenied: RomaRecordingAlertPresentation {
        RomaRecordingAlertPresentation(
            id: "microphonePermissionDenied",
            title: "Microphone Access Denied",
            message: "To record audio, please grant microphone access in Settings.",
            primaryButtonTitle: "Settings",
            secondaryButtonTitle: "Cancel",
            action: .openSettings
        )
    }

    public static var microphoneInUse: RomaRecordingAlertPresentation {
        RomaRecordingAlertPresentation(
            id: "microphoneInUse",
            title: "Microphone In Use",
            message: "Another app is using the microphone. Please try again."
        )
    }

    public static func recordingFailed(localizedDescription: String) -> RomaRecordingAlertPresentation {
        RomaRecordingAlertPresentation(
            id: "recordingFailed-\(localizedDescription)",
            title: "Recording Failed",
            message: "Could not start recording: \(localizedDescription)"
        )
    }

    public static func recordingStartFailure(
        domain: String,
        code: Int,
        localizedDescription: String
    ) -> RomaRecordingAlertPresentation {
        if domain == NSOSStatusErrorDomain && code == microphoneInUseOSStatusCode {
            return microphoneInUse
        }

        return recordingFailed(localizedDescription: localizedDescription)
    }

    public static func recordingStartFailure(for error: Error) -> RomaRecordingAlertPresentation {
        let nsError = error as NSError
        return recordingStartFailure(
            domain: nsError.domain,
            code: nsError.code,
            localizedDescription: error.localizedDescription
        )
    }
}

enum RomaRecordingStartAction: Equatable, Sendable {
    case startRecording
    case presentAlert(RomaRecordingAlertPresentation)

    func applyRuntimeState(
        startRecording: () -> Void,
        presentAlert: (RomaRecordingAlertPresentation) -> Void
    ) {
        switch self {
        case .startRecording:
            startRecording()
        case .presentAlert(let alert):
            presentAlert(alert)
        }
    }
}

public struct RomaRecordingStartPlan: Sendable {
    private let action: RomaRecordingStartAction

    init(action: RomaRecordingStartAction) {
        self.action = action
    }

    public func applyRuntimeState(
        startRecording: () -> Void,
        presentAlert: (RomaRecordingAlertPresentation) -> Void
    ) {
        action.applyRuntimeState(
            startRecording: startRecording,
            presentAlert: presentAlert
        )
    }
}

public enum RomaRecordingStartPolicy {
    public static func plan(modeCount: Int) -> RomaRecordingStartPlan {
        RomaRecordingStartPlan(
            action: modeCount <= 0 ? .presentAlert(.noModesAvailable) : .startRecording
        )
    }
}

public struct RomaMacOSRecordingCancellationPlan: Equatable, Sendable {
    private let shouldClearDeferredStopRequest: Bool
    private let shouldRequestRecordingCancellation: Bool
    private let shouldFinishActiveRecorderCancellation: Bool
    private let shouldClearPartialTranscript: Bool
    private let shouldClearCancelFlag: Bool
    private let recordingStateAfterImmediateCancel: RomaRecordingState?
    private let shouldFinishRecorderSessionImmediately: Bool

    fileprivate init(
        shouldClearDeferredStopRequest: Bool,
        shouldRequestRecordingCancellation: Bool,
        shouldFinishActiveRecorderCancellation: Bool,
        shouldClearPartialTranscript: Bool,
        shouldClearCancelFlag: Bool,
        recordingStateAfterImmediateCancel: RomaRecordingState?,
        shouldFinishRecorderSessionImmediately: Bool
    ) {
        self.shouldClearDeferredStopRequest = shouldClearDeferredStopRequest
        self.shouldRequestRecordingCancellation = shouldRequestRecordingCancellation
        self.shouldFinishActiveRecorderCancellation = shouldFinishActiveRecorderCancellation
        self.shouldClearPartialTranscript = shouldClearPartialTranscript
        self.shouldClearCancelFlag = shouldClearCancelFlag
        self.recordingStateAfterImmediateCancel = recordingStateAfterImmediateCancel
        self.shouldFinishRecorderSessionImmediately = shouldFinishRecorderSessionImmediately
    }

    @MainActor
    public func applyRuntimeState(
        clearDeferredStopRequest: @MainActor () -> Void,
        requestRecordingCancellation: @MainActor () -> Void,
        finishActiveRecorderCancellation: @MainActor () async -> Void,
        clearPartialTranscript: @MainActor () -> Void,
        clearCancelFlag: @MainActor () -> Void,
        setRecordingState: @MainActor (RomaRecordingState) -> Void,
        finishRecorderSessionImmediately: @MainActor () async -> Void
    ) async {
        if shouldClearDeferredStopRequest {
            clearDeferredStopRequest()
        }

        if shouldRequestRecordingCancellation {
            requestRecordingCancellation()
        }

        if shouldFinishActiveRecorderCancellation {
            await finishActiveRecorderCancellation()
        }

        if shouldClearPartialTranscript {
            clearPartialTranscript()
        }

        if shouldClearCancelFlag {
            clearCancelFlag()
        }

        if let recordingStateAfterImmediateCancel {
            setRecordingState(recordingStateAfterImmediateCancel)
        }

        if shouldFinishRecorderSessionImmediately {
            await finishRecorderSessionImmediately()
        }
    }
}

public enum RomaMacOSRecordingCancellationPolicy {
    public static func plan(
        recordingState: RomaRecordingState
    ) -> RomaMacOSRecordingCancellationPlan {
        if recordingState.isRecorderCaptureInProgress {
            return RomaMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: true,
                shouldClearPartialTranscript: false,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: nil,
                shouldFinishRecorderSessionImmediately: true
            )
        }

        if recordingState.isPostRecordingProcessing {
            return RomaMacOSRecordingCancellationPlan(
                shouldClearDeferredStopRequest: true,
                shouldRequestRecordingCancellation: true,
                shouldFinishActiveRecorderCancellation: false,
                shouldClearPartialTranscript: true,
                shouldClearCancelFlag: false,
                recordingStateAfterImmediateCancel: .idle,
                shouldFinishRecorderSessionImmediately: false
            )
        }

        return RomaMacOSRecordingCancellationPlan(
            shouldClearDeferredStopRequest: true,
            shouldRequestRecordingCancellation: false,
            shouldFinishActiveRecorderCancellation: false,
            shouldClearPartialTranscript: true,
            shouldClearCancelFlag: true,
            recordingStateAfterImmediateCancel: .idle,
            shouldFinishRecorderSessionImmediately: true
        )
    }
}

public struct RomaMacOSRecordingStartupOrchestrationPlan: Equatable, Sendable {
    public let shouldResolvePowerMode: Bool
    public let shouldPrepareTranscriptionSessionBeforeRecorder: Bool

    public init(
        shouldResolvePowerMode: Bool,
        shouldPrepareTranscriptionSessionBeforeRecorder: Bool
    ) {
        self.shouldResolvePowerMode = shouldResolvePowerMode
        self.shouldPrepareTranscriptionSessionBeforeRecorder = shouldPrepareTranscriptionSessionBeforeRecorder
    }
}

public enum RomaMacOSRecordingStartupOrchestrationPolicy {
    public static func plan(
        powerModeConfigurationCount: Int
    ) -> RomaMacOSRecordingStartupOrchestrationPlan {
        let shouldResolvePowerMode = powerModeConfigurationCount > 0
        return RomaMacOSRecordingStartupOrchestrationPlan(
            shouldResolvePowerMode: shouldResolvePowerMode,
            shouldPrepareTranscriptionSessionBeforeRecorder: !shouldResolvePowerMode
        )
    }
}

public extension RomaRecordingState {
    var isActivelyRecording: Bool {
        self == .recording
    }

    var isRecorderCaptureInProgress: Bool {
        self == .starting || self == .recording
    }

    var acceptsRecordingShortcutAction: Bool {
        self != .transcribing &&
        self != .enhancing &&
        self != .busy
    }

    var isPostRecordingProcessing: Bool {
        recorderProcessingPresentation != nil
    }

    var isRecorderDismissCancelable: Bool {
        switch self {
        case .starting, .recording, .transcribing, .enhancing:
            return true
        case .idle, .busy:
            return false
        }
    }

    var shouldReturnToIdleWhenActivePipelineFinishes: Bool {
        isPostRecordingProcessing || self == .busy
    }

    private var recorderUIToggleAction: RomaRecorderUIToggleAction {
        switch self {
        case .recording, .starting:
            return .toggleRecord
        case .transcribing, .enhancing:
            return .cancelRecording
        case .idle, .busy:
            return .dismissRecorder
        }
    }

    @MainActor
    func applyRecorderUIToggleRuntimeState(
        toggleRecord: @MainActor () async -> Void,
        cancelRecording: @MainActor () async -> Void,
        dismissRecorder: @MainActor () async -> Void
    ) async {
        switch recorderUIToggleAction {
        case .toggleRecord:
            await toggleRecord()
        case .cancelRecording:
            await cancelRecording()
        case .dismissRecorder:
            await dismissRecorder()
        }
    }

    var recorderProcessingPresentation: RomaRecorderProcessingPresentation? {
        switch self {
        case .transcribing:
            return RomaRecorderProcessingPresentation(
                label: "Transcribing",
                progressAnimationInterval: 0.18
            )
        case .enhancing:
            return RomaRecorderProcessingPresentation(
                label: "Enhancing",
                progressAnimationInterval: 0.22
            )
        case .idle, .starting, .recording, .busy:
            return nil
        }
    }
}

public enum RomaRecorderUISessionPolicy {
    public static func isActiveForRecordingShortcut(
        hasVisibleRecorderType: Bool,
        recordingState: RomaRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        if !hasVisibleRecorderType, recordingState == .idle {
            return false
        }

        return isRecorderSessionActive
    }

    public static func shouldClearStaleHiddenRecorderSession(
        hasVisibleRecorderType: Bool,
        recordingState: RomaRecordingState,
        isRecorderSessionActive: Bool
    ) -> Bool {
        !hasVisibleRecorderType && isRecorderSessionActive && recordingState == .idle
    }
}
