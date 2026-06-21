import Foundation
import SwiftUI
import os
import VoiceInkCore

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = TranscriptionModelRegistry.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?

    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, fluidAudioModelManager: FluidAudioModelManager) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Computed: usable models

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { availabilityFacts(for: $0).isUsable }
    }

    func isAvailableOnCurrentOS(_ model: any TranscriptionModel) -> Bool {
        availabilityFacts(for: model).isAvailableOnCurrentOS
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        if let savedModelName = VoiceInkCurrentTranscriptionModelPreference.modelName(),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            guard isAvailableOnCurrentOS(savedModel) else {
                VoiceInkCurrentTranscriptionModelPreference.clearModelName()
                currentTranscriptionModel = nil
                return
            }

            currentTranscriptionModel = savedModel
            ensureSelectedLanguageIsSupported(by: savedModel)
            notifyCurrentModelDidChange(savedModel)
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        guard isAvailableOnCurrentOS(model) else {
            NotificationManager.shared.showNotification(
                title: VoiceInkNativeAppleTranscriptionPolicy.requiresMacOS26Title(
                    modelDisplayName: model.displayName
                ),
                type: .error
            )
            return
        }

        self.currentTranscriptionModel = model
        VoiceInkCurrentTranscriptionModelPreference.saveModelName(model.name)
        ensureSelectedLanguageIsSupported(by: model)

        if model.transcriptionRuntimeResourcePlan.modelSelectionResourceAction == .clearLocalWhisperModelAndMarkLoaded {
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        notifyCurrentModelDidChange(model)
    }

    private func notifyCurrentModelDidChange(_ model: any TranscriptionModel) {
        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func ensureSelectedLanguageIsSupported(by model: any TranscriptionModel) {
        let currentLanguage = VoiceInkTranscriptionLanguagePreference.storedLanguage()
        let compatibleLanguage = model.validTranscriptionLanguageOrFallback(currentLanguage)

        if currentLanguage != compatibleLanguage {
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(compatibleLanguage)
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    private func availabilityFacts(for model: any TranscriptionModel) -> VoiceInkTranscriptionModelAvailabilityFacts {
        let isAvailableOnCurrentOS = model.provider.transcriptionModelAvailabilityRequirement == .currentOSSupport
            ? isAvailableOnCurrentOSForNativeAppleTranscription
            : true

        model.transcriptionModelAvailabilityFacts(
            hasConfiguredAPIKey: hasConfiguredAPIKey(for: model),
            isAvailableOnCurrentOS: isAvailableOnCurrentOS,
            isLocalFluidAudioModelDownloaded: fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false,
            isLocalWhisperModelDownloaded: whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
        )
    }

    private func hasConfiguredAPIKey(for model: any TranscriptionModel) -> Bool {
        guard model.provider.transcriptionModelAvailabilityRequirement == .configuredAPIKey else {
            return false
        }
        return APIKeyManager.shared.hasAPIKey(forProvider: model.provider.apiKeyProviderName)
    }

    private var isAvailableOnCurrentOSForNativeAppleTranscription: Bool {
        if #available(macOS 26, *) {
            return true
        } else {
            return false
        }
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelRegistry.models

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedWhisperModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        VoiceInkCurrentTranscriptionModelPreference.clearModelName()
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            VoiceInkCurrentTranscriptionModelPreference.clearModelName()
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = false
        }
        refreshAllAvailableModels()
    }
}
