import Foundation
import AppKit
import VoiceInkCore

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private var isApplyingPowerModeConfig = false

    private weak var stateProvider: (any PowerModeStateProvider)?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    /// Configure with new VoiceInkEngine-based provider.
    func configure(engine: any PowerModeStateProvider, enhancementService: AIEnhancementService) {
        self.stateProvider = engine
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let stateProvider = stateProvider, let enhancementService = enhancementService else {
            print(VoiceInkPowerModeSessionDiagnostics.notConfiguredMessage)
            return
        }

        let beginPlan = VoiceInkPowerModeSessionBeginPlan.plan(activeSession: loadSession())
        if let newSession = beginPlan.sessionToSave(
            id: UUID(),
            startTime: Date(),
            originalState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            )
        ) {
            saveSession(newSession)

            if beginPlan.shouldInstallSettingsObserver {
                NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
            }
        }

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    var hasActiveSession: Bool {
        return loadSession() != nil
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false

        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        VoiceInkPowerModeSessionPreference.clear()
    }

    @objc func updateSessionSnapshot() {
        let snapshotPlan = VoiceInkPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: isApplyingPowerModeConfig,
            activeSession: loadSession()
        )
        guard snapshotPlan.shouldCaptureCurrentState,
              let stateProvider = stateProvider,
              let enhancementService = enhancementService else { return }

        if let session = snapshotPlan.sessionToSave(
            currentState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            )
        ) {
            saveSession(session)
        }
    }

    private func currentApplicationState(
        stateProvider: any PowerModeStateProvider,
        enhancementService: AIEnhancementService
    ) -> VoiceInkPowerModeApplicationState {
        let aiService = enhancementService.getAIService()

        return VoiceInkPowerModeApplicationState(
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId,
            selectedAIProvider: aiService.selectedProvider.rawValue,
            selectedAIModel: aiService.currentModel,
            selectedLanguage: VoiceInkTranscriptionLanguagePreference.storedLanguage(),
            transcriptionModelName: stateProvider.currentTranscriptionModel?.name,
            cleanupSettings: VoiceInkTranscriptionCleanupSettings.current()
        )
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            VoiceInkPowerModeSessionApplicationPlan.applying(
                config: config,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func restoreState(_ state: VoiceInkPowerModeApplicationState) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            VoiceInkPowerModeSessionApplicationPlan.restoring(
                state: state,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func applySessionApplicationPlan(
        _ plan: VoiceInkPowerModeSessionApplicationPlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        applyPreferenceApplication(plan.preferenceApplication)
        await applyModelResourcePlan(plan.modelResourcePlan, stateProvider: stateProvider)
        applyLanguageApplicationPlan(plan.languageApplicationPlan)

        if plan.shouldPostConfigurationApplied {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func applyPreferenceApplication(_ application: VoiceInkPowerModePreferenceApplication) {
        guard let enhancementService else { return }

        enhancementService.isEnhancementEnabled = application.isEnhancementEnabled
        enhancementService.useScreenCaptureContext = application.useScreenCaptureContext

        switch application.promptSelection {
        case .leaveUnchanged:
            break
        case .set(let selectedPromptId):
            enhancementService.selectedPromptId = selectedPromptId
        }

        let aiService = enhancementService.getAIService()
        if let provider = application.selectedAIProvider {
            aiService.selectedProvider = provider
        }
        if let model = application.selectedAIModel {
            aiService.selectModel(model)
        }

        let cleanupRestore = application.cleanupRestore
        if let isTextFormattingEnabled = cleanupRestore.isTextFormattingEnabled {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(isTextFormattingEnabled)
        }
        if let punctuationCleanupMode = cleanupRestore.punctuationMode {
            PunctuationCleanupMode.setCurrent(punctuationCleanupMode)
        }
        if let lowercaseTranscription = cleanupRestore.lowercaseTranscription {
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(lowercaseTranscription)
        }
    }

    private func sessionApplicationFacts(
        stateProvider: any PowerModeStateProvider
    ) -> VoiceInkPowerModeSessionApplicationFacts {
        VoiceInkPowerModeSessionApplicationFacts(
            currentModelName: stateProvider.currentTranscriptionModel?.name,
            availableModelResourceFacts: stateProvider.allAvailableModels.map(modelResourceFacts(for:)),
            availableLanguageModelFacts: stateProvider.allAvailableModels.map(transcriptionModelFacts(for:)),
            availableLocalModelNames: Set(stateProvider.availableModels.map(\.name))
        )
    }

    private func transcriptionModelFacts(
        for model: any TranscriptionModel
    ) -> VoiceInkPowerModeTranscriptionModelFacts {
        model.powerModeTranscriptionModelFacts
    }

    private func applyLanguageApplicationPlan(_ plan: VoiceInkPowerModeLanguageApplicationPlan) {
        guard plan.shouldPostLanguageDidChange,
              let languageToSave = plan.languageToSave else { return }

        VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(languageToSave)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    private func modelResourceFacts(
        for model: any TranscriptionModel
    ) -> VoiceInkPowerModeTranscriptionModelResourceFacts {
        model.powerModeTranscriptionModelResourceFacts
    }

    private func applyModelResourcePlan(
        _ plan: VoiceInkPowerModeTranscriptionModelResourcePlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        await plan.applyRuntimeState(
            setDefaultTranscriptionModelNamed: { modelName in
                guard let selectedModel = stateProvider.allAvailableModels.first(where: { $0.name == modelName }) else {
                    return false
                }

                stateProvider.setDefaultTranscriptionModel(selectedModel)
                return true
            },
            cleanupModelResources: {
                await stateProvider.cleanupModelResources()
            },
            loadDownloadedLocalModelNamed: { modelName in
                if let localModel = VoiceInkWhisperModelFiles.downloadedLocalModelFile(
                    forModelName: modelName,
                    in: stateProvider.availableModels
                ) {
                    try await stateProvider.loadModel(localModel)
                }
            },
            handleLocalModelLoadFailure: { modelName, error in
                print(
                    VoiceInkPowerModeSessionDiagnostics.localModelLoadFailedMessage(
                        modelName: modelName,
                        errorDescription: String(describing: error)
                    )
                )
            }
        )
    }

    private func recoverSession() {
        guard let session = loadSession() else { return }
        print(VoiceInkPowerModeSessionDiagnostics.recoveringAbandonedSessionMessage)
        Task {
            await endSession()
        }
    }

    private func saveSession(_ session: VoiceInkPowerModeSession) {
        do {
            try VoiceInkPowerModeSessionPreference.saveActiveSession(session)
        } catch {
            print(
                VoiceInkPowerModeSessionDiagnostics.saveFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
        }
    }

    private func loadSession() -> VoiceInkPowerModeSession? {
        do {
            return try VoiceInkPowerModeSessionPreference.loadActiveSession()
        } catch {
            print(
                VoiceInkPowerModeSessionDiagnostics.loadFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
            return nil
        }
    }

}
