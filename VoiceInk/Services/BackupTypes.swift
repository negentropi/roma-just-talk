import Foundation
import VoiceInkCore

typealias GeneralBackup = VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>

extension VoiceInkCustomCloudModelBackup {
    init(model: CustomCloudModel) {
        self.init(
            id: model.id,
            name: model.name,
            displayName: model.displayName,
            description: model.description,
            apiEndpoint: model.apiEndpoint,
            modelName: model.modelName,
            isMultilingualModel: model.isMultilingualModel,
            supportedLanguages: model.supportedLanguages,
            apiKey: nil
        )
    }

    func makeModel() -> CustomCloudModel {
        return importPlan.applyRuntimeState(
            makeModel: { id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages in
                CustomCloudModel(
                    id: id,
                    name: name,
                    displayName: displayName,
                    description: description,
                    apiEndpoint: apiEndpoint,
                    modelName: modelName,
                    isMultilingual: isMultilingualModel,
                    supportedLanguages: supportedLanguages
                )
            },
            restoreAPIKey: { apiKey, modelId in
                APIKeyManager.shared.saveCustomModelAPIKey(apiKey, forModelId: modelId)
            }
        )
    }
}

struct BackupFile: Codable {
    let version: String
    let customPrompts: [VoiceInkCustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let powerModeShortcuts: [String: ShortcutBackup]?
    let vocabularyWords: [VoiceInkVocabularyWordBackup]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralBackup?
    let customEmojis: [String]?
    let customCloudModels: [VoiceInkCustomCloudModelBackup]?

    private enum CodingKeys: String, CodingKey {
        case version, customPrompts, powerModeConfigs, powerModeShortcuts, vocabularyWords, wordReplacements, generalSettings, customEmojis, customCloudModels
    }

    init(version: String, customPrompts: [VoiceInkCustomPrompt], powerModeConfigs: [PowerModeConfig], powerModeShortcuts: [String: ShortcutBackup]?, vocabularyWords: [VoiceInkVocabularyWordBackup]?, wordReplacements: [String: String]?, generalSettings: GeneralBackup?, customEmojis: [String]?, customCloudModels: [VoiceInkCustomCloudModelBackup]?) {
        self.version = version
        self.customPrompts = customPrompts
        self.powerModeConfigs = powerModeConfigs
        self.powerModeShortcuts = powerModeShortcuts
        self.vocabularyWords = vocabularyWords
        self.wordReplacements = wordReplacements
        self.generalSettings = generalSettings
        self.customEmojis = customEmojis
        self.customCloudModels = customCloudModels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        customPrompts = try container.decodeIfPresent([VoiceInkCustomPrompt].self, forKey: .customPrompts) ?? []
        powerModeConfigs = try container.decodeIfPresent([PowerModeConfig].self, forKey: .powerModeConfigs) ?? []
        powerModeShortcuts = try container.decodeIfPresent([String: ShortcutBackup].self, forKey: .powerModeShortcuts)
        vocabularyWords = try container.decodeIfPresent([VoiceInkVocabularyWordBackup].self, forKey: .vocabularyWords)
        wordReplacements = try container.decodeIfPresent([String: String].self, forKey: .wordReplacements)
        generalSettings = try container.decodeIfPresent(GeneralBackup.self, forKey: .generalSettings)
        customEmojis = try container.decodeIfPresent([String].self, forKey: .customEmojis)
        customCloudModels = try container.decodeIfPresent([VoiceInkCustomCloudModelBackup].self, forKey: .customCloudModels)
    }
}
