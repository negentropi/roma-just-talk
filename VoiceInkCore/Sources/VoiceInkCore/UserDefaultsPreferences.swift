import Foundation

public enum VoiceInkUserDefaultsKey {
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let lowercaseTranscription = "LowercaseTranscription"
    public static let removeFillerWords = "RemoveFillerWords"
    public static let fillerWords = "FillerWords"
    public static let modes = "modes"
    public static let selectedModeId = "selectedModeId"
    public static let audioSessionTimeoutSeconds = "audioSessionTimeoutSeconds"
}

public enum VoiceInkPreferenceDefault {
    public static let audioSessionTimeoutSeconds = 90
}

public enum VoiceInkModeStorage {
    public static func saveModes(
        _ modes: [Mode],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(modes) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.modes)
        }
    }

    public static func loadModes(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [Mode] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.modes),
              let modes = try? decoder.decode([Mode].self, from: data) else {
            return []
        }

        return modes
    }

    public static func saveSelectedModeId(_ selectedModeId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedModeId {
            defaults.set(selectedModeId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedModeId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
        }
    }

    public static func loadSelectedModeId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedModeId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.modes)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedModeId)
    }
}
