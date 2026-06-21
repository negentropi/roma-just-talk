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

public struct VoiceInkRollingBufferPreloadSettingsPresentation: Equatable, Sendable {
    public let sectionTitle: String
    public let modePickerTitle: String
    public let modePickerHelp: String
    public let durationLabel: String
    public let durationUnitLabel: String
    public let preRunFinalizationTitle: String
    public let preRunFinalizationHelp: String
    public let vadModelPickerTitle: String
    public let vadModelPickerHelp: String
    public let autoDisableCloudModelsTitle: String
    public let autoDisableCloudModelsHelp: String
    public let autoDisableLowBatteryLocalModelsTitle: String
    public let autoDisableLowBatteryLocalModelsHelp: String

    public static let macOS = VoiceInkRollingBufferPreloadSettingsPresentation(
        sectionTitle: "Rolling Buffer",
        modePickerTitle: "Buffer Preload",
        modePickerHelp: "Runs local VAD on the rolling buffer and pre-runs supported STT models before capture is finalized.",
        durationLabel: "Rolling Duration",
        durationUnitLabel: "s",
        preRunFinalizationTitle: "Pre-run Finalization",
        preRunFinalizationHelp: "When available, use the already-running preload session to finalize text instead of starting transcription from the saved WAV.",
        vadModelPickerTitle: "Buffer VAD Model",
        vadModelPickerHelp: "Silero runs locally on CPU and watches rolling-buffer audio for speech before STT preload starts.",
        autoDisableCloudModelsTitle: "Auto: Disable Cloud Models",
        autoDisableCloudModelsHelp: "When enabled, Auto keeps rolling-buffer preload local and avoids cloud streaming before capture.",
        autoDisableLowBatteryLocalModelsTitle: "Auto: Disable Local Models on Low Battery",
        autoDisableLowBatteryLocalModelsHelp: "When enabled, Auto stops local pre-run STT while running on battery below the cutoff."
    )

    public func batteryCutoffLabel(percent: Int) -> String {
        "Battery cutoff: \(percent)%"
    }
}

public struct VoiceInkRollingBufferBackupPreferences: Codable, Equatable, Sendable {
    public let preloadModeRawValue: String?
    public let autoDisablesCloudModels: Bool?
    public let autoDisablesLowBatteryLocalModels: Bool?
    public let lowBatteryThresholdPercent: Int?
    public let bufferDurationSeconds: Double?
    public let preRunFinalization: Bool?
    public let vadModelRawValue: String?
    public let perModelPreloadEnabled: [String: Bool]?

    public init(
        preloadModeRawValue: String?,
        autoDisablesCloudModels: Bool?,
        autoDisablesLowBatteryLocalModels: Bool?,
        lowBatteryThresholdPercent: Int?,
        bufferDurationSeconds: Double?,
        preRunFinalization: Bool?,
        vadModelRawValue: String?,
        perModelPreloadEnabled: [String: Bool]?
    ) {
        self.preloadModeRawValue = preloadModeRawValue
        self.autoDisablesCloudModels = autoDisablesCloudModels
        self.autoDisablesLowBatteryLocalModels = autoDisablesLowBatteryLocalModels
        self.lowBatteryThresholdPercent = lowBatteryThresholdPercent
        self.bufferDurationSeconds = bufferDurationSeconds
        self.preRunFinalization = preRunFinalization
        self.vadModelRawValue = vadModelRawValue
        self.perModelPreloadEnabled = perModelPreloadEnabled
    }
}

public struct VoiceInkRollingBufferBackupImportPlan: Equatable, Sendable {
    public let mode: VoiceInkRollingBufferPreloadMode?
    public let autoDisablesCloudModels: Bool?
    public let autoDisablesLowBatteryLocalModels: Bool?
    public let lowBatteryThresholdPercent: Int?
    public let bufferDurationSeconds: Double?
    public let preRunFinalization: Bool?
    public let vadModel: VoiceInkRollingBufferVADModel?
    public let perModelPreloadEnabled: [String: Bool]?

    public init(
        mode: VoiceInkRollingBufferPreloadMode?,
        autoDisablesCloudModels: Bool?,
        autoDisablesLowBatteryLocalModels: Bool?,
        lowBatteryThresholdPercent: Int?,
        bufferDurationSeconds: Double?,
        preRunFinalization: Bool?,
        vadModel: VoiceInkRollingBufferVADModel?,
        perModelPreloadEnabled: [String: Bool]?
    ) {
        self.mode = mode
        self.autoDisablesCloudModels = autoDisablesCloudModels
        self.autoDisablesLowBatteryLocalModels = autoDisablesLowBatteryLocalModels
        self.lowBatteryThresholdPercent = lowBatteryThresholdPercent
        self.bufferDurationSeconds = bufferDurationSeconds
        self.preRunFinalization = preRunFinalization
        self.vadModel = vadModel
        self.perModelPreloadEnabled = perModelPreloadEnabled
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
    public static let defaultPerModelPreloadEnabled = true
    public static let macOSSettingsPresentation = VoiceInkRollingBufferPreloadSettingsPresentation.macOS

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
        defaults.object(forKey: perModelPreloadEnabledKey(forModelName: modelName)) as? Bool ?? defaultPerModelPreloadEnabled
    }

    public static func savePerModelPreloadEnabled(
        _ enabled: Bool,
        forModelName modelName: String,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: perModelPreloadEnabledKey(forModelName: modelName))
    }

    public static func exportedPerModelPreloadEnabled(
        from defaults: UserDefaults = .standard
    ) -> [String: Bool] {
        defaults.dictionaryRepresentation().reduce(into: [:]) { result, entry in
            guard entry.key.hasPrefix(perModelEnabledKeyPrefix),
                  let enabled = entry.value as? Bool else {
                return
            }

            let modelName = String(entry.key.dropFirst(perModelEnabledKeyPrefix.count))
            guard !modelName.isEmpty else { return }
            result[modelName] = enabled
        }
    }

    public static func backupPreferences(
        from configuration: VoiceInkRollingBufferPreloadConfiguration,
        selectedVADModelRawValue: String,
        perModelPreloadEnabled: [String: Bool]
    ) -> VoiceInkRollingBufferBackupPreferences {
        VoiceInkRollingBufferBackupPreferences(
            preloadModeRawValue: configuration.mode.rawValue,
            autoDisablesCloudModels: configuration.autoDisablesCloudModels,
            autoDisablesLowBatteryLocalModels: configuration.autoDisablesLowBatteryLocalModels,
            lowBatteryThresholdPercent: configuration.lowBatteryThresholdPercent,
            bufferDurationSeconds: configuration.bufferDurationSeconds,
            preRunFinalization: configuration.preRunFinalization,
            vadModelRawValue: selectedVADModelRawValue,
            perModelPreloadEnabled: perModelPreloadEnabled.isEmpty ? nil : perModelPreloadEnabled
        )
    }

    public static func backupImportPlan(
        from preferences: VoiceInkRollingBufferBackupPreferences
    ) -> VoiceInkRollingBufferBackupImportPlan {
        VoiceInkRollingBufferBackupImportPlan(
            mode: preferences.preloadModeRawValue.flatMap(VoiceInkRollingBufferPreloadMode.init(rawValue:)),
            autoDisablesCloudModels: preferences.autoDisablesCloudModels,
            autoDisablesLowBatteryLocalModels: preferences.autoDisablesLowBatteryLocalModels,
            lowBatteryThresholdPercent: preferences.lowBatteryThresholdPercent.map { min(max($0, 1), 100) },
            bufferDurationSeconds: preferences.bufferDurationSeconds.map { min(max($0, 0.25), 30.0) },
            preRunFinalization: preferences.preRunFinalization,
            vadModel: preferences.vadModelRawValue.flatMap(VoiceInkRollingBufferVADModel.init(rawValue:)),
            perModelPreloadEnabled: preferences.perModelPreloadEnabled
        )
    }

    @discardableResult
    public static func saveImportedSettings(
        modeRawValue: String?,
        autoDisablesCloudModels: Bool?,
        autoDisablesLowBatteryLocalModels: Bool?,
        lowBatteryThresholdPercent: Int?,
        bufferDurationSeconds: Double?,
        preRunFinalization: Bool?,
        perModelPreloadEnabled: [String: Bool]?,
        to defaults: UserDefaults = .standard
    ) -> Bool {
        saveImportedSettings(
            from: backupImportPlan(
                from: VoiceInkRollingBufferBackupPreferences(
                    preloadModeRawValue: modeRawValue,
                    autoDisablesCloudModels: autoDisablesCloudModels,
                    autoDisablesLowBatteryLocalModels: autoDisablesLowBatteryLocalModels,
                    lowBatteryThresholdPercent: lowBatteryThresholdPercent,
                    bufferDurationSeconds: bufferDurationSeconds,
                    preRunFinalization: preRunFinalization,
                    vadModelRawValue: nil,
                    perModelPreloadEnabled: perModelPreloadEnabled
                )
            ),
            to: defaults
        )
    }

    @discardableResult
    public static func saveImportedSettings(
        from importPlan: VoiceInkRollingBufferBackupImportPlan,
        to defaults: UserDefaults = .standard
    ) -> Bool {
        var didSave = false

        if let mode = importPlan.mode {
            defaults.set(mode.rawValue, forKey: modeKey)
            didSave = true
        }
        if let autoDisablesCloudModels = importPlan.autoDisablesCloudModels {
            defaults.set(autoDisablesCloudModels, forKey: autoDisableCloudModelsKey)
            didSave = true
        }
        if let autoDisablesLowBatteryLocalModels = importPlan.autoDisablesLowBatteryLocalModels {
            defaults.set(autoDisablesLowBatteryLocalModels, forKey: autoDisableLowBatteryLocalModelsKey)
            didSave = true
        }
        if let lowBatteryThresholdPercent = importPlan.lowBatteryThresholdPercent {
            defaults.set(lowBatteryThresholdPercent, forKey: lowBatteryThresholdPercentKey)
            didSave = true
        }
        if let bufferDurationSeconds = importPlan.bufferDurationSeconds {
            defaults.set(bufferDurationSeconds, forKey: bufferDurationSecondsKey)
            didSave = true
        }
        if let preRunFinalization = importPlan.preRunFinalization {
            defaults.set(preRunFinalization, forKey: preRunFinalizationKey)
            didSave = true
        }
        if let perModelPreloadEnabled = importPlan.perModelPreloadEnabled {
            for (modelName, enabled) in perModelPreloadEnabled where !modelName.isEmpty {
                savePerModelPreloadEnabled(enabled, forModelName: modelName, in: defaults)
            }
            didSave = didSave || !perModelPreloadEnabled.isEmpty
        }

        return didSave
    }

    public static func perModelPreloadEnabledKey(forModelName modelName: String) -> String {
        "\(perModelEnabledKeyPrefix)\(modelName)"
    }
}

public enum VoiceInkRollingBufferVADModel: String, CaseIterable, Identifiable, Sendable {
    case silero

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .silero:
            return "Silero"
        }
    }
}

public enum VoiceInkRollingBufferVADSettings {
    public static let modelKey = "RollingBufferVADModel"
    public static let defaultModel: VoiceInkRollingBufferVADModel = .silero
    public static let sileroModelName = VoiceInkRollingBufferVADModel.silero.rawValue

    public static func selectedModel(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: modelKey) ?? defaultModel.rawValue
    }

    public static func usesSilero(in defaults: UserDefaults = .standard) -> Bool {
        selectedModel(in: defaults) == sileroModelName
    }

    public static func saveSelectedModel(
        _ model: VoiceInkRollingBufferVADModel,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(model.rawValue, forKey: modelKey)
    }

    @discardableResult
    public static func saveImportedModel(
        rawValue: String?,
        to defaults: UserDefaults = .standard
    ) -> Bool {
        guard let rawValue,
              let model = VoiceInkRollingBufferVADModel(rawValue: rawValue)
        else {
            return false
        }

        saveSelectedModel(model, to: defaults)
        return true
    }

    @discardableResult
    public static func saveImportedModel(
        from importPlan: VoiceInkRollingBufferBackupImportPlan,
        to defaults: UserDefaults = .standard
    ) -> Bool {
        guard let model = importPlan.vadModel else {
            return false
        }

        saveSelectedModel(model, to: defaults)
        return true
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
