import Foundation

public enum VoiceInkUserDefaultsKey {
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let lowercaseTranscription = "LowercaseTranscription"
    public static let removeFillerWords = "RemoveFillerWords"
    public static let fillerWords = "FillerWords"
    public static let modes = "modes"
    public static let selectedModeId = "selectedModeId"
    public static let selectedTranscriptionLanguage = "SelectedLanguage"
    public static let currentTranscriptionModel = "CurrentTranscriptionModel"
    public static let transcriptionPrompt = "TranscriptionPrompt"
    public static let isTextFormattingEnabled = "IsTextFormattingEnabled"
    public static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    public static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    public static let skipShortEnhancement = "SkipShortEnhancement"
    public static let shortEnhancementWordThreshold = "ShortEnhancementWordThreshold"
    public static let enhancementTimeoutSeconds = "EnhancementTimeoutSeconds"
    public static let enhancementRetryOnTimeout = "EnhancementRetryOnTimeout"
    public static let audioSessionTimeoutSeconds = "audioSessionTimeoutSeconds"
    public static let isAIEnhancementEnabled = "isAIEnhancementEnabled"
    public static let useClipboardContext = "useClipboardContext"
    public static let useScreenCaptureContext = "useScreenCaptureContext"
    public static let customPrompts = "customPrompts"
    public static let selectedPromptId = "selectedPromptId"
    public static let selectedAIProvider = "selectedAIProvider"
    public static let openRouterModels = "openRouterModels"
    public static let ollamaBaseURL = "ollamaBaseURL"
    public static let ollamaSelectedModel = "ollamaSelectedModel"
    public static let customProviderBaseURL = "customProviderBaseURL"
    public static let customProviderModel = "customProviderModel"

    public static func selectedAIProviderModel(_ providerRawValue: String) -> String {
        "\(providerRawValue)SelectedModel"
    }
}

public enum VoiceInkPreferenceDefault {
    public static let audioSessionTimeoutSeconds = 90
    public static let isTextFormattingEnabled = true
    public static let lowercaseTranscription = false
    public static let removeFillerWords = true
    public static let transcriptionRetentionMinutes = 24 * 60
    public static let skipShortEnhancement = true
    public static let shortEnhancementWordThreshold = 3
    public static let enhancementTimeoutSeconds = 7
    public static let enhancementRetryOnTimeout = true
    public static let ollamaBaseURL = "http://localhost:11434"
}

public enum VoiceInkTranscriptionPromptPreference {
    public static func localWhisperPrompt(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt) ?? fallback
    }

    public static func requestPrompt(from defaults: UserDefaults = .standard) -> String? {
        requestPrompt(defaults.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt))
    }

    public static func requestPrompt(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }
}

public enum VoiceInkTranscriptionLanguagePreference {
    public static func storedLanguage(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func selectedLanguage(
        from defaults: UserDefaults = .standard,
        fallback: String = VoiceInkLanguageCatalog.autoDetectCode
    ) -> String {
        storedLanguage(from: defaults) ?? fallback
    }

    public static func saveSelectedLanguage(
        _ language: String,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(language, forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    @discardableResult
    public static func saveCompatibleLanguage(
        _ language: String?,
        languages: [String: String],
        to defaults: UserDefaults = .standard,
        prefersNativeAppleEnglish: Bool = false
    ) -> String {
        let compatibleLanguage = VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            language,
            languages: languages,
            prefersNativeAppleEnglish: prefersNativeAppleEnglish
        )
        saveSelectedLanguage(compatibleLanguage, to: defaults)
        return compatibleLanguage
    }

    public static func clearSelectedLanguage(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
    }

    public static func requestLanguage(from defaults: UserDefaults = .standard) -> String? {
        VoiceInkTranscriptionLanguageSupport.requestLanguage(selectedLanguage(from: defaults))
    }
}

public enum VoiceInkCurrentTranscriptionModelPreference {
    public static func modelName(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func saveModelName(_ modelName: String, to defaults: UserDefaults = .standard) {
        defaults.set(modelName, forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }

    public static func clearModelName(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.currentTranscriptionModel)
    }
}

public enum VoiceInkFillerWordPreference {
    public static func words(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.fillerWords) ?? VoiceInkFillerWords.defaultWords
    }

    public static func saveWords(_ words: [String], to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: VoiceInkUserDefaultsKey.fillerWords)
    }
}

public enum VoiceInkAIEnhancementRequestPreference {
    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.integer(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        return stored > 0
            ? TimeInterval(stored)
            : TimeInterval(VoiceInkPreferenceDefault.enhancementTimeoutSeconds)
    }

    public static func shouldRetryOnTimeout(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout) as? Bool
            ?? VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    }
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

public enum VoiceInkCustomPromptStorage {
    public static func savePrompts(
        _ prompts: [VoiceInkCustomPrompt],
        to defaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        if let data = try? encoder.encode(prompts) {
            defaults.set(data, forKey: VoiceInkUserDefaultsKey.customPrompts)
        }
    }

    public static func loadPrompts(
        from defaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [VoiceInkCustomPrompt] {
        guard let data = defaults.data(forKey: VoiceInkUserDefaultsKey.customPrompts),
              let prompts = try? decoder.decode([VoiceInkCustomPrompt].self, from: data) else {
            return []
        }

        return prompts
    }

    public static func saveSelectedPromptId(_ selectedPromptId: UUID?, to defaults: UserDefaults = .standard) {
        if let selectedPromptId {
            defaults.set(selectedPromptId.uuidString, forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        } else {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
        }
    }

    public static func loadSelectedPromptId(from defaults: UserDefaults = .standard) -> UUID? {
        guard let idString = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedPromptId) else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customPrompts)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedPromptId)
    }
}

public enum VoiceInkProviderAPIKeyVerificationState {
    public static func verifiedProviders(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) -> Set<VoiceInkProviderKind> {
        Set(providers.filter { isVerified($0, in: defaults) })
    }

    public static func isVerified(
        _ provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else {
            return false
        }

        return defaults.bool(forKey: key)
    }

    public static func setVerified(
        _ verified: Bool,
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.set(verified, forKey: key)
    }

    public static func clear(
        for provider: VoiceInkProviderKind,
        in defaults: UserDefaults = .standard
    ) {
        guard let key = provider.apiKeyVerificationStateKey else {
            return
        }

        defaults.removeObject(forKey: key)
    }

    public static func clearAll(
        from providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders,
        in defaults: UserDefaults = .standard
    ) {
        providers.forEach { clear(for: $0, in: defaults) }
    }
}
