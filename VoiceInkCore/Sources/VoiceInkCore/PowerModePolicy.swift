import Foundation

public struct PowerModeConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]?
    public var urlConfigs: [VoiceInkPowerModeURLConfig]?
    public var isAIEnhancementEnabled: Bool
    public var selectedPrompt: String?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var useScreenCapture: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isEnabled: Bool
    public var isDefault: Bool

    public var selectedPromptUUID: UUID? {
        selectedPrompt.flatMap(UUID.init)
    }

    public var selectedAIProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }

    public func selectedPromptTitle(in prompts: [VoiceInkCustomPrompt]) -> String? {
        guard let selectedPromptUUID else { return nil }
        return prompts.first { $0.id == selectedPromptUUID }?.title
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, appConfigs, urlConfigs, isAIEnhancementEnabled, selectedPrompt, selectedLanguage, isTextFormattingEnabled, punctuationCleanupMode, removePunctuation, lowercaseTranscription, useScreenCapture, selectedAIProvider, selectedAIModel, isAutoSendEnabled, autoSendKey, isEnabled, isDefault
        case selectedWhisperModel
        case selectedTranscriptionModelName
    }

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig]? = nil,
        urlConfigs: [VoiceInkPowerModeURLConfig]? = nil,
        isAIEnhancementEnabled: Bool,
        selectedPrompt: String? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isEnabled: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPrompt = selectedPrompt
        self.useScreenCapture = useScreenCapture
        self.autoSendKey = autoSendKey
        self.selectedAIProvider = selectedAIProvider ?? VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
        self.selectedAIModel = selectedAIModel
        self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? VoiceInkCurrentTranscriptionModelPreference.modelName()
        self.selectedLanguage = selectedLanguage ?? VoiceInkTranscriptionLanguagePreference.selectedMacOSLanguage()
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        appConfigs = try container.decodeIfPresent([VoiceInkPowerModeAppConfig].self, forKey: .appConfigs)
        urlConfigs = try container.decodeIfPresent([VoiceInkPowerModeURLConfig].self, forKey: .urlConfigs)
        isAIEnhancementEnabled = try container.decode(Bool.self, forKey: .isAIEnhancementEnabled)
        selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled) ?? false
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            let removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation) ?? false
            punctuationCleanupMode = removePunctuation ? .removeAll : .keep
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription) ?? false
        useScreenCapture = try container.decode(Bool.self, forKey: .useScreenCapture)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .autoSendKey),
           let newKey = VoiceInkAutoSendKey(rawValue: rawValue) {
            autoSendKey = newKey
        } else if let oldBool = try container.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled), oldBool {
            autoSendKey = .enter
        } else {
            autoSendKey = .none
        }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        if let newModelName = try container.decodeIfPresent(String.self, forKey: .selectedTranscriptionModelName) {
            selectedTranscriptionModelName = newModelName
        } else if let oldModelName = try container.decodeIfPresent(String.self, forKey: .selectedWhisperModel) {
            selectedTranscriptionModelName = oldModelName
        } else {
            selectedTranscriptionModelName = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encodeIfPresent(appConfigs, forKey: .appConfigs)
        try container.encodeIfPresent(urlConfigs, forKey: .urlConfigs)
        try container.encode(isAIEnhancementEnabled, forKey: .isAIEnhancementEnabled)
        try container.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encode(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encode(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encode(punctuationCleanupMode == .removeAll, forKey: .removePunctuation)
        try container.encode(lowercaseTranscription, forKey: .lowercaseTranscription)
        try container.encode(useScreenCapture, forKey: .useScreenCapture)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encode(autoSendKey, forKey: .autoSendKey)
        try container.encodeIfPresent(selectedTranscriptionModelName, forKey: .selectedTranscriptionModelName)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isDefault, forKey: .isDefault)
    }

    public static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool {
        lhs.id == rhs.id
    }
}

public struct VoiceInkPowerModeTranscriptionMetadata: Equatable, Sendable {
    public static let inactive = VoiceInkPowerModeTranscriptionMetadata(name: nil, emoji: nil)

    public let name: String?
    public let emoji: String?

    public init(name: String?, emoji: String?) {
        self.name = name
        self.emoji = emoji
    }

    public static func active(from config: PowerModeConfig?) -> Self {
        guard let config,
              config.isEnabled else {
            return .inactive
        }

        return VoiceInkPowerModeTranscriptionMetadata(
            name: config.name,
            emoji: config.emoji
        )
    }
}

public struct VoiceInkPowerModeConfigurationDraft: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]
    public var urlConfigs: [VoiceInkPowerModeURLConfig]
    public var isAIEnhancementEnabled: Bool
    public var selectedPromptId: UUID?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var useScreenCapture: Bool
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isDefault: Bool

    public init(
        id: UUID,
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig] = [],
        urlConfigs: [VoiceInkPowerModeURLConfig] = [],
        isAIEnhancementEnabled: Bool,
        selectedPromptId: UUID? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPromptId = selectedPromptId
        self.selectedTranscriptionModelName = selectedTranscriptionModelName
        self.selectedLanguage = selectedLanguage
        self.useScreenCapture = useScreenCapture
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.autoSendKey = autoSendKey
        self.isDefault = isDefault
    }
}

public struct VoiceInkPowerModeConfigurationFormState: Equatable, Sendable {
    public static let addDefaultName = ""
    public static let addDefaultEmoji = "✏️"

    public var id: UUID
    public var name: String
    public var emoji: String
    public var appConfigs: [VoiceInkPowerModeAppConfig]
    public var urlConfigs: [VoiceInkPowerModeURLConfig]
    public var isAIEnhancementEnabled: Bool
    public var selectedPromptId: UUID?
    public var selectedTranscriptionModelName: String?
    public var selectedLanguage: String?
    public var useScreenCapture: Bool
    public var isTextFormattingEnabled: Bool
    public var punctuationCleanupMode: PunctuationCleanupMode
    public var lowercaseTranscription: Bool
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var autoSendKey: VoiceInkAutoSendKey
    public var isDefault: Bool
    public var isTranscriptFormattingExpanded: Bool

    public init(
        id: UUID,
        name: String,
        emoji: String,
        appConfigs: [VoiceInkPowerModeAppConfig] = [],
        urlConfigs: [VoiceInkPowerModeURLConfig] = [],
        isAIEnhancementEnabled: Bool,
        selectedPromptId: UUID? = nil,
        selectedTranscriptionModelName: String? = nil,
        selectedLanguage: String? = nil,
        useScreenCapture: Bool = false,
        isTextFormattingEnabled: Bool = false,
        punctuationCleanupMode: PunctuationCleanupMode = .keep,
        lowercaseTranscription: Bool = false,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        autoSendKey: VoiceInkAutoSendKey = .none,
        isDefault: Bool = false,
        isTranscriptFormattingExpanded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.appConfigs = appConfigs
        self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled
        self.selectedPromptId = selectedPromptId
        self.selectedTranscriptionModelName = selectedTranscriptionModelName
        self.selectedLanguage = selectedLanguage
        self.useScreenCapture = useScreenCapture
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.lowercaseTranscription = lowercaseTranscription
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.autoSendKey = autoSendKey
        self.isDefault = isDefault
        self.isTranscriptFormattingExpanded = isTranscriptFormattingExpanded
    }

    public static func adding(
        id: UUID = UUID(),
        selectedAIProvider: String? = VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
    ) -> Self {
        Self(
            id: id,
            name: addDefaultName,
            emoji: addDefaultEmoji,
            isAIEnhancementEnabled: false,
            selectedAIProvider: selectedAIProvider
        )
    }

    public static func editing(_ config: PowerModeConfig) -> Self {
        Self(
            id: config.id,
            name: config.name,
            emoji: config.emoji,
            appConfigs: config.appConfigs ?? [],
            urlConfigs: config.urlConfigs ?? [],
            isAIEnhancementEnabled: config.isAIEnhancementEnabled,
            selectedPromptId: config.selectedPromptUUID,
            selectedTranscriptionModelName: config.selectedTranscriptionModelName,
            selectedLanguage: config.selectedLanguage,
            useScreenCapture: config.useScreenCapture,
            isTextFormattingEnabled: config.isTextFormattingEnabled,
            punctuationCleanupMode: config.punctuationCleanupMode,
            lowercaseTranscription: config.lowercaseTranscription,
            selectedAIProvider: config.selectedAIProvider,
            selectedAIModel: config.selectedAIModel,
            autoSendKey: config.autoSendKey,
            isDefault: config.isDefault,
            isTranscriptFormattingExpanded: config.isTextFormattingEnabled
                || config.punctuationCleanupMode != .keep
                || config.lowercaseTranscription
        )
    }
}

public struct VoiceInkPowerModeEnhancementSelection: Equatable, Sendable {
    public var selectedPromptId: UUID?
    public var selectedAIProvider: String?
    public var selectedAIModel: String?

    public init(
        selectedPromptId: UUID?,
        selectedAIProvider: String?,
        selectedAIModel: String?
    ) {
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
    }

    public func fillingMissingProviderAndModel(
        currentProvider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        treatsEmptyModelAsMissing: Bool
    ) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider ?? currentProvider.rawValue,
            selectedAIModel: selectedAIModel.isMissing(treatsEmptyAsMissing: treatsEmptyModelAsMissing) ? currentModel : selectedAIModel
        )
    }

    public func resolvedProviderForPicker(
        currentProvider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderKind {
        selectedProviderKind ?? currentProvider
    }

    public func selectedProviderForModelOptions(
        currentProvider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider == nil ? currentProvider : selectedProviderKind
    }

    public func selectingProvider(_ provider: VoiceInkAIEnhancementProviderKind) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: provider.rawValue,
            selectedAIModel: nil
        )
    }

    public func selectingDefaultModelForSelectedProvider(
        defaultModelForProvider: (VoiceInkAIEnhancementProviderKind) -> String
    ) -> Self {
        guard let selectedProviderKind else {
            return self
        }

        return Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: defaultModelForProvider(selectedProviderKind)
        )
    }

    public func selectedModelForPicker(currentModel: String) -> String {
        guard let selectedAIModel, !selectedAIModel.isEmpty else {
            return currentModel
        }

        return selectedAIModel
    }

    public func selectingModel(_ model: String) -> Self {
        Self(
            selectedPromptId: selectedPromptId,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: model
        )
    }

    public func selectingPromptAfterEnabling(prompts: [VoiceInkCustomPrompt]) -> Self {
        Self(
            selectedPromptId: VoiceInkCustomPromptPolicy.selectedPromptIdAfterEnablingEnhancement(
                selectedPromptId,
                prompts: prompts
            ),
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel
        )
    }

    private var selectedProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }
}

public enum VoiceInkPowerModeLanguageControl: Equatable, Sendable {
    case disabledAutodetect
    case picker
    case hiddenDefault
}

public struct VoiceInkPowerModeTranscriptionModelFacts: Equatable, Sendable {
    public var name: String
    public var disablesLanguageSelection: Bool
    public var isMultilingual: Bool
    public var languageOptions: [String: String]
    public var prefersNativeAppleEnglish: Bool

    public var languageControl: VoiceInkPowerModeLanguageControl {
        if disablesLanguageSelection {
            return .disabledAutodetect
        }

        return isMultilingual ? .picker : .hiddenDefault
    }

    public init(
        name: String,
        languageSource: VoiceInkTranscriptionLanguageSource,
        isMultilingual: Bool,
        languageOptions: [String: String]
    ) {
        self.init(
            name: name,
            disablesLanguageSelection: languageSource.disablesTranscriptionLanguageSelection,
            isMultilingual: isMultilingual,
            languageOptions: languageOptions,
            prefersNativeAppleEnglish: languageSource.prefersNativeAppleEnglishFallback
        )
    }

    public init(
        name: String,
        disablesLanguageSelection: Bool,
        isMultilingual: Bool,
        languageOptions: [String: String],
        prefersNativeAppleEnglish: Bool
    ) {
        self.name = name
        self.disablesLanguageSelection = disablesLanguageSelection
        self.isMultilingual = isMultilingual
        self.languageOptions = languageOptions
        self.prefersNativeAppleEnglish = prefersNativeAppleEnglish
    }
}

public struct VoiceInkPowerModeTranscriptionSelection: Equatable, Sendable {
    public var selectedModelName: String?
    public var selectedLanguage: String?

    public init(selectedModelName: String?, selectedLanguage: String?) {
        self.selectedModelName = selectedModelName
        self.selectedLanguage = selectedLanguage
    }

    public func selectedModelNameForPicker(currentModelName: String?) -> String? {
        selectedModelName ?? currentModelName
    }

    public func selectingModelName(_ modelName: String?) -> Self {
        Self(selectedModelName: modelName, selectedLanguage: selectedLanguage)
    }

    public func selectedLanguageForPicker(storedLanguage: String) -> String? {
        selectedLanguage ?? storedLanguage
    }

    public func selectingLanguage(_ language: String?) -> Self {
        Self(selectedModelName: selectedModelName, selectedLanguage: language)
    }

    public func selectingAutodetectLanguage() -> Self {
        selectingLanguage(VoiceInkLanguageCatalog.autoDetectCode)
    }

    public func selectingDefaultLanguageIfMissing(_ defaultLanguage: String) -> Self {
        guard selectedLanguage == nil else {
            return self
        }

        return selectingLanguage(defaultLanguage)
    }

    public func selectingCompatibleLanguage(
        for model: VoiceInkPowerModeTranscriptionModelFacts,
        storedLanguage: String?
    ) -> Self {
        switch model.languageControl {
        case .disabledAutodetect:
            return selectingAutodetectLanguage()
        case .picker, .hiddenDefault:
            return selectingLanguage(
                VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                    selectedLanguage ?? storedLanguage,
                    languages: model.languageOptions,
                    prefersNativeAppleEnglish: model.prefersNativeAppleEnglish
                )
            )
        }
    }
}

public struct VoiceInkPowerModeTranscriptionModelResourceFacts: Equatable, Sendable {
    public var name: String
    public var loadsLocalWhisperModel: Bool

    public init(name: String, languageSource: VoiceInkTranscriptionLanguageSource) {
        self.init(
            name: name,
            loadsLocalWhisperModel: languageSource.loadsLocalWhisperModelResource
        )
    }

    public init(name: String, loadsLocalWhisperModel: Bool) {
        self.name = name
        self.loadsLocalWhisperModel = loadsLocalWhisperModel
    }
}

public enum VoiceInkPowerModeTranscriptionModelResourceAction: Equatable, Sendable {
    case none
    case cleanupOnly
    case cleanupAndLoadLocalModel(String)
}

public struct VoiceInkPowerModeTranscriptionModelResourcePlan: Equatable, Sendable {
    public var selectedModelName: String?
    public var action: VoiceInkPowerModeTranscriptionModelResourceAction

    public var shouldChangeModel: Bool {
        selectedModelName != nil
    }

    public init(
        selectedModelName: String?,
        action: VoiceInkPowerModeTranscriptionModelResourceAction
    ) {
        self.selectedModelName = selectedModelName
        self.action = action
    }

    public static func plan(
        selectedModelName: String?,
        currentModelName: String?,
        availableModels: [VoiceInkPowerModeTranscriptionModelResourceFacts],
        availableLocalModelNames: Set<String>
    ) -> Self {
        guard let selectedModelName,
              let selectedModel = availableModels.first(where: { $0.name == selectedModelName }),
              currentModelName != selectedModelName else {
            return Self(selectedModelName: nil, action: .none)
        }

        guard selectedModel.loadsLocalWhisperModel else {
            return Self(selectedModelName: selectedModelName, action: .cleanupOnly)
        }

        guard availableLocalModelNames.contains(selectedModelName) else {
            return Self(selectedModelName: selectedModelName, action: .cleanupOnly)
        }

        return Self(
            selectedModelName: selectedModelName,
            action: .cleanupAndLoadLocalModel(selectedModelName)
        )
    }
}

public struct VoiceInkPowerModeShortcutImport: Equatable, Sendable {
    public var backupKey: String
    public var id: UUID

    public init(backupKey: String, id: UUID) {
        self.backupKey = backupKey
        self.id = id
    }
}

public struct VoiceInkPowerModeShortcutExportRequest: Equatable, Sendable {
    public var backupKey: String
    public var id: UUID

    public init(backupKey: String, id: UUID) {
        self.backupKey = backupKey
        self.id = id
    }
}

public struct VoiceInkPowerModeBackupImportPlan: Equatable, Sendable {
    public var existingConfigurationIdsToClear: [UUID]
    public var importedConfigurations: [PowerModeConfig]
    public var shortcutImports: [VoiceInkPowerModeShortcutImport]
    public var hasCustomEmojiBackupRecord: Bool
    public var customEmojisToImport: [String]

    public var importedConfigurationCount: Int {
        importedConfigurations.count
    }

    public init(
        existingConfigurationIdsToClear: [UUID],
        importedConfigurations: [PowerModeConfig],
        shortcutImports: [VoiceInkPowerModeShortcutImport],
        hasCustomEmojiBackupRecord: Bool,
        customEmojisToImport: [String]
    ) {
        self.existingConfigurationIdsToClear = existingConfigurationIdsToClear
        self.importedConfigurations = importedConfigurations
        self.shortcutImports = shortcutImports
        self.hasCustomEmojiBackupRecord = hasCustomEmojiBackupRecord
        self.customEmojisToImport = customEmojisToImport
    }
}

public struct VoiceInkPowerModeBackupExportPlan: Equatable, Sendable {
    public var configurationsToExport: [PowerModeConfig]
    public var shortcutRequests: [VoiceInkPowerModeShortcutExportRequest]
    public var customEmojisToExport: [String]

    public var exportedConfigurationCount: Int {
        configurationsToExport.count
    }

    public init(
        configurationsToExport: [PowerModeConfig],
        shortcutRequests: [VoiceInkPowerModeShortcutExportRequest],
        customEmojisToExport: [String]
    ) {
        self.configurationsToExport = configurationsToExport
        self.shortcutRequests = shortcutRequests
        self.customEmojisToExport = customEmojisToExport
    }
}

public struct VoiceInkPowerModeLanguageApplicationPlan: Equatable, Sendable {
    public var languageToSave: String?

    public var shouldPostLanguageDidChange: Bool {
        languageToSave != nil
    }

    public init(languageToSave: String?) {
        self.languageToSave = languageToSave
    }

    public static func plan(
        selectedLanguage: String?,
        preferredModelName: String?,
        currentModelName: String?,
        availableModels: [VoiceInkPowerModeTranscriptionModelFacts]
    ) -> Self {
        guard let selectedLanguage else {
            return Self(languageToSave: nil)
        }

        guard let model = modelForLanguageApplication(
            preferredModelName: preferredModelName,
            currentModelName: currentModelName,
            availableModels: availableModels
        ) else {
            return Self(languageToSave: selectedLanguage)
        }

        return Self(
            languageToSave: VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
                selectedLanguage,
                languages: model.languageOptions,
                prefersNativeAppleEnglish: model.prefersNativeAppleEnglish
            )
        )
    }

    private static func modelForLanguageApplication(
        preferredModelName: String?,
        currentModelName: String?,
        availableModels: [VoiceInkPowerModeTranscriptionModelFacts]
    ) -> VoiceInkPowerModeTranscriptionModelFacts? {
        if let preferredModelName,
           let preferredModel = availableModels.first(where: { $0.name == preferredModelName }) {
            return preferredModel
        }

        guard let currentModelName else { return nil }
        return availableModels.first { $0.name == currentModelName }
    }
}

public struct VoiceInkPowerModeSessionApplicationFacts: Equatable, Sendable {
    public var currentModelName: String?
    public var availableModelResourceFacts: [VoiceInkPowerModeTranscriptionModelResourceFacts]
    public var availableLanguageModelFacts: [VoiceInkPowerModeTranscriptionModelFacts]
    public var availableLocalModelNames: Set<String>

    public init(
        currentModelName: String?,
        availableModelResourceFacts: [VoiceInkPowerModeTranscriptionModelResourceFacts],
        availableLanguageModelFacts: [VoiceInkPowerModeTranscriptionModelFacts],
        availableLocalModelNames: Set<String>
    ) {
        self.currentModelName = currentModelName
        self.availableModelResourceFacts = availableModelResourceFacts
        self.availableLanguageModelFacts = availableLanguageModelFacts
        self.availableLocalModelNames = availableLocalModelNames
    }
}

public struct VoiceInkPowerModeSessionApplicationPlan: Equatable, Sendable {
    public var preferenceApplication: VoiceInkPowerModePreferenceApplication
    public var modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan
    public var languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan
    public var shouldPostConfigurationApplied: Bool

    public init(
        preferenceApplication: VoiceInkPowerModePreferenceApplication,
        modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan,
        languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan,
        shouldPostConfigurationApplied: Bool
    ) {
        self.preferenceApplication = preferenceApplication
        self.modelResourcePlan = modelResourcePlan
        self.languageApplicationPlan = languageApplicationPlan
        self.shouldPostConfigurationApplied = shouldPostConfigurationApplied
    }

    public static func applying(
        config: PowerModeConfig,
        facts: VoiceInkPowerModeSessionApplicationFacts
    ) -> Self {
        plan(
            preferenceApplication: config.powerModePreferenceApplication,
            selectedModelName: config.selectedTranscriptionModelName,
            selectedLanguage: config.selectedLanguage,
            facts: facts,
            shouldPostConfigurationApplied: true
        )
    }

    public static func restoring(
        state: VoiceInkPowerModeApplicationState,
        facts: VoiceInkPowerModeSessionApplicationFacts
    ) -> Self {
        plan(
            preferenceApplication: state.powerModePreferenceRestore,
            selectedModelName: state.transcriptionModelName,
            selectedLanguage: state.selectedLanguage,
            facts: facts,
            shouldPostConfigurationApplied: false
        )
    }

    private static func plan(
        preferenceApplication: VoiceInkPowerModePreferenceApplication,
        selectedModelName: String?,
        selectedLanguage: String?,
        facts: VoiceInkPowerModeSessionApplicationFacts,
        shouldPostConfigurationApplied: Bool
    ) -> Self {
        Self(
            preferenceApplication: preferenceApplication,
            modelResourcePlan: VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
                selectedModelName: selectedModelName,
                currentModelName: facts.currentModelName,
                availableModels: facts.availableModelResourceFacts,
                availableLocalModelNames: facts.availableLocalModelNames
            ),
            languageApplicationPlan: VoiceInkPowerModeLanguageApplicationPlan.plan(
                selectedLanguage: selectedLanguage,
                preferredModelName: selectedModelName,
                currentModelName: facts.currentModelName,
                availableModels: facts.availableLanguageModelFacts
            ),
            shouldPostConfigurationApplied: shouldPostConfigurationApplied
        )
    }
}

public struct VoiceInkPowerModeApplicationState: Codable, Equatable, Sendable {
    public var isEnhancementEnabled: Bool
    public var useScreenCaptureContext: Bool
    public var selectedPromptId: String?
    public var selectedAIProvider: String?
    public var selectedAIModel: String?
    public var selectedLanguage: String?
    public var transcriptionModelName: String?
    public var isTextFormattingEnabled: Bool?
    public var punctuationCleanupMode: PunctuationCleanupMode?
    public var removePunctuation: Bool?
    public var lowercaseTranscription: Bool?

    public var selectedPromptUUID: UUID? {
        selectedPromptId.flatMap(UUID.init)
    }

    public var selectedAIProviderKind: VoiceInkAIEnhancementProviderKind? {
        selectedAIProvider.flatMap(VoiceInkAIEnhancementProviderKind.init(storedValue:))
    }

    public var cleanupRestore: VoiceInkPowerModeCleanupRestore {
        VoiceInkPowerModeCleanupRestore(
            isTextFormattingEnabled: isTextFormattingEnabled,
            punctuationMode: punctuationCleanupMode ?? removePunctuation.map { $0 ? .removeAll : .keep },
            lowercaseTranscription: lowercaseTranscription
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isEnhancementEnabled
        case useScreenCaptureContext
        case selectedPromptId
        case selectedAIProvider
        case selectedAIModel
        case selectedLanguage
        case transcriptionModelName
        case isTextFormattingEnabled
        case punctuationCleanupMode
        case removePunctuation
        case lowercaseTranscription
    }

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        selectedPromptId: String? = nil,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        selectedLanguage: String? = nil,
        transcriptionModelName: String? = nil,
        isTextFormattingEnabled: Bool? = nil,
        punctuationCleanupMode: PunctuationCleanupMode? = nil,
        removePunctuation: Bool? = nil,
        lowercaseTranscription: Bool? = nil
    ) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.useScreenCaptureContext = useScreenCaptureContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationCleanupMode = punctuationCleanupMode
        self.removePunctuation = removePunctuation
        self.lowercaseTranscription = lowercaseTranscription
    }

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        selectedPromptId: UUID? = nil,
        selectedAIProvider: String? = nil,
        selectedAIModel: String? = nil,
        selectedLanguage: String? = nil,
        transcriptionModelName: String? = nil,
        cleanupSettings: VoiceInkTranscriptionCleanupSettings
    ) {
        self.init(
            isEnhancementEnabled: isEnhancementEnabled,
            useScreenCaptureContext: useScreenCaptureContext,
            selectedPromptId: selectedPromptId?.uuidString,
            selectedAIProvider: selectedAIProvider,
            selectedAIModel: selectedAIModel,
            selectedLanguage: selectedLanguage,
            transcriptionModelName: transcriptionModelName,
            isTextFormattingEnabled: cleanupSettings.isTextFormattingEnabled,
            punctuationCleanupMode: cleanupSettings.punctuationMode,
            removePunctuation: cleanupSettings.removesAllPunctuation,
            lowercaseTranscription: cleanupSettings.lowercaseTranscription
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnhancementEnabled = try container.decode(Bool.self, forKey: .isEnhancementEnabled)
        useScreenCaptureContext = try container.decode(Bool.self, forKey: .useScreenCaptureContext)
        selectedPromptId = try container.decodeIfPresent(String.self, forKey: .selectedPromptId)
        selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
        selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
        transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
        isTextFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTextFormattingEnabled)
        removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation)
        if let mode = try container.decodeIfPresent(PunctuationCleanupMode.self, forKey: .punctuationCleanupMode) {
            punctuationCleanupMode = mode
        } else {
            punctuationCleanupMode = removePunctuation.map { $0 ? .removeAll : .keep }
        }
        lowercaseTranscription = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscription)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnhancementEnabled, forKey: .isEnhancementEnabled)
        try container.encode(useScreenCaptureContext, forKey: .useScreenCaptureContext)
        try container.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
        try container.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try container.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try container.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try container.encodeIfPresent(transcriptionModelName, forKey: .transcriptionModelName)
        try container.encodeIfPresent(isTextFormattingEnabled, forKey: .isTextFormattingEnabled)
        try container.encodeIfPresent(punctuationCleanupMode, forKey: .punctuationCleanupMode)
        try container.encodeIfPresent(removePunctuation, forKey: .removePunctuation)
        try container.encodeIfPresent(lowercaseTranscription, forKey: .lowercaseTranscription)
    }
}

public struct VoiceInkPowerModeCleanupRestore: Equatable, Sendable {
    public let isTextFormattingEnabled: Bool?
    public let punctuationMode: PunctuationCleanupMode?
    public let lowercaseTranscription: Bool?

    public init(
        isTextFormattingEnabled: Bool?,
        punctuationMode: PunctuationCleanupMode?,
        lowercaseTranscription: Bool?
    ) {
        self.isTextFormattingEnabled = isTextFormattingEnabled
        self.punctuationMode = punctuationMode
        self.lowercaseTranscription = lowercaseTranscription
    }
}

public enum VoiceInkPowerModePromptSelectionApplication: Equatable, Sendable {
    case leaveUnchanged
    case set(UUID?)
}

public struct VoiceInkPowerModePreferenceApplication: Equatable, Sendable {
    public let isEnhancementEnabled: Bool
    public let useScreenCaptureContext: Bool
    public let promptSelection: VoiceInkPowerModePromptSelectionApplication
    public let selectedAIProvider: VoiceInkAIEnhancementProviderKind?
    public let selectedAIModel: String?
    public let cleanupRestore: VoiceInkPowerModeCleanupRestore

    public init(
        isEnhancementEnabled: Bool,
        useScreenCaptureContext: Bool,
        promptSelection: VoiceInkPowerModePromptSelectionApplication,
        selectedAIProvider: VoiceInkAIEnhancementProviderKind?,
        selectedAIModel: String?,
        cleanupRestore: VoiceInkPowerModeCleanupRestore
    ) {
        self.isEnhancementEnabled = isEnhancementEnabled
        self.useScreenCaptureContext = useScreenCaptureContext
        self.promptSelection = promptSelection
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.cleanupRestore = cleanupRestore
    }
}

public extension PowerModeConfig {
    var powerModePreferenceApplication: VoiceInkPowerModePreferenceApplication {
        let appliesEnhancementSettings = isAIEnhancementEnabled

        return VoiceInkPowerModePreferenceApplication(
            isEnhancementEnabled: isAIEnhancementEnabled,
            useScreenCaptureContext: useScreenCapture,
            promptSelection: appliesEnhancementSettings
                ? selectedPromptUUID.map { .set($0) } ?? .leaveUnchanged
                : .leaveUnchanged,
            selectedAIProvider: appliesEnhancementSettings ? selectedAIProviderKind : nil,
            selectedAIModel: appliesEnhancementSettings ? selectedAIModel : nil,
            cleanupRestore: VoiceInkPowerModeCleanupRestore(
                isTextFormattingEnabled: isTextFormattingEnabled,
                punctuationMode: punctuationCleanupMode,
                lowercaseTranscription: lowercaseTranscription
            )
        )
    }
}

public extension VoiceInkPowerModeApplicationState {
    var powerModePreferenceRestore: VoiceInkPowerModePreferenceApplication {
        VoiceInkPowerModePreferenceApplication(
            isEnhancementEnabled: isEnhancementEnabled,
            useScreenCaptureContext: useScreenCaptureContext,
            promptSelection: .set(selectedPromptUUID),
            selectedAIProvider: selectedAIProviderKind,
            selectedAIModel: selectedAIModel,
            cleanupRestore: cleanupRestore
        )
    }
}

private extension Optional where Wrapped == String {
    func isMissing(treatsEmptyAsMissing: Bool) -> Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return treatsEmptyAsMissing && value.isEmpty
        }
    }
}

public struct VoiceInkPowerModeSession: Codable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var originalState: VoiceInkPowerModeApplicationState

    public init(id: UUID, startTime: Date, originalState: VoiceInkPowerModeApplicationState) {
        self.id = id
        self.startTime = startTime
        self.originalState = originalState
    }
}

public struct VoiceInkPowerModeSessionBeginPlan: Equatable, Sendable {
    public var startsNewSession: Bool

    public var shouldInstallSettingsObserver: Bool {
        startsNewSession
    }

    public init(startsNewSession: Bool) {
        self.startsNewSession = startsNewSession
    }

    public static func plan(activeSession: VoiceInkPowerModeSession?) -> Self {
        Self(startsNewSession: activeSession == nil)
    }

    public func sessionToSave(
        id: UUID,
        startTime: Date,
        originalState: @autoclosure () -> VoiceInkPowerModeApplicationState
    ) -> VoiceInkPowerModeSession? {
        guard startsNewSession else { return nil }
        return VoiceInkPowerModeSession(
            id: id,
            startTime: startTime,
            originalState: originalState()
        )
    }
}

public struct VoiceInkPowerModeSessionSnapshotPlan: Equatable, Sendable {
    public var activeSession: VoiceInkPowerModeSession?

    public var shouldCaptureCurrentState: Bool {
        activeSession != nil
    }

    public init(activeSession: VoiceInkPowerModeSession?) {
        self.activeSession = activeSession
    }

    public static func plan(
        isApplyingPowerModeConfiguration: Bool,
        activeSession: VoiceInkPowerModeSession?
    ) -> Self {
        guard !isApplyingPowerModeConfiguration else {
            return Self(activeSession: nil)
        }

        return Self(activeSession: activeSession)
    }

    public func sessionToSave(
        currentState: VoiceInkPowerModeApplicationState
    ) -> VoiceInkPowerModeSession? {
        guard var activeSession else { return nil }
        activeSession.originalState = currentState
        return activeSession
    }
}

public enum VoiceInkPowerModeSessionDiagnostics {
    public static let notConfiguredMessage = "SessionManager not configured."
    public static let recoveringAbandonedSessionMessage = "Recovering abandoned Power Mode session."

    public static func localModelLoadFailedMessage(modelName: String, errorDescription: String) -> String {
        "Power Mode: Failed to load local model '\(modelName)': \(errorDescription)"
    }

    public static func saveFailedMessage(errorDescription: String) -> String {
        "Error saving Power Mode session: \(errorDescription)"
    }

    public static func loadFailedMessage(errorDescription: String) -> String {
        "Error loading Power Mode session: \(errorDescription)"
    }
}

public extension Array where Element == PowerModeConfig {
    var powerModePolicyRules: [VoiceInkPowerModeRule] {
        map(\.powerModePolicyRule)
    }

    var enabledPowerModeConfigurations: [PowerModeConfig] {
        filter(\.isEnabled)
    }

    var enabledPowerModeConfigurationIds: Set<UUID> {
        Set(enabledPowerModeConfigurations.map(\.id))
    }

    var hasPowerModeDefaultConfiguration: Bool {
        contains { $0.isDefault }
    }

    var hasEnabledAutomaticRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledAutomaticRules(in: powerModePolicyRules)
    }

    var hasEnabledURLRules: Bool {
        VoiceInkPowerModePolicy.hasEnabledWebsiteRules(in: powerModePolicyRules)
    }

    func powerModeConfiguration(with id: UUID) -> PowerModeConfig? {
        first { $0.id == id }
    }

    func powerModeConfiguration(forWebsiteURL url: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forWebsiteURL: url,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    func powerModeConfiguration(forAppBundleIdentifier bundleIdentifier: String) -> PowerModeConfig? {
        guard let matchingRule = VoiceInkPowerModePolicy.matchingRule(
            forAppBundleIdentifier: bundleIdentifier,
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: matchingRule.id)
    }

    var defaultPowerModeConfiguration: PowerModeConfig? {
        guard let defaultRule = VoiceInkPowerModePolicy.defaultRule(
            in: powerModePolicyRules
        ) else { return nil }

        return powerModeConfiguration(with: defaultRule.id)
    }

    func resolvedPowerModeConfiguration(
        explicitID: UUID? = nil,
        websiteURL: String? = nil,
        appBundleIdentifier: String? = nil
    ) -> PowerModeConfig? {
        if let explicitID,
           let config = powerModeConfiguration(with: explicitID) {
            return config
        }

        guard websiteURL != nil || appBundleIdentifier != nil else {
            return nil
        }

        guard hasEnabledAutomaticRules else {
            return nil
        }

        if let websiteURL,
           let config = powerModeConfiguration(forWebsiteURL: websiteURL) {
            return config
        }

        if let appBundleIdentifier,
           let config = powerModeConfiguration(forAppBundleIdentifier: appBundleIdentifier) {
            return config
        }

        return defaultPowerModeConfiguration
    }

    func containsPowerModeEmoji(_ emoji: String) -> Bool {
        contains { $0.emoji == emoji }
    }

    @discardableResult
    mutating func appendPowerModeConfigurationIfMissing(_ config: PowerModeConfig) -> Bool {
        guard powerModeConfiguration(with: config.id) == nil else {
            return false
        }

        append(config)
        return true
    }

    @discardableResult
    mutating func updatePowerModeConfiguration(_ config: PowerModeConfig) -> Bool {
        guard let index = firstIndex(where: { $0.id == config.id }) else {
            return false
        }

        self[index] = config
        return true
    }

    @discardableResult
    mutating func removePowerModeConfiguration(with id: UUID) -> Bool {
        let originalCount = count
        removeAll { $0.id == id }
        return count != originalCount
    }

    mutating func movePowerModeConfigurations(fromOffsets offsets: IndexSet, toOffset: Int) {
        let validOffsets = offsets
            .filter { indices.contains($0) }
            .sorted()
        guard !validOffsets.isEmpty else { return }

        let configurationsToMove = validOffsets.map { self[$0] }
        for index in validOffsets.reversed() {
            remove(at: index)
        }

        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let insertionIndex = Swift.max(0, Swift.min(toOffset - removedBeforeDestination, count))
        insert(contentsOf: configurationsToMove, at: insertionIndex)
    }

    mutating func setPowerModeDefaultConfiguration(id configID: UUID) {
        for index in indices {
            self[index].isDefault = false
        }

        if let index = firstIndex(where: { $0.id == configID }) {
            self[index].isDefault = true
        }
    }

    @discardableResult
    mutating func setPowerModeConfiguration(id configID: UUID, isEnabled: Bool) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].isEnabled = isEnabled
        return true
    }

    @discardableResult
    mutating func addPowerModeAppConfig(
        _ appConfig: VoiceInkPowerModeAppConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].appConfigs ?? []
        configs.append(appConfig)
        self[index].appConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeAppConfig(
        id appConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].appConfigs?.removeAll { $0.id == appConfigID }
        return true
    }

    @discardableResult
    mutating func addPowerModeURLConfig(
        _ urlConfig: VoiceInkPowerModeURLConfig,
        toConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        var configs = self[index].urlConfigs ?? []
        configs.append(urlConfig)
        self[index].urlConfigs = configs
        return true
    }

    @discardableResult
    mutating func removePowerModeURLConfig(
        id urlConfigID: UUID,
        fromConfigurationID configID: UUID
    ) -> Bool {
        guard let index = firstIndex(where: { $0.id == configID }) else {
            return false
        }

        self[index].urlConfigs?.removeAll { $0.id == urlConfigID }
        return true
    }
}

public extension PowerModeConfig {
    var powerModePolicyRule: VoiceInkPowerModeRule {
        VoiceInkPowerModeRule(
            id: id,
            name: name,
            appRules: (appConfigs ?? []).map(\.rule),
            websiteRules: (urlConfigs ?? []).map(\.rule),
            isEnabled: isEnabled,
            isDefault: isDefault
        )
    }
}

public struct VoiceInkPowerModeAppConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var appName: String

    public init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    public static func == (lhs: VoiceInkPowerModeAppConfig, rhs: VoiceInkPowerModeAppConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeAppRule {
        VoiceInkPowerModeAppRule(bundleIdentifier: bundleIdentifier, appName: appName)
    }
}

public struct VoiceInkPowerModeAppRule: Equatable, Sendable {
    public let bundleIdentifier: String
    public let appName: String

    public init(bundleIdentifier: String, appName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }
}

public extension Array where Element == VoiceInkPowerModeAppConfig {
    func containsPowerModeAppConfig(bundleIdentifier: String) -> Bool {
        contains { $0.bundleIdentifier == bundleIdentifier }
    }

    mutating func togglePowerModeAppConfig(bundleIdentifier: String, appName: String) {
        if let index = firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            remove(at: index)
        } else {
            append(VoiceInkPowerModeAppConfig(bundleIdentifier: bundleIdentifier, appName: appName))
        }
    }
}

public struct VoiceInkPowerModeURLConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var url: String

    public init(id: UUID = UUID(), url: String) {
        self.id = id
        self.url = url
    }

    public static func == (lhs: VoiceInkPowerModeURLConfig, rhs: VoiceInkPowerModeURLConfig) -> Bool {
        lhs.id == rhs.id
    }

    public var rule: VoiceInkPowerModeWebsiteRule {
        VoiceInkPowerModeWebsiteRule(url: url)
    }
}

public struct VoiceInkPowerModeWebsiteRule: Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct VoiceInkPowerModeRule: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let appRules: [VoiceInkPowerModeAppRule]
    public let websiteRules: [VoiceInkPowerModeWebsiteRule]
    public let isEnabled: Bool
    public let isDefault: Bool

    public init(
        id: UUID,
        name: String,
        appRules: [VoiceInkPowerModeAppRule] = [],
        websiteRules: [VoiceInkPowerModeWebsiteRule] = [],
        isEnabled: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.appRules = appRules
        self.websiteRules = websiteRules
        self.isEnabled = isEnabled
        self.isDefault = isDefault
    }
}

public enum VoiceInkAutoSendKey: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case enter = "enter"
    case shiftEnter = "shiftEnter"
    case commandEnter = "commandEnter"

    public static let allCases: [VoiceInkAutoSendKey] = [
        .none,
        .enter,
        .shiftEnter,
        .commandEnter
    ]

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .enter:
            return "Return (⏎)"
        case .shiftEnter:
            return "Shift + Return (⇧⏎)"
        case .commandEnter:
            return "Command + Return (⌘⏎)"
        }
    }

    public var isEnabled: Bool {
        self != .none
    }
}

public enum VoiceInkAutoSendPolicy {
    public static let defaultDelayAfterPasteNanoseconds: UInt64 = 120_000_000

    public static func delayAfterPasteNanoseconds(for key: VoiceInkAutoSendKey) -> UInt64? {
        key.isEnabled ? defaultDelayAfterPasteNanoseconds : nil
    }
}

public enum VoiceInkPowerModeSaveMode: Equatable, Sendable {
    case add
    case edit(UUID)
}

public enum VoiceInkPowerModeConfigurationMode: Hashable, Sendable {
    case add
    case edit(PowerModeConfig)

    public var isAdding: Bool {
        if case .add = self {
            return true
        }
        return false
    }

    public var title: String {
        switch self {
        case .add:
            return "Add Power Mode"
        case .edit:
            return "Edit Power Mode"
        }
    }

    public var saveMode: VoiceInkPowerModeSaveMode {
        switch self {
        case .add:
            return .add
        case .edit(let config):
            return .edit(config.id)
        }
    }

    public func formState(
        existingConfigurations: [PowerModeConfig],
        newID: UUID = UUID(),
        selectedAIProvider: String? = VoiceInkAIEnhancementProviderPreference.selectedProviderRawValue()
    ) -> VoiceInkPowerModeConfigurationFormState {
        switch self {
        case .add:
            return .adding(id: newID, selectedAIProvider: selectedAIProvider)
        case .edit(let config):
            return .editing(existingConfigurations.powerModeConfiguration(with: config.id) ?? config)
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }

    public static func == (
        lhs: VoiceInkPowerModeConfigurationMode,
        rhs: VoiceInkPowerModeConfigurationMode
    ) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

public enum VoiceInkPowerModeValidationError: Error, Equatable, Identifiable, Sendable {
    case emptyName
    case duplicateName(String)
    case duplicateAppTrigger(String, String)
    case duplicateWebsiteTrigger(String, String)

    public var id: String {
        switch self {
        case .emptyName:
            return "emptyName"
        case .duplicateName:
            return "duplicateName"
        case .duplicateAppTrigger:
            return "duplicateAppTrigger"
        case .duplicateWebsiteTrigger:
            return "duplicateWebsiteTrigger"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .emptyName:
            return "Power mode name cannot be empty."
        case .duplicateName(let name):
            return "A power mode with the name '\(name)' already exists."
        case .duplicateAppTrigger(let appName, let powerModeName):
            return "The app '\(appName)' is already configured in the '\(powerModeName)' power mode."
        case .duplicateWebsiteTrigger(let website, let powerModeName):
            return "The website '\(website)' is already configured in the '\(powerModeName)' power mode."
        }
    }
}

public enum VoiceInkPowerModePolicy {
    public static func powerModeBackupExportPlan(
        configurations: [PowerModeConfig],
        customEmojis: [String]
    ) -> VoiceInkPowerModeBackupExportPlan {
        VoiceInkPowerModeBackupExportPlan(
            configurationsToExport: configurations,
            shortcutRequests: configurations.map {
                VoiceInkPowerModeShortcutExportRequest(backupKey: $0.id.uuidString, id: $0.id)
            },
            customEmojisToExport: customEmojis
        )
    }

    public static func powerModeShortcutBackups<Backup>(
        for requests: [VoiceInkPowerModeShortcutExportRequest],
        backupForConfiguration: (UUID) -> Backup?
    ) -> [String: Backup]? {
        let backups = Dictionary(uniqueKeysWithValues: requests.compactMap { request -> (String, Backup)? in
            guard let backup = backupForConfiguration(request.id) else {
                return nil
            }

            return (request.backupKey, backup)
        })

        return backups.isEmpty ? nil : backups
    }

    public static func powerModeShortcutImports(
        backupKeys: [String],
        importedConfigurations: [PowerModeConfig]
    ) -> [VoiceInkPowerModeShortcutImport] {
        let importedConfigurationIds = Set(importedConfigurations.map(\.id))
        return backupKeys.compactMap { backupKey in
            guard let id = UUID(uuidString: backupKey),
                  importedConfigurationIds.contains(id) else {
                return nil
            }

            return VoiceInkPowerModeShortcutImport(backupKey: backupKey, id: id)
        }
    }

    public static func powerModeBackupImportPlan(
        existingConfigurations: [PowerModeConfig],
        importedConfigurations: [PowerModeConfig],
        backupShortcutKeys: [String],
        customEmojis: [String]?
    ) -> VoiceInkPowerModeBackupImportPlan {
        VoiceInkPowerModeBackupImportPlan(
            existingConfigurationIdsToClear: existingConfigurations.map(\.id),
            importedConfigurations: importedConfigurations,
            shortcutImports: powerModeShortcutImports(
                backupKeys: backupShortcutKeys,
                importedConfigurations: importedConfigurations
            ),
            hasCustomEmojiBackupRecord: customEmojis != nil,
            customEmojisToImport: customEmojis ?? []
        )
    }

    public static func normalizedWebsiteURL(_ url: String) -> String {
        url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func websiteConfigForFormInput(_ input: String) -> VoiceInkPowerModeURLConfig? {
        guard !input.isEmpty else { return nil }
        return VoiceInkPowerModeURLConfig(url: normalizedWebsiteURL(input))
    }

    public static func addingWebsiteConfig(
        forFormInput input: String,
        to existingConfigs: [VoiceInkPowerModeURLConfig]
    ) -> [VoiceInkPowerModeURLConfig]? {
        guard let websiteConfig = websiteConfigForFormInput(input) else { return nil }
        return existingConfigs + [websiteConfig]
    }

    public static func removingAppConfig(
        id: UUID,
        from existingConfigs: [VoiceInkPowerModeAppConfig]
    ) -> [VoiceInkPowerModeAppConfig] {
        existingConfigs.filter { $0.id != id }
    }

    public static func removingWebsiteConfig(
        id: UUID,
        from existingConfigs: [VoiceInkPowerModeURLConfig]
    ) -> [VoiceInkPowerModeURLConfig] {
        existingConfigs.filter { $0.id != id }
    }

    public static func canSaveConfigurationName(_ name: String) -> Bool {
        !name.isEmpty
    }

    public static func configuration(
        from draft: VoiceInkPowerModeConfigurationDraft,
        mode: VoiceInkPowerModeConfigurationMode
    ) -> PowerModeConfig {
        switch mode {
        case .add:
            return PowerModeConfig(
                id: draft.id,
                name: draft.name,
                emoji: draft.emoji,
                appConfigs: draft.appConfigs.isEmpty ? nil : draft.appConfigs,
                urlConfigs: draft.urlConfigs.isEmpty ? nil : draft.urlConfigs,
                isAIEnhancementEnabled: draft.isAIEnhancementEnabled,
                selectedPrompt: draft.selectedPromptId?.uuidString,
                selectedTranscriptionModelName: draft.selectedTranscriptionModelName,
                selectedLanguage: draft.selectedLanguage,
                useScreenCapture: draft.useScreenCapture,
                isTextFormattingEnabled: draft.isTextFormattingEnabled,
                punctuationCleanupMode: draft.punctuationCleanupMode,
                lowercaseTranscription: draft.lowercaseTranscription,
                selectedAIProvider: draft.selectedAIProvider,
                selectedAIModel: draft.selectedAIModel,
                autoSendKey: draft.autoSendKey,
                isDefault: draft.isDefault
            )
        case .edit(let config):
            var updatedConfig = config
            updatedConfig.name = draft.name
            updatedConfig.emoji = draft.emoji
            updatedConfig.isAIEnhancementEnabled = draft.isAIEnhancementEnabled
            updatedConfig.selectedPrompt = draft.selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = draft.selectedTranscriptionModelName
            updatedConfig.selectedLanguage = draft.selectedLanguage
            updatedConfig.isTextFormattingEnabled = draft.isTextFormattingEnabled
            updatedConfig.punctuationCleanupMode = draft.punctuationCleanupMode
            updatedConfig.lowercaseTranscription = draft.lowercaseTranscription
            updatedConfig.appConfigs = draft.appConfigs.isEmpty ? nil : draft.appConfigs
            updatedConfig.urlConfigs = draft.urlConfigs.isEmpty ? nil : draft.urlConfigs
            updatedConfig.useScreenCapture = draft.useScreenCapture
            updatedConfig.autoSendKey = draft.autoSendKey
            updatedConfig.selectedAIProvider = draft.selectedAIProvider
            updatedConfig.selectedAIModel = draft.selectedAIModel
            updatedConfig.isDefault = draft.isDefault
            return updatedConfig
        }
    }

    public static func hasEnabledAutomaticRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && (
                rule.isDefault ||
                !rule.appRules.isEmpty ||
                !rule.websiteRules.isEmpty
            )
        }
    }

    public static func hasEnabledWebsiteRules(in rules: [VoiceInkPowerModeRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && !rule.websiteRules.isEmpty
        }
    }

    public static func matchingRule(
        forWebsiteURL url: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        let normalizedURL = normalizedWebsiteURL(url)

        for rule in rules where rule.isEnabled {
            for websiteRule in rule.websiteRules {
                let normalizedRuleURL = normalizedWebsiteURL(websiteRule.url)
                if normalizedURL.contains(normalizedRuleURL) {
                    return rule
                }
            }
        }

        return nil
    }

    public static func matchingRule(
        forAppBundleIdentifier bundleIdentifier: String,
        in rules: [VoiceInkPowerModeRule]
    ) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.appRules.contains { appRule in
                appRule.bundleIdentifier == bundleIdentifier
            }
        }
    }

    public static func defaultRule(in rules: [VoiceInkPowerModeRule]) -> VoiceInkPowerModeRule? {
        rules.first { rule in
            rule.isEnabled && rule.isDefault
        }
    }

    public static func validateForSave(
        candidate: VoiceInkPowerModeRule,
        mode: VoiceInkPowerModeSaveMode,
        existing rules: [VoiceInkPowerModeRule]
    ) -> [VoiceInkPowerModeValidationError] {
        var errors: [VoiceInkPowerModeValidationError] = []

        if candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        let comparableRules = rules.filter { rule in
            switch mode {
            case .add:
                return true
            case .edit(let editedID):
                return rule.id != editedID
            }
        }

        if comparableRules.contains(where: { $0.name == candidate.name }) {
            errors.append(.duplicateName(candidate.name))
        }

        for appRule in candidate.appRules {
            for existingRule in comparableRules {
                if existingRule.appRules.contains(where: { $0.bundleIdentifier == appRule.bundleIdentifier }) {
                    errors.append(.duplicateAppTrigger(appRule.appName, existingRule.name))
                }
            }
        }

        for websiteRule in candidate.websiteRules {
            for existingRule in comparableRules {
                if existingRule.websiteRules.contains(where: { $0.url == websiteRule.url }) {
                    errors.append(.duplicateWebsiteTrigger(websiteRule.url, existingRule.name))
                }
            }
        }

        return errors
    }
}
