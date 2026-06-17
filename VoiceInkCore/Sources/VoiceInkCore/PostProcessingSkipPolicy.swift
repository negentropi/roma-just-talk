import Foundation

public struct VoiceInkPostProcessingSkipConfiguration: Equatable, Sendable {
    public static func current(in defaults: UserDefaults = .standard) -> VoiceInkPostProcessingSkipConfiguration {
        VoiceInkPostProcessingSkipConfiguration(
            isEnabled: defaults.object(forKey: VoiceInkUserDefaultsKey.skipShortEnhancement) as? Bool
                ?? VoiceInkPreferenceDefault.skipShortEnhancement,
            wordThreshold: defaults.object(forKey: VoiceInkUserDefaultsKey.shortEnhancementWordThreshold) as? Int
                ?? VoiceInkPreferenceDefault.shortEnhancementWordThreshold
        )
    }

    public let isEnabled: Bool
    public let wordThreshold: Int

    public init(isEnabled: Bool, wordThreshold: Int) {
        self.isEnabled = isEnabled
        self.wordThreshold = wordThreshold > 0
            ? wordThreshold
            : VoiceInkPreferenceDefault.shortEnhancementWordThreshold
    }
}

public enum VoiceInkPostProcessingSkipPolicy {
    public static func shouldSkipPostProcessing(
        transcript: String,
        configuration: VoiceInkPostProcessingSkipConfiguration,
        promptTriggerForcesPostProcessing: Bool
    ) -> Bool {
        guard configuration.isEnabled, !promptTriggerForcesPostProcessing else {
            return false
        }

        return VoiceInkWordCounter.count(in: transcript) <= configuration.wordThreshold
    }
}
