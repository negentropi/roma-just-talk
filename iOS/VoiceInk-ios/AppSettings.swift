import Foundation
import Combine
import OSLog
import VoiceInkCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var localModelAvailabilityCancellable: AnyCancellable?
    private var fluidAudioAvailabilityCancellable: AnyCancellable?
    private var customCloudModelCancellable: AnyCancellable?

    // Modes system
    @Published var modes: [Mode] {
        didSet {
            VoiceInkModeStorage.saveModes(modes)
            repairSelectedTranscriptionLanguage()
        }
    }
    
    @Published var selectedModeId: UUID? {
        didSet {
            VoiceInkModeStorage.saveSelectedModeId(selectedModeId)
            repairSelectedTranscriptionLanguage()
        }
    }
    
    @Published private var apiKeyState: VoiceInkProviderAPIKeyState
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { VoiceInkAudioSessionTimeoutPreference.saveTimeoutSeconds(audioSessionTimeoutSeconds) }
    }

    @Published var transcriptionCleanupSettings: VoiceInkTranscriptionCleanupSettings {
        didSet { transcriptionCleanupSettings.saveChangedValues(from: oldValue) }
    }

    @Published var fillerWords: [String] {
        didSet { VoiceInkFillerWordPreference.saveWords(fillerWords) }
    }

    @Published var wordReplacements: [VoiceInkWordReplacementRule] {
        didSet { VoiceInkWordReplacementPreference.saveRules(wordReplacements) }
    }

    @Published var customVocabularyTerms: [String] {
        didSet { VoiceInkCustomVocabularyPreference.saveTerms(customVocabularyTerms) }
    }

    @Published var customPrompts: [VoiceInkCustomPrompt] {
        didSet { VoiceInkCustomPromptStorage.savePrompts(customPrompts) }
    }

    @Published var recordingPromptOverrideId: UUID?

    @Published var selectedTranscriptionLanguage: String {
        didSet {
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(selectedTranscriptionLanguage)
        }
    }

    private init() {
        let startupState = VoiceInkIOSAppSettingsStartupPolicy.state(
            verifiedProviders: VoiceInkProviderAPIKeyVerificationState.verifiedProviders(),
            loadStoredAPIKey: { VoiceInkProviderAPIKeyStorage.storedKey(for: $0) }
        )

        self.modes = startupState.modes
        self.selectedModeId = startupState.selectedModeId
        self.apiKeyState = startupState.apiKeyState
        self.audioSessionTimeoutSeconds = startupState.audioSessionTimeoutSeconds
        self.transcriptionCleanupSettings = startupState.transcriptionCleanupSettings
        self.fillerWords = startupState.fillerWords
        self.wordReplacements = startupState.wordReplacements
        self.customVocabularyTerms = startupState.customVocabularyTerms
        self.customPrompts = VoiceInkCustomPromptPolicy.startupStoreState(
            loadedPrompts: VoiceInkCustomPromptStorage.loadPrompts(),
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

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.runtimeAPIKey(for: provider) ?? ""
    }

    func refreshOpenRouterModels() async {
        guard let apiKey = VoiceInkProviderCredential.nonBlank(apiKey(for: .openRouter)) else {
            return
        }

        do {
            let models = try await VoiceInkOpenAICompatibleClient().fetchModelIDs(
                baseURL: VoiceInkProviderKind.openRouter.apiBaseURL,
                apiKey: apiKey
            )
            guard !models.isEmpty else { return }

            VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(models)
            var repairedModes = modes
            var didRepairSelection = false
            for index in repairedModes.indices
            where repairedModes[index].postProcessingProvider == .openRouter {
                let repairedModel = VoiceInkProviderKind.openRouter.selectedModel(
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
            VoiceInkIOSLogger.settings.error(
                "OpenRouter model refresh failed: \(VoiceInkErrorDescription.text(for: error), privacy: .public)"
            )
        }
    }

    func updateCustomEnhancementConfiguration(baseURL: String, model: String) {
        VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        VoiceInkDynamicAIProviderPreference.saveCustomProviderModel(
            model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        repairUnavailableProviders()
        objectWillChange.send()
    }

    func updateOllamaConfiguration(baseURL: String, model: String) {
        VoiceInkDynamicAIProviderPreference.saveOllamaBaseURL(
            baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        VoiceInkDynamicAIProviderPreference.saveOllamaSelectedModel(
            model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        repairUnavailableProviders()
        objectWillChange.send()
    }

    var providerAccess: VoiceInkProviderAccessSnapshot {
        VoiceInkProviderAccessSnapshot(
            apiKeyState: apiKeyState,
            localWhisperModelAvailable: LocalModelManager.shared.managementSnapshot.hasAvailableModel(),
            localFluidAudioModelAvailable: VoiceInkTranscriptionModelCatalog.fluidAudioModels.contains {
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
                string: VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
            ) != nil && VoiceInkProviderCredential.nonBlank(
                VoiceInkDynamicAIProviderPreference.ollamaRuntimeSelectedModel()
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

    func setAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingStoredAPIKey(key, for: provider),
            for: provider
        )
    }
    
    func applyProviderAPIKeyEditPlan(
        _ plan: VoiceInkProviderAPIKeyEditPlan,
        for provider: VoiceInkProviderKind
    ) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingEditPlan(plan, for: provider),
            for: provider
        )
    }

    private func applyProviderAPIKeyStateUpdatePlan(
        _ plan: VoiceInkProviderAPIKeyStateUpdatePlan,
        for provider: VoiceInkProviderKind
    ) {
        plan.applyRuntimeState(
            setAPIKeyState: { [self] state in
                apiKeyState = state
            },
            persistStoredKey: { [self] key in
                saveAPIKey(key, for: provider)
            },
            persistVerificationFlag: { flag in
                VoiceInkProviderAPIKeyVerificationState.setVerified(flag, for: provider)
            }
        )
    }

    func applyAPIKeyVerificationPlan(
        _ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan,
        for provider: VoiceInkProviderKind
    ) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingVerificationPlan(plan, for: provider),
            for: provider
        )
    }

    // MARK: - Modes Management

    func currentTranscriptionRunSettings() -> VoiceInkTranscriptionRunSettings {
        VoiceInkIOSAppSettingsRunSnapshot(
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
    ) -> VoiceInkTranscriptionRunSettings {
        VoiceInkIOSAppSettingsRunSnapshot(
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

    func liveTranscriptionRequest() -> VoiceInkLiveTranscriptionRequest? {
        VoiceInkLiveTranscriptionPolicy.request(
            for: currentTranscriptionRunSettings().configuration
        )
    }

    func isLiveTranscriptionEnabled(for modelName: String) -> Bool {
        VoiceInkTranscriptionStreamingPreference.isEnabled(forModelName: modelName)
    }

    func setLiveTranscriptionEnabled(_ isEnabled: Bool, for modelName: String) {
        VoiceInkTranscriptionStreamingPreference.saveIsEnabled(
            isEnabled,
            forModelName: modelName
        )
        objectWillChange.send()
    }

    func finalizeStreamingTranscript(
        _ rawText: String,
        for note: Transcription,
        runSettings: VoiceInkTranscriptionRunSettings,
        transcriptionDuration: TimeInterval?
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        do {
            let result = try await runSettings.processTranscribedText(
                rawText,
                transcriptionDuration: transcriptionDuration,
                processor: VoiceInkTranscriptionRunProcessor(),
                apiKeyProvider: { [self] provider in
                    await apiKey(for: provider)
                }
            )
            note.applyCompletedRunResult(result)
            return .succeeded(result.finalText)
        } catch is CancellationError {
            return .canceled
        } catch {
            return .failed(reason: VoiceInkErrorDescription.text(for: error))
        }
    }

    func retranscribeStoredAudio(_ note: Transcription) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
            note,
            iOSAppSettingsRunSnapshotProvider: { [self] in
                await VoiceInkIOSAppSettingsRunSnapshot(
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
        runSettings: VoiceInkTranscriptionRunSettings
    ) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
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
        runSettings: VoiceInkTranscriptionRunSettings
    ) async -> VoiceInkStoredTranscriptionReEnhancementOutcome {
        await VoiceInkStoredTranscriptionReEnhancement.run(
            note,
            rawText: note.text,
            runSettings: runSettings,
            apiKeyProvider: { [self] provider in
                await apiKey(for: provider)
            }
        )
    }

    func addMode(_ mode: Mode) {
        modes = VoiceInkModeListPolicy.appending(mode, to: modes)
    }

    func addPrompt(_ prompt: VoiceInkCustomPrompt) {
        customPrompts = VoiceInkCustomPromptPolicy.addingPrompt(
            prompt,
            to: customPrompts,
            selectedPromptId: nil
        ).prompts
    }

    func updatePrompt(_ prompt: VoiceInkCustomPrompt) {
        customPrompts = VoiceInkCustomPromptPolicy.updatingPrompt(
            prompt,
            in: customPrompts,
            selectedPromptId: nil
        ).prompts
    }

    func removePrompt(_ prompt: VoiceInkCustomPrompt) {
        guard !prompt.isPredefined else { return }
        customPrompts = VoiceInkCustomPromptPolicy.deletingPrompt(
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
        customPrompts = VoiceInkCustomPromptPolicy.movingPrompts(
            customPrompts,
            from: source,
            to: destination
        )
    }

    func updateMode(_ updatedMode: Mode, replacing modeId: UUID) {
        guard let updatedModes = VoiceInkModeListPolicy.replacing(
            modeId: modeId,
            with: updatedMode,
            in: modes
        ) else {
            return
        }

        modes = updatedModes
    }

    func removeModes(at offsets: IndexSet) {
        modes = VoiceInkModeListPolicy.removing(at: offsets, from: modes)
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
            VoiceInkModeSettingsPolicy.repairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            )
        )
        let repairedLanguage = VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            selectedTranscriptionLanguage,
            languages: transcriptionLanguages
        )
        if repairedLanguage != selectedTranscriptionLanguage {
            selectedTranscriptionLanguage = repairedLanguage
        }
    }

    private func applyModeSettingsRepairPlan(_ plan: VoiceInkModeSettingsRepairPlan) {
        plan.applyRuntimeState(
            currentSelectedModeId: selectedModeId,
            currentSelectedTranscriptionLanguage: selectedTranscriptionLanguage,
            replaceModes: { modes = $0 },
            selectMode: { selectedModeId = $0 },
            selectTranscriptionLanguage: { selectedTranscriptionLanguage = $0 }
        )
    }

    func completeFirstTimeSetup() {
        VoiceInkIOSFirstTimeSetupPolicy.plan(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage
        ).applyRuntimeState(
            applyModeSettingsRepair: applyModeSettingsRepairPlan,
            saveHasCompletedOnboarding: {
                VoiceInkOnboardingPreference.saveHasCompletedOnboarding()
                VoiceInkIOSOnboardingProgressStore.reset()
            }
        )
    }

    private func saveAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        let result = VoiceInkProviderAPIKeyStorage.saveStoredKey(key, for: provider)
        if result.shouldReportFailure, let status = result.status {
            VoiceInkIOSLogger.settings.error("\(VoiceInkProviderAPIKeyStorageDiagnostics.saveFailureMessage(status: status), privacy: .public)")
        }
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        VoiceInkDefaultSettings.iOS.appSettingsResetState.applyRuntimeState(
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
                VoiceInkSharedPreferenceReset.clearCoreUserSettings()
                VoiceInkIOSOnboardingProgressStore.reset()
            },
            deleteProviderAPIKeys: { providers in
                VoiceInkProviderAPIKeyStorage.deleteStoredKeys(for: providers)
                IOSCustomCloudModelManager.shared.removeAll()
            }
        )
        customPrompts = VoiceInkCustomPromptPolicy.repairedPredefinedPrompts(in: [])
        recordingPromptOverrideId = nil
    }
}
