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
    public static let isVADEnabled = "IsVADEnabled"
    public static let isTranscriptionCleanupEnabled = "IsTranscriptionCleanupEnabled"
    public static let transcriptionRetentionMinutes = "TranscriptionRetentionMinutes"
    public static let isAudioCleanupEnabled = "IsAudioCleanupEnabled"
    public static let audioRetentionPeriodDays = "AudioRetentionPeriod"
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
    public static let powerModeConfigurations = "powerModeConfigurationsV2"
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
    public static let isVADEnabled = true
    public static let lowercaseTranscription = false
    public static let removeFillerWords = true
    public static let transcriptionRetentionMinutes = 24 * 60
    public static let audioRetentionDays = 7
    public static let skipShortEnhancement = true
    public static let shortEnhancementWordThreshold = 3
    public static let enhancementTimeoutSeconds = 7
    public static let enhancementRetryOnTimeout = true
    public static let ollamaBaseURL = "http://localhost:11434"
}

public struct VoiceInkDefaultSettings: Equatable, Sendable {
    public let audioSessionTimeoutSeconds: Int
    public let punctuationCleanupMode: PunctuationCleanupMode
    public let isTextFormattingEnabled: Bool
    public let isVADEnabled: Bool
    public let lowercaseTranscription: Bool
    public let removeFillerWords: Bool
    public let fillerWords: [String]
    public let selectedTranscriptionLanguage: String
    public let isTranscriptionCleanupEnabled: Bool
    public let transcriptionRetentionMinutes: Int
    public let isAudioCleanupEnabled: Bool
    public let audioRetentionDays: Int
    public let skipShortEnhancement: Bool
    public let shortEnhancementWordThreshold: Int
    public let enhancementTimeoutSeconds: Int
    public let enhancementRetryOnTimeout: Bool

    public init(
        audioSessionTimeoutSeconds: Int = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        isTextFormattingEnabled: Bool = VoiceInkPreferenceDefault.isTextFormattingEnabled,
        isVADEnabled: Bool = VoiceInkPreferenceDefault.isVADEnabled,
        lowercaseTranscription: Bool = VoiceInkPreferenceDefault.lowercaseTranscription,
        removeFillerWords: Bool = VoiceInkPreferenceDefault.removeFillerWords,
        fillerWords: [String] = VoiceInkFillerWords.defaultWords,
        selectedTranscriptionLanguage: String = VoiceInkLanguageCatalog.autoDetectCode,
        isTranscriptionCleanupEnabled: Bool = false,
        transcriptionRetentionMinutes: Int = VoiceInkPreferenceDefault.transcriptionRetentionMinutes,
        isAudioCleanupEnabled: Bool = false,
        audioRetentionDays: Int = VoiceInkPreferenceDefault.audioRetentionDays,
        skipShortEnhancement: Bool = VoiceInkPreferenceDefault.skipShortEnhancement,
        shortEnhancementWordThreshold: Int = VoiceInkPreferenceDefault.shortEnhancementWordThreshold,
        enhancementTimeoutSeconds: Int = VoiceInkPreferenceDefault.enhancementTimeoutSeconds,
        enhancementRetryOnTimeout: Bool = VoiceInkPreferenceDefault.enhancementRetryOnTimeout
    ) {
        self.audioSessionTimeoutSeconds = audioSessionTimeoutSeconds
        self.punctuationCleanupMode = punctuationCleanupMode
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.isVADEnabled = isVADEnabled
        self.lowercaseTranscription = lowercaseTranscription
        self.removeFillerWords = removeFillerWords
        self.fillerWords = fillerWords
        self.selectedTranscriptionLanguage = selectedTranscriptionLanguage
        self.isTranscriptionCleanupEnabled = isTranscriptionCleanupEnabled
        self.transcriptionRetentionMinutes = transcriptionRetentionMinutes
        self.isAudioCleanupEnabled = isAudioCleanupEnabled
        self.audioRetentionDays = audioRetentionDays
        self.skipShortEnhancement = skipShortEnhancement
        self.shortEnhancementWordThreshold = shortEnhancementWordThreshold
        self.enhancementTimeoutSeconds = enhancementTimeoutSeconds
        self.enhancementRetryOnTimeout = enhancementRetryOnTimeout
    }

    public static let iOS = VoiceInkDefaultSettings()

    public func registeredUserDefaults(
        hasCompletedOnboarding: Bool = false,
        currentTranscriptionModel: String? = nil
    ) -> [String: Any] {
        var defaults: [String: Any] = [
            VoiceInkUserDefaultsKey.hasCompletedOnboarding: hasCompletedOnboarding,
            VoiceInkUserDefaultsKey.isTextFormattingEnabled: isTextFormattingEnabled,
            VoiceInkUserDefaultsKey.isVADEnabled: isVADEnabled,
            VoiceInkUserDefaultsKey.removeFillerWords: removeFillerWords,
            PunctuationCleanupMode.legacyRemovePunctuationKey: punctuationCleanupMode == .removeAll,
            VoiceInkUserDefaultsKey.lowercaseTranscription: lowercaseTranscription,
            VoiceInkUserDefaultsKey.selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled: isTranscriptionCleanupEnabled,
            VoiceInkUserDefaultsKey.transcriptionRetentionMinutes: transcriptionRetentionMinutes,
            VoiceInkUserDefaultsKey.isAudioCleanupEnabled: isAudioCleanupEnabled,
            VoiceInkUserDefaultsKey.audioRetentionPeriodDays: audioRetentionDays,
            VoiceInkUserDefaultsKey.skipShortEnhancement: skipShortEnhancement,
            VoiceInkUserDefaultsKey.shortEnhancementWordThreshold: shortEnhancementWordThreshold,
            VoiceInkUserDefaultsKey.enhancementTimeoutSeconds: enhancementTimeoutSeconds,
            VoiceInkUserDefaultsKey.enhancementRetryOnTimeout: enhancementRetryOnTimeout
        ]

        if let currentTranscriptionModel {
            defaults[VoiceInkUserDefaultsKey.currentTranscriptionModel] = currentTranscriptionModel
        }

        return defaults
    }
}

public enum VoiceInkOnboardingPreference {
    public static func hasCompletedOnboarding(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func saveHasCompletedOnboarding(
        _ completed: Bool = true,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(completed, forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
    }
}

public enum VoiceInkAudioSessionTimeoutPreference {
    public static func timeoutSeconds(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
    }

    public static func saveTimeoutSeconds(_ seconds: Int, to defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)
    }
}

public enum VoiceInkVADPreference {
    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: VoiceInkUserDefaultsKey.isVADEnabled) as? Bool
            ?? VoiceInkPreferenceDefault.isVADEnabled
    }

    public static func saveIsEnabled(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: VoiceInkUserDefaultsKey.isVADEnabled)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isVADEnabled)
    }
}

public enum VoiceInkTranscriptionPromptPreference {
    public static func storedPrompt(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func localWhisperPrompt(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        storedPrompt(from: defaults) ?? fallback
    }

    public static func localWhisperPromptForSelectedLanguage(
        from defaults: UserDefaults = .standard
    ) -> String {
        localWhisperPrompt(
            from: defaults,
            fallback: VoiceInkLocalWhisperPromptCatalog.promptForSelectedLanguage(from: defaults)
        )
    }

    public static func requestPrompt(from defaults: UserDefaults = .standard) -> String? {
        requestPrompt(storedPrompt(from: defaults))
    }

    public static func requestPrompt(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : prompt
    }

    public static func savePrompt(_ prompt: String, to defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
    }

    public static func clearPrompt(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionPrompt)
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

public enum VoiceInkAIEnhancementProviderPreference {
    public static func selectedProviderRawValue(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func saveSelectedProviderRawValue(_ rawValue: String, to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
    }

    public static func selectedProvider(
        default defaultProvider: VoiceInkAIEnhancementProviderKind = .gemini,
        from defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementProviderKind {
        guard let storedProvider = selectedProviderRawValue(from: defaults),
              let provider = VoiceInkAIEnhancementProviderKind(storedValue: storedProvider)
        else {
            return defaultProvider
        }

        if storedProvider != provider.rawValue {
            saveSelectedProviderRawValue(provider.rawValue, to: defaults)
        }

        return provider
    }

    public static func selectedModel(
        for providerRawValue: String,
        from defaults: UserDefaults = .standard
    ) -> String? {
        let savedModel = defaults.string(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
        return savedModel?.isEmpty == false ? savedModel : nil
    }

    public static func saveSelectedModel(
        _ model: String,
        for providerRawValue: String,
        to defaults: UserDefaults = .standard
    ) {
        guard !model.isEmpty else { return }
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel(providerRawValue))
    }

    public static func clear(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkAIEnhancementProviderKind] = VoiceInkAIEnhancementProviderKind.allCases
    ) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProvider)
        providers.forEach {
            defaults.removeObject(forKey: VoiceInkUserDefaultsKey.selectedAIProviderModel($0.rawValue))
        }
    }
}

public enum VoiceInkDynamicAIProviderPreference {
    public static func ollamaBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = VoiceInkPreferenceDefault.ollamaBaseURL
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL) ?? fallback
    }

    public static func saveOllamaBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
    }

    public static func ollamaSelectedModel(
        from defaults: UserDefaults = .standard,
        fallback: String
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel) ?? fallback
    }

    public static func saveOllamaSelectedModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
    }

    public static func customProviderBaseURL(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL) ?? fallback
    }

    public static func saveCustomProviderBaseURL(_ baseURL: String, to defaults: UserDefaults = .standard) {
        defaults.set(baseURL, forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
    }

    public static func customProviderModel(
        from defaults: UserDefaults = .standard,
        fallback: String = ""
    ) -> String {
        defaults.string(forKey: VoiceInkUserDefaultsKey.customProviderModel) ?? fallback
    }

    public static func saveCustomProviderModel(_ model: String, to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: VoiceInkUserDefaultsKey.customProviderModel)
    }

    public static func openRouterModels(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.openRouterModels) ?? []
    }

    public static func saveOpenRouterModels(_ models: [String], to defaults: UserDefaults = .standard) {
        defaults.set(models, forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.ollamaSelectedModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderBaseURL)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.customProviderModel)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.openRouterModels)
    }
}

public enum VoiceInkFillerWordPreference {
    public static func words(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: VoiceInkUserDefaultsKey.fillerWords) ?? VoiceInkFillerWords.defaultWords
    }

    public static func saveWords(_ words: [String], to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: VoiceInkUserDefaultsKey.fillerWords)
    }

    public static func clearWords(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.fillerWords)
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

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementTimeoutSeconds)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.enhancementRetryOnTimeout)
    }
}

public struct VoiceInkTranscriptionAutoCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionMinutes: Int

    public init(isEnabled: Bool, retentionMinutes: Int) {
        self.isEnabled = isEnabled
        self.retentionMinutes = retentionMinutes
    }

    public var effectiveRetentionMinutes: Int {
        max(retentionMinutes, 0)
    }

    public var shouldDeleteCompletedTranscriptionImmediately: Bool {
        retentionMinutes <= 0
    }

    public func cutoffDate(from referenceDate: Date = Date()) -> Date {
        referenceDate.addingTimeInterval(TimeInterval(-effectiveRetentionMinutes * 60))
    }
}

public enum VoiceInkTranscriptionAutoCleanupPreference {
    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkTranscriptionAutoCleanupConfiguration {
        VoiceInkTranscriptionAutoCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionMinutes: retentionMinutes(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
    }

    public static func retentionMinutes(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes) as? Int
            ?? VoiceInkPreferenceDefault.transcriptionRetentionMinutes
    }

    public static func saveRetentionMinutes(_ minutes: Int, to defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isTranscriptionCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.transcriptionRetentionMinutes)
    }
}

public struct VoiceInkAudioCleanupConfiguration: Equatable, Sendable {
    public let isEnabled: Bool
    public let retentionDays: Int

    public init(isEnabled: Bool, retentionDays: Int) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
    }

    public var effectiveRetentionDays: Int {
        max(retentionDays, 0)
    }

    public func cutoffDate(
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: -effectiveRetentionDays, to: referenceDate) ?? referenceDate
    }
}

public enum VoiceInkAudioCleanupPreference {
    public static func current(from defaults: UserDefaults = .standard) -> VoiceInkAudioCleanupConfiguration {
        VoiceInkAudioCleanupConfiguration(
            isEnabled: isEnabled(from: defaults),
            retentionDays: retentionDays(from: defaults)
        )
    }

    public static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func saveIsEnabled(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
    }

    public static func retentionDays(from defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays) as? Int
            ?? VoiceInkPreferenceDefault.audioRetentionDays
    }

    public static func saveRetentionDays(_ days: Int, to defaults: UserDefaults = .standard) {
        defaults.set(days, forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.isAudioCleanupEnabled)
        defaults.removeObject(forKey: VoiceInkUserDefaultsKey.audioRetentionPeriodDays)
    }
}

public enum VoiceInkSharedPreferenceReset {
    public static func clearCoreUserSettings(
        from defaults: UserDefaults = .standard,
        providers: [VoiceInkProviderKind] = VoiceInkProviderKind.userAPIKeyProviders
    ) {
        VoiceInkModeStorage.clear(from: defaults)
        VoiceInkOnboardingPreference.clear(from: defaults)
        VoiceInkProviderAPIKeyVerificationState.clearAll(from: providers, in: defaults)
        VoiceInkAudioSessionTimeoutPreference.clear(from: defaults)
        VoiceInkVADPreference.clear(from: defaults)
        VoiceInkTranscriptionPromptPreference.clearPrompt(from: defaults)
        PunctuationCleanupMode.clearCurrent(in: defaults)
        VoiceInkTranscriptionCleanupPreferenceStorage.clearTextPreferences(from: defaults)
        VoiceInkFillerWordPreference.clearWords(from: defaults)
        VoiceInkTranscriptionLanguagePreference.clearSelectedLanguage(from: defaults)
        VoiceInkCurrentTranscriptionModelPreference.clearModelName(from: defaults)
        VoiceInkAIEnhancementProviderPreference.clear(from: defaults)
        VoiceInkDynamicAIProviderPreference.clear(from: defaults)
        VoiceInkAIEnhancementRequestPreference.clear(from: defaults)
        VoiceInkTranscriptionAutoCleanupPreference.clear(from: defaults)
        VoiceInkAudioCleanupPreference.clear(from: defaults)
        VoiceInkCustomPromptStorage.clear(from: defaults)
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

        return modes.map { mode in
            var repairedMode = mode
            repairedMode.repairModelSelection()
            return repairedMode
        }
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
