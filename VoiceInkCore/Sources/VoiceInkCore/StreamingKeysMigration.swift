import Foundation

public enum VoiceInkStreamingKeysMigration {
    public static let didMigrateKey = "streaming-keys-migrated"
    public static let legacyParakeetStreamingEnabledKey = "parakeet-streaming-enabled"
    public static let defaultPowerModeConfigurationsKey = VoiceInkUserDefaultsKey.powerModeConfigurations
    public static let powerModeSelectedTranscriptionModelNameKey = "selectedTranscriptionModelName"

    public static let removedModelReplacements: [String: String] = [
        "stt-rt-v4": "stt-async-v4",
        "voxtral-mini-transcribe-realtime-2602": "voxtral-mini-latest",
    ]

    @discardableResult
    public static func run(
        in defaults: UserDefaults = .standard,
        powerModeConfigurationsKey: String = defaultPowerModeConfigurationsKey
    ) -> Bool {
        guard !defaults.bool(forKey: didMigrateKey) else { return false }

        migrateLegacyStreamingPreferenceKeys(in: defaults)
        migrateCurrentTranscriptionModel(in: defaults)
        migratePowerModeTranscriptionModels(in: defaults, powerModeConfigurationsKey: powerModeConfigurationsKey)

        defaults.set(true, forKey: didMigrateKey)
        return true
    }

    private static func migrateLegacyStreamingPreferenceKeys(in defaults: UserDefaults) {
        let legacyStreamingMappings: [(old: String, new: [String])] = [
            (legacyParakeetStreamingEnabledKey, [
                VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v2"),
                VoiceInkTranscriptionStreamingPreference.key(forModelName: "parakeet-tdt-0.6b-v3"),
            ]),
        ]

        for mapping in legacyStreamingMappings {
            guard let value = defaults.object(forKey: mapping.old) as? Bool else { continue }
            for newKey in mapping.new {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: mapping.old)
        }
    }

    private static func migrateCurrentTranscriptionModel(in defaults: UserDefaults) {
        guard let savedModel = VoiceInkCurrentTranscriptionModelPreference.modelName(from: defaults),
              let replacement = removedModelReplacements[savedModel] else {
            return
        }

        VoiceInkCurrentTranscriptionModelPreference.saveModelName(replacement, to: defaults)
    }

    private static func migratePowerModeTranscriptionModels(
        in defaults: UserDefaults,
        powerModeConfigurationsKey: String
    ) {
        guard let data = defaults.data(forKey: powerModeConfigurationsKey),
              var configs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return
        }

        var changed = false
        for index in configs.indices {
            guard let savedModel = configs[index][powerModeSelectedTranscriptionModelNameKey] as? String,
                  let replacement = removedModelReplacements[savedModel] else {
                continue
            }
            configs[index][powerModeSelectedTranscriptionModelNameKey] = replacement
            changed = true
        }

        if changed, let newData = try? JSONSerialization.data(withJSONObject: configs) {
            defaults.set(newData, forKey: powerModeConfigurationsKey)
        }
    }
}
