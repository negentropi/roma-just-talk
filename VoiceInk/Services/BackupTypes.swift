import Foundation
import VoiceInkCore

typealias GeneralBackup = VoiceInkGeneralSettingsBackupPayload<ShortcutBackup>
typealias BackupFile = VoiceInkSettingsBackupFile<ShortcutBackup>

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
