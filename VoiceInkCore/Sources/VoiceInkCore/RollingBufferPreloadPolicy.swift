import Foundation

public enum VoiceInkRollingBufferPreloadMode: String, CaseIterable, Identifiable, Sendable {
    case on
    case off
    case auto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .on:
            return "On"
        case .off:
            return "Off"
        case .auto:
            return "Auto"
        }
    }
}

public struct VoiceInkRollingBufferPreloadConfiguration: Equatable, Sendable {
    public let mode: VoiceInkRollingBufferPreloadMode
    public let autoDisablesCloudModels: Bool
    public let autoDisablesLowBatteryLocalModels: Bool
    public let lowBatteryThresholdPercent: Int
    public let bufferDurationSeconds: Double
    public let preRunFinalization: Bool

    public init(
        mode: VoiceInkRollingBufferPreloadMode,
        autoDisablesCloudModels: Bool,
        autoDisablesLowBatteryLocalModels: Bool,
        lowBatteryThresholdPercent: Int,
        bufferDurationSeconds: Double,
        preRunFinalization: Bool
    ) {
        self.mode = mode
        self.autoDisablesCloudModels = autoDisablesCloudModels
        self.autoDisablesLowBatteryLocalModels = autoDisablesLowBatteryLocalModels
        self.lowBatteryThresholdPercent = min(max(lowBatteryThresholdPercent, 1), 100)
        self.bufferDurationSeconds = min(max(bufferDurationSeconds, 0.25), 30.0)
        self.preRunFinalization = preRunFinalization
    }
}

public struct VoiceInkRollingBufferPowerState: Equatable, Sendable {
    public let isOnBattery: Bool
    public let batteryLevelPercent: Int?

    public init(isOnBattery: Bool, batteryLevelPercent: Int?) {
        self.isOnBattery = isOnBattery
        self.batteryLevelPercent = batteryLevelPercent
    }
}

public struct VoiceInkRollingBufferPreloadModelSnapshot: Equatable, Sendable {
    public let supportsStreaming: Bool
    public let isCloudTranscriptionProvider: Bool

    public var isLocalTranscriptionProvider: Bool {
        !isCloudTranscriptionProvider
    }

    public init(
        supportsStreaming: Bool,
        isCloudTranscriptionProvider: Bool
    ) {
        self.supportsStreaming = supportsStreaming
        self.isCloudTranscriptionProvider = isCloudTranscriptionProvider
    }
}

public enum VoiceInkRollingBufferPreloadSettings {
    public static let modeKey = "RollingBufferPreloadMode"
    public static let autoDisableCloudModelsKey = "RollingBufferPreloadAutoDisableCloudModels"
    public static let autoDisableLowBatteryLocalModelsKey = "RollingBufferPreloadAutoDisableLowBatteryLocalModels"
    public static let lowBatteryThresholdPercentKey = "RollingBufferPreloadLowBatteryThresholdPercent"
    public static let bufferDurationSecondsKey = "RollingBufferDurationSeconds"
    public static let preRunFinalizationKey = "RollingBufferPreloadFinalization"
    public static let perModelEnabledKeyPrefix = "rolling-buffer-preload-enabled-"

    public static let defaultMode: VoiceInkRollingBufferPreloadMode = .auto
    public static let defaultAutoDisablesCloudModels = false
    public static let defaultAutoDisablesLowBatteryLocalModels = true
    public static let defaultLowBatteryThresholdPercent = 40
    public static let defaultBufferDurationSeconds = 3.0
    public static let defaultPreRunFinalization = true

    public static func configuration(in defaults: UserDefaults = .standard) -> VoiceInkRollingBufferPreloadConfiguration {
        let mode = defaults.string(forKey: modeKey)
            .flatMap(VoiceInkRollingBufferPreloadMode.init(rawValue:))
            ?? defaultMode
        let cloudGuard = defaults.object(forKey: autoDisableCloudModelsKey) as? Bool
            ?? defaultAutoDisablesCloudModels
        let lowBatteryGuard = defaults.object(forKey: autoDisableLowBatteryLocalModelsKey) as? Bool
            ?? defaultAutoDisablesLowBatteryLocalModels
        let storedThreshold = defaults.object(forKey: lowBatteryThresholdPercentKey) as? Int
            ?? defaultLowBatteryThresholdPercent
        let duration = defaults.object(forKey: bufferDurationSecondsKey) as? Double
            ?? defaultBufferDurationSeconds
        let preRunFinalization = defaults.object(forKey: preRunFinalizationKey) as? Bool
            ?? defaultPreRunFinalization

        return VoiceInkRollingBufferPreloadConfiguration(
            mode: mode,
            autoDisablesCloudModels: cloudGuard,
            autoDisablesLowBatteryLocalModels: lowBatteryGuard,
            lowBatteryThresholdPercent: storedThreshold,
            bufferDurationSeconds: duration,
            preRunFinalization: preRunFinalization
        )
    }

    public static func perModelPreloadEnabled(
        forModelName modelName: String,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: perModelPreloadEnabledKey(forModelName: modelName)) as? Bool ?? true
    }

    public static func perModelPreloadEnabledKey(forModelName modelName: String) -> String {
        "\(perModelEnabledKeyPrefix)\(modelName)"
    }
}

public struct VoiceInkRollingBufferPreloadPolicy {
    public let configuration: VoiceInkRollingBufferPreloadConfiguration
    public let powerState: VoiceInkRollingBufferPowerState

    public init(
        configuration: VoiceInkRollingBufferPreloadConfiguration,
        powerState: VoiceInkRollingBufferPowerState
    ) {
        self.configuration = configuration
        self.powerState = powerState
    }

    public init(defaults: UserDefaults = .standard, powerState: VoiceInkRollingBufferPowerState) {
        self.init(
            configuration: VoiceInkRollingBufferPreloadSettings.configuration(in: defaults),
            powerState: powerState
        )
    }

    public func allowsPreload(
        for model: VoiceInkRollingBufferPreloadModelSnapshot,
        perModelEnabled: Bool
    ) -> Bool {
        guard model.supportsStreaming else { return false }
        guard perModelEnabled else { return false }

        switch configuration.mode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            if configuration.autoDisablesCloudModels, model.isCloudTranscriptionProvider {
                return false
            }

            if configuration.autoDisablesLowBatteryLocalModels,
               model.isLocalTranscriptionProvider,
               powerState.isOnBattery,
               let batteryLevel = powerState.batteryLevelPercent,
               batteryLevel < configuration.lowBatteryThresholdPercent {
                return false
            }

            return true
        }
    }
}
