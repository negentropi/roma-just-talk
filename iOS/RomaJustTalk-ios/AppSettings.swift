import Foundation
import Combine
import OSLog
import RomaCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var localModelAvailabilityCancellable: AnyCancellable?
    private var fluidAudioAvailabilityCancellable: AnyCancellable?
    private var customCloudModelCancellable: AnyCancellable?

    // Modes system
    @Published var modes: [Mode] {
        didSet {
            RomaModeStorage.saveModes(modes)
            repairSelectedTranscriptionLanguage()
        }
    }
    
    @Published var selectedModeId: UUID? {
        didSet {
            RomaModeStorage.saveSelectedModeId(selectedModeId)
            repairSelectedTranscriptionLanguage()
        }
    }
    
    @Published private var apiKeyState: RomaProviderAPIKeyState
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { RomaAudioSessionTimeoutPreference.saveTimeoutSeconds(audioSessionTimeoutSeconds) }
    }

    @Published var transcriptionCleanupSettings: RomaTranscriptionCleanupSettings {
        didSet { transcriptionCleanupSettings.saveChangedValues(from: oldValue) }
    }

    @Published var fillerWords: [String] {
        didSet { RomaFillerWordPreference.saveWords(fillerWords) }
    }

    @Published var wordReplacements: [RomaWordReplacementRule] {
        didSet { RomaWordReplacementPreference.saveRules(wordReplacements) }
    }

    @Published var customVocabularyTerms: [String] {
        didSet { RomaCustomVocabularyPreference.saveTerms(customVocabularyTerms) }
    }

    @Published var customPrompts: [RomaCustomPrompt] {
        didSet { RomaCustomPromptStorage.savePrompts(customPrompts) }
    }

    @Published var recordingPromptOverrideId: UUID?

    @Published var selectedTranscriptionLanguage: String {
        didSet {
            RomaTranscriptionLanguagePreference.saveSelectedLanguage(selectedTranscriptionLanguage)
        }
    }

    private init() {
        let startupState = RomaIOSAppSettingsStartupPolicy.state(
            verifiedProviders: RomaProviderAPIKeyVerificationState.verifiedProviders(),
            loadStoredAPIKey: { RomaProviderAPIKeyStorage.storedKey(for: $0) }
        )

        self.modes = startupState.modes
        self.selectedModeId = startupState.selectedModeId
        self.apiKeyState = startupState.apiKeyState
        self.audioSessionTimeoutSeconds = startupState.audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = startupState.transcriptionCleanupSettings
        self.fillerWords = startupState.fillerWords
        self.wordReplacements = startupState.wordReplacements
        self.customVocabularyTerms = startupState.customVocabularyTerms
        self.customPrompts = RomaCustomPromptPolicy.startupStoreState(
            loadedPrompts: RomaCustomPromptStorage.loadPrompts(),
            selectedPromptId: nil,
            isEnhancementEnabled: false
        ).prompts
        self.recordingPromptOverrideId = nil
        self.selectedTranscriptionLanguage = startupState.selectedTranscriptionLanguage

        observeLocalModelAvailability()
        observeFluidAudioModelAvailability()
        observeCustomCloudModels()
        repairLocalWhisperModelSelections()
        repairCustomCloudModelSelections()
        repairSelectedTranscriptionLanguage()
    }

    func apiKey(for provider: RomaProviderKind) -> String {
        apiKeyState.runtimeAPIKey(for: provider) ?? ""
    }

    func refreshOpenRouterModels() async {
        guard let apiKey = RomaProviderCredential.nonBlank(apiKey(for: .openRouter)) else {
            return
        }

        do {
            let models = try await RomaOpenAICompatibleClient().fetchModelIDs(
                baseURL: RomaProviderKind.openRouter.apiBaseURL,
                apiKey: apiKey
            )
            guard !models.isEmpty else { return }

            RomaDynamicAIProviderPreference.saveOpenRouterModels(models)
            var repairedModes = modes
            var didRepairSelection = false
            for index in repairedModes.indices
            where repairedModes[index].postProcessingProvider == .openRouter {
                let repairedModel = RomaProviderKind.openRouter.selectedModel(
                    repairedModes[index].postProcessingModel,
                    for: .postProcessing
                )
                didRepairSelection = didRepairSelection
                    || repairedModel != repairedModes[index].postProcessingModel
                repairedModes[index].postProcessingModel = repairedModel
            }
            if didRepairSelection {
                modes = repairedModes
            } else {
                objectWillChange.send()
            }
        } catch {
            RomaIOSLogger.settings.error(
                "OpenRouter model refresh failed: \(RomaErrorDescription.text(for: error), privacy: .public)"
            )
        }
    }

    func updateCustomEnhancementConfiguration(baseURL: String, model: String) {
        RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        RomaDynamicAIProviderPreference.saveCustomProviderModel(
            model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        repairUnavailableProviders()
        objectWillChange.send()
    }

    func updateOllamaConfiguration(baseURL: String, model: String) {
        RomaDynamicAIProviderPreference.saveOllamaBaseURL(
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        RomaDynamicAIProviderPreference.saveOllamaSelectedModel(
            model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        repairUnavailableProviders()
        objectWillChange.send()
    }

    var providerAccess: RomaProviderAccessSnapshot {
        RomaProviderAccessSnapshot(
            apiKeyState: apiKeyState,
            localWhisperModelAvailable: LocalModelManager.shared.managementSnapshot.hasAvailableModel(),
            localFluidAudioModelAvailable: RomaTranscriptionModelCatalog.fluidAudioModels.contains {
                FluidAudioModelManager.shared.isFluidAudioModelDownloaded(named: $0.name)
            },
            nativeAppleSpeechAvailable: {
                if #available(iOS 26.0, *) {
                    return true
                }
                return false
            }(),
            customCloudModelAvailable: !IOSCustomCloudModelManager.shared.models.isEmpty,
            localEnhancementServiceAvailable: URL(
                string: RomaDynamicAIProviderPreference.ollamaBaseURL()
            ) != nil && RomaProviderCredential.nonBlank(
                RomaDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
            ) != nil
        )
    }

    private func observeLocalModelAvailability() {
        localModelAvailabilityCancellable = LocalModelManager.shared.$localModelAvailabilityRevision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.repairLocalWhisperModelSelections()
                    self?.objectWillChange.send()
                }
            }
    }

    private func observeFluidAudioModelAvailability() {
        FluidAudioModelManager.shared.onModelDeleted = { [weak self] _ in
            self?.repairUnavailableProviders()
        }
        fluidAudioAvailabilityCancellable = FluidAudioModelManager.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
    }

    private func observeCustomCloudModels() {
        customCloudModelCancellable = IOSCustomCloudModelManager.shared.$models
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.repairCustomCloudModelSelections()
                    self?.repairUnavailableProviders()
                    self?.repairSelectedTranscriptionLanguage()
                    self?.objectWillChange.send()
                }
            }
    }

    private func repairUnavailableProviders() {
        let availability = providerAccess.modeFormProviderAvailability
        var repairedModes = modes
        for index in repairedModes.indices {
            repairedModes[index].repairProviderSelection(
                providerAvailability: availability
            )
        }
        modes = repairedModes
    }

    private func repairLocalWhisperModelSelections() {
        let importedModelNames = LocalModelManager.shared.importedModelNames
        var didRepairSelection = false
        let repairedModes = modes.map { mode in
            var repairedMode = mode
            repairedMode.repairLocalWhisperModelSelection(
                additionalLocalWhisperModelNames: importedModelNames
            )
            didRepairSelection = didRepairSelection
                || repairedMode.transcriptionModel != mode.transcriptionModel
            return repairedMode
        }
        if didRepairSelection {
            modes = repairedModes
        }
    }

    private func repairCustomCloudModelSelections() {
        let availableModelNames = IOSCustomCloudModelManager.shared.modelNames
        var didRepairSelection = false
        let repairedModes = modes.map { mode in
            var repairedMode = mode
            repairedMode.repairCustomCloudModelSelection(
                availableModelNames: availableModelNames
            )
            didRepairSelection = didRepairSelection
                || repairedMode.transcriptionModel != mode.transcriptionModel
            return repairedMode
        }
        if didRepairSelection {
            modes = repairedModes
        }
    }

    func setAPIKey(_ key: String, for provider: RomaProviderKind) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingStoredAPIKey(key, for: provider),
            for: provider
        )
    }
    
    func applyProviderAPIKeyEditPlan(
        _ plan: RomaProviderAPIKeyEditPlan,
        for provider: RomaProviderKind
    ) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingEditPlan(plan, for: provider),
            for: provider
        )
    }

    private func applyProviderAPIKeyStateUpdatePlan(
        _ plan: RomaProviderAPIKeyStateUpdatePlan,
        for provider: RomaProviderKind
    ) {
        plan.applyRuntimeState(
            setAPIKeyState: { [self] state in
                apiKeyState = state
            },
            persistStoredKey: { [self] key in
                saveAPIKey(key, for: provider)
            },
            persistVerificationFlag: { flag in
                RomaProviderAPIKeyVerificationState.setVerified(flag, for: provider)
            }
        )
    }

    func applyAPIKeyVerificationPlan(
        _ plan: RomaProviderAPIKeyVerificationApplicationPlan,
        for provider: RomaProviderKind
    ) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingVerificationPlan(plan, for: provider),
            for: provider
        )
    }

    // MARK: - Modes Management

    func currentTranscriptionRunSettings() -> RomaTranscriptionRunSettings {
        RomaIOSAppSettingsRunSnapshot(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            wordReplacementRules: wordReplacements,
            customVocabulary: customVocabularyTerms,
            additionalLocalWhisperModelNames: LocalModelManager.shared.importedModelNames,
            promptLibrary: customPrompts,
            recordingPromptOverrideId: recordingPromptOverrideId
        ).transcriptionRunSettings()
    }

    func historyReprocessingRunSettings(
        promptOverrideId: UUID?
    ) -> RomaTranscriptionRunSettings {
        RomaIOSAppSettingsRunSnapshot(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            wordReplacementRules: wordReplacements,
            customVocabulary: customVocabularyTerms,
            additionalLocalWhisperModelNames: LocalModelManager.shared.importedModelNames,
            promptLibrary: customPrompts,
            recordingPromptOverrideId: promptOverrideId
        ).transcriptionRunSettings()
    }

    func liveTranscriptionRequest() -> RomaLiveTranscriptionRequest? {
        RomaLiveTranscriptionPolicy.request(
            for: currentTranscriptionRunSettings().configuration
        )
    }

    func isLiveTranscriptionEnabled(for modelName: String) -> Bool {
        RomaTranscriptionStreamingPreference.isEnabled(forModelName: modelName)
    }

    func setLiveTranscriptionEnabled(_ isEnabled: Bool, for modelName: String) {
        RomaTranscriptionStreamingPreference.saveIsEnabled(
            isEnabled,
            forModelName: modelName
        )
        objectWillChange.send()
    }

    func finalizeStreamingTranscript(
        _ rawText: String,
        for note: Transcription,
        runSettings: RomaTranscriptionRunSettings,
        transcriptionDuration: TimeInterval?
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        do {
            let result = try await runSettings.processTranscribedText(
                rawText,
                transcriptionDuration: transcriptionDuration,
                processor: RomaTranscriptionRunProcessor(),
                apiKeyProvider: { [self] provider in
                    await apiKey(for: provider)
                }
            )
            note.applyCompletedRunResult(result)
            return .succeeded(result.finalText)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(reason: RomaErrorDescription.text(for: error))
        }
    }

    func retranscribeStoredAudio(_ note: Transcription) async -> RomaStoredAudioRetranscriptionOutcome {
        await RomaStoredAudioRetranscription.retranscribeWithOutcome(
            note,
            iOSAppSettingsRunSnapshotProvider: { [self] in
                await RomaIOSAppSettingsRunSnapshot(
                    modes: modes,
                    selectedModeId: selectedModeId,
                    selectedTranscriptionLanguage: selectedTranscriptionLanguage,
                    wordReplacementRules: wordReplacements,
                    customVocabulary: customVocabularyTerms,
                    additionalLocalWhisperModelNames: LocalModelManager.shared.importedModelNames,
                    promptLibrary: customPrompts
                )
            },
            apiKeyProvider: { [self] provider in
                await apiKey(for: provider)
            },
            localWhisperServiceFactory: {
                WhisperTranscriptionService()
            },
            localFluidAudioServiceFactory: {
                IOSFluidAudioTranscriptionService()
            },
            nativeAppleServiceFactory: {
                IOSNativeAppleTranscriptionService()
            },
            customCloudServiceFactory: {
                IOSCustomCloudTranscriptionService(
                    models: IOSCustomCloudModelManager.shared.models
                )
            }
        )
    }

    func retranscribeStoredAudio(
        _ note: Transcription,
        runSettings: RomaTranscriptionRunSettings
    ) async -> RomaStoredAudioRetranscriptionOutcome {
        await RomaStoredAudioRetranscription.retranscribeWithOutcome(
            note,
            runSettings: runSettings,
            apiKeyProvider: { [self] provider in
                await apiKey(for: provider)
            },
            localWhisperServiceFactory: {
                WhisperTranscriptionService()
            },
            localFluidAudioServiceFactory: {
                IOSFluidAudioTranscriptionService()
            },
            nativeAppleServiceFactory: {
                IOSNativeAppleTranscriptionService()
            },
            customCloudServiceFactory: {
                IOSCustomCloudTranscriptionService(
                    models: IOSCustomCloudModelManager.shared.models
                )
            }
        )
    }

    func reEnhanceStoredTranscription(
        _ note: Transcription,
        runSettings: RomaTranscriptionRunSettings
    ) async -> RomaStoredTranscriptionReEnhancementOutcome {
        await RomaStoredTranscriptionReEnhancement.run(
            note,
            rawText: note.text,
            runSettings: runSettings,
            apiKeyProvider: { [self] provider in
                await apiKey(for: provider)
            }
        )
    }

    func addMode(_ mode: Mode) {
        modes = RomaModeListPolicy.appending(mode, to: modes)
    }

    func addPrompt(_ prompt: RomaCustomPrompt) {
        customPrompts = RomaCustomPromptPolicy.addingPrompt(
            prompt,
            to: customPrompts,
            selectedPromptId: nil
        ).prompts
    }

    func updatePrompt(_ prompt: RomaCustomPrompt) {
        customPrompts = RomaCustomPromptPolicy.updatingPrompt(
            prompt,
            in: customPrompts,
            selectedPromptId: nil
        ).prompts
    }

    func removePrompt(_ prompt: RomaCustomPrompt) {
        guard !prompt.isPredefined else { return }
        customPrompts = RomaCustomPromptPolicy.deletingPrompt(
            prompt,
            from: customPrompts,
            selectedPromptId: nil
        ).prompts
        for index in modes.indices where modes[index].selectedPromptId == prompt.id {
            modes[index].selectedPromptId = nil
        }
        if recordingPromptOverrideId == prompt.id {
            recordingPromptOverrideId = nil
        }
    }

    func movePrompts(from source: IndexSet, to destination: Int) {
        customPrompts = RomaCustomPromptPolicy.movingPrompts(
            customPrompts,
            from: source,
            to: destination
        )
    }

    func updateMode(_ updatedMode: Mode, replacing modeId: UUID) {
        guard let updatedModes = RomaModeListPolicy.replacing(
            modeId: modeId,
            with: updatedMode,
            in: modes
        ) else {
            return
        }

        modes = updatedModes
    }

    func removeModes(at offsets: IndexSet) {
        modes = RomaModeListPolicy.removing(at: offsets, from: modes)
    }

    func setSelectedTranscriptionLanguage(_ language: String) {
        selectedTranscriptionLanguage = language
        repairSelectedTranscriptionLanguage()
    }

    var transcriptionLanguages: [String: String] {
        guard let mode = modes.activeMode(selectedModeId: selectedModeId),
              mode.transcriptionProvider == .customCloud,
              let model = IOSCustomCloudModelManager.shared.model(named: mode.transcriptionModel) else {
            return modes.transcriptionLanguages(selectedModeId: selectedModeId)
        }
        return model.supportedLanguages
    }

    func repairSelectedTranscriptionLanguage() {
        applyModeSettingsRepairPlan(
            RomaModeSettingsPolicy.repairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            )
        )
        let repairedLanguage = RomaTranscriptionLanguageSupport.validLanguageOrFallback(
            selectedTranscriptionLanguage,
            languages: transcriptionLanguages
        )
        if repairedLanguage != selectedTranscriptionLanguage {
            selectedTranscriptionLanguage = repairedLanguage
        }
    }

    private func applyModeSettingsRepairPlan(_ plan: RomaModeSettingsRepairPlan) {
        plan.applyRuntimeState(
            currentSelectedModeId: selectedModeId,
            currentSelectedTranscriptionLanguage: selectedTranscriptionLanguage,
            replaceModes: { modes = $0 },
            selectMode: { selectedModeId = $0 },
            selectTranscriptionLanguage: { selectedTranscriptionLanguage = $0 }
        )
    }

    func completeFirstTimeSetup() {
        RomaIOSFirstTimeSetupPolicy.plan(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage
        ).applyRuntimeState(
            applyModeSettingsRepair: applyModeSettingsRepairPlan,
            saveHasCompletedOnboarding: {
                RomaOnboardingPreference.saveHasCompletedOnboarding()
                RomaIOSOnboardingProgressStore.reset()
            }
        )
    }

    private func saveAPIKey(_ key: String, for provider: RomaProviderKind) {
        let result = RomaProviderAPIKeyStorage.saveStoredKey(key, for: provider)
        if result.shouldReportFailure, let status = result.status {
            RomaIOSLogger.settings.error("\(RomaProviderAPIKeyStorageDiagnostics.saveFailureMessage(status: status), privacy: .public)")
        }
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        RomaDefaultSettings.iOS.appSettingsResetState.applyRuntimeState(
            setModes: { [self] in modes = $0 },
            setSelectedModeId: { [self] in selectedModeId = $0 },
            setAPIKeyState: { [self] in apiKeyState = $0 },
            setAudioSessionTimeoutSeconds: { [self] in audioSessionTimeoutSeconds = $0 },
            setTranscriptionCleanupSettings: { [self] in transcriptionCleanupSettings = $0 },
            setFillerWords: { [self] in fillerWords = $0 },
            setWordReplacements: { [self] in wordReplacements = $0 },
            setCustomVocabularyTerms: { [self] in customVocabularyTerms = $0 },
            setSelectedTranscriptionLanguage: { [self] in selectedTranscriptionLanguage = $0 },
            clearCoreUserSettings: {
                RomaSharedPreferenceReset.clearCoreUserSettings()
                RomaIOSOnboardingProgressStore.reset()
            },
            deleteProviderAPIKeys: { providers in
                RomaProviderAPIKeyStorage.deleteStoredKeys(for: providers)
                IOSCustomCloudModelManager.shared.removeAll()
            }
        )
        customPrompts = RomaCustomPromptPolicy.repairedPredefinedPrompts(in: [])
        recordingPromptOverrideId = nil
    }
}
