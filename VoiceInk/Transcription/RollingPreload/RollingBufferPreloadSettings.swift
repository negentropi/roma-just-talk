import Foundation
import IOKit.ps

enum RollingBufferPreloadMode: String, CaseIterable, Identifiable {
    case on
    case off
    case auto

    var id: String { rawValue }

    var displayName: String {
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

struct RollingBufferPreloadConfiguration: Equatable {
    let mode: RollingBufferPreloadMode
    let autoDisablesCloudModels: Bool
    let autoDisablesLowBatteryLocalModels: Bool
    let lowBatteryThresholdPercent: Int
    let bufferDurationSeconds: Double
    let preRunFinalization: Bool
}

enum RollingBufferPreloadSettings {
    static let modeKey = "RollingBufferPreloadMode"
    static let autoDisableCloudModelsKey = "RollingBufferPreloadAutoDisableCloudModels"
    static let autoDisableLowBatteryLocalModelsKey = "RollingBufferPreloadAutoDisableLowBatteryLocalModels"
    static let lowBatteryThresholdPercentKey = "RollingBufferPreloadLowBatteryThresholdPercent"
    static let bufferDurationSecondsKey = "RollingBufferDurationSeconds"
    static let preRunFinalizationKey = "RollingBufferPreloadFinalization"
    static let perModelEnabledKeyPrefix = "rolling-buffer-preload-enabled-"

    static let defaultMode: RollingBufferPreloadMode = .auto
    static let defaultAutoDisablesCloudModels = false
    static let defaultAutoDisablesLowBatteryLocalModels = true
    static let defaultLowBatteryThresholdPercent = 40
    static let defaultBufferDurationSeconds = 3.0
    static let defaultPreRunFinalization = true

    static func configuration(in defaults: UserDefaults = .standard) -> RollingBufferPreloadConfiguration {
        let mode = defaults.string(forKey: modeKey)
            .flatMap(RollingBufferPreloadMode.init(rawValue:))
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

        return RollingBufferPreloadConfiguration(
            mode: mode,
            autoDisablesCloudModels: cloudGuard,
            autoDisablesLowBatteryLocalModels: lowBatteryGuard,
            lowBatteryThresholdPercent: min(max(storedThreshold, 1), 100),
            bufferDurationSeconds: min(max(duration, 0.25), 30.0),
            preRunFinalization: preRunFinalization
        )
    }

    static func perModelPreloadEnabled(for model: any TranscriptionModel, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: perModelPreloadEnabledKey(forModelName: model.name)) as? Bool ?? true
    }

    static func perModelPreloadEnabledKey(forModelName modelName: String) -> String {
        "\(perModelEnabledKeyPrefix)\(modelName)"
    }
}

enum RollingBufferVADSettings {
    static let modelKey = "RollingBufferVADModel"
    static let sileroModelName = "silero"

    static func selectedModel(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: modelKey) ?? sileroModelName
    }

    static func usesSilero(in defaults: UserDefaults = .standard) -> Bool {
        selectedModel(in: defaults) == sileroModelName
    }
}

struct RollingBufferPowerState: Equatable, Sendable {
    let isOnBattery: Bool
    let batteryLevelPercent: Int?
}

protocol RollingBufferPowerStateProviding {
    func currentPowerState() -> RollingBufferPowerState
}

struct IOKitRollingBufferPowerStateProvider: RollingBufferPowerStateProviding {
    func currentPowerState() -> RollingBufferPowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return RollingBufferPowerState(isOnBattery: false, batteryLevelPercent: nil)
        }

        var hasBattery = false
        var isOnBattery = false
        var levels: [Int] = []

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let type = description[kIOPSTypeKey as String] as? String
            let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int
            let looksLikeBattery = type == (kIOPSInternalBatteryType as String) || currentCapacity != nil
            guard looksLikeBattery else { continue }

            hasBattery = true

            if description[kIOPSPowerSourceStateKey as String] as? String == (kIOPSBatteryPowerValue as String) {
                isOnBattery = true
            }

            if let currentCapacity, let maxCapacity, maxCapacity > 0 {
                levels.append(Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded()))
            }
        }

        return RollingBufferPowerState(
            isOnBattery: hasBattery && isOnBattery,
            batteryLevelPercent: levels.min()
        )
    }
}

struct RollingBufferPreloadPolicy {
    let configuration: RollingBufferPreloadConfiguration
    let powerState: RollingBufferPowerState

    init(
        configuration: RollingBufferPreloadConfiguration,
        powerState: RollingBufferPowerState
    ) {
        self.configuration = configuration
        self.powerState = powerState
    }

    init(defaults: UserDefaults = .standard, powerState: RollingBufferPowerState) {
        self.init(
            configuration: RollingBufferPreloadSettings.configuration(in: defaults),
            powerState: powerState
        )
    }

    func allowsPreload(
        for model: any TranscriptionModel,
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
            if configuration.autoDisablesCloudModels, model.provider.isCloudTranscriptionProvider {
                return false
            }

            if configuration.autoDisablesLowBatteryLocalModels,
               model.provider.isLocalTranscriptionProvider,
               powerState.isOnBattery,
               let batteryLevel = powerState.batteryLevelPercent,
               batteryLevel < configuration.lowBatteryThresholdPercent {
                return false
            }

            return true
        }
    }
}

extension ModelProvider {
    var isCloudTranscriptionProvider: Bool {
        switch self {
        case .groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox, .speechmatics, .assemblyAI, .xai, .cartesia, .custom:
            return true
        case .whisper, .fluidAudio, .nativeApple:
            return false
        }
    }

    var isLocalTranscriptionProvider: Bool {
        !isCloudTranscriptionProvider
    }
}
