import Foundation
import RomaCore

@MainActor
class PowerModeSessionManager {
    static let shared = PowerModeSessionManager()
    private var isApplyingPowerModeConfig = false

    private weak var stateProvider: (any PowerModeStateProvider)?
    private var enhancementService: AIEnhancementService?

    private init() {
        recoverSession()
    }

    /// Configure with new RomaEngine-based provider.
    func configure(engine: any PowerModeStateProvider, enhancementService: AIEnhancementService) {
        self.stateProvider = engine
        self.enhancementService = enhancementService
    }

    func beginSession(with config: PowerModeConfig) async {
        guard let stateProvider = stateProvider, let enhancementService = enhancementService else {
            print(RomaPowerModeSessionDiagnostics.notConfiguredMessage)
            return
        }

        let beginPlan = RomaPowerModeSessionBeginPlan.plan(activeSession: loadSession())
        beginPlan.applyRuntimeState(
            id: UUID(),
            startTime: Date(),
            originalState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            ),
            saveSession: saveSession,
            installSettingsObserver: {
                NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
            }
        )

        // Always apply the new configuration
        isApplyingPowerModeConfig = true
        await applyConfiguration(config)
        isApplyingPowerModeConfig = false
    }

    func endSession() async {
        guard let session = loadSession() else { return }

        isApplyingPowerModeConfig = true
        await restoreState(session.originalState)
        isApplyingPowerModeConfig = false

        NotificationCenter.default.removeObserver(self, name: .AppSettingsDidChange, object: nil)

        RomaPowerModeSessionPreference.clear()
    }

    @objc func updateSessionSnapshot() {
        let snapshotPlan = RomaPowerModeSessionSnapshotPlan.plan(
            isApplyingPowerModeConfiguration: isApplyingPowerModeConfig,
            activeSession: loadSession()
        )
        guard let stateProvider = stateProvider,
              let enhancementService = enhancementService else { return }

        snapshotPlan.applyRuntimeState(
            currentState: currentApplicationState(
                stateProvider: stateProvider,
                enhancementService: enhancementService
            ),
            saveSession: saveSession
        )
    }

    private func currentApplicationState(
        stateProvider: any PowerModeStateProvider,
        enhancementService: AIEnhancementService
    ) -> RomaPowerModeApplicationState {
        let aiService = enhancementService.getAIService()

        return RomaPowerModeApplicationState(
            isEnhancementEnabled: enhancementService.isEnhancementEnabled,
            useScreenCaptureContext: enhancementService.useScreenCaptureContext,
            selectedPromptId: enhancementService.selectedPromptId,
            selectedAIProvider: aiService.selectedProvider.rawValue,
            selectedAIModel: aiService.currentModel,
            selectedLanguage: RomaTranscriptionLanguagePreference.storedLanguage(),
            transcriptionModelName: stateProvider.currentTranscriptionModel?.name,
            cleanupSettings: RomaTranscriptionCleanupSettings.current()
        )
    }

    private func applyConfiguration(_ config: PowerModeConfig) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            RomaPowerModeSessionApplicationPlan.applying(
                config: config,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func restoreState(_ state: RomaPowerModeApplicationState) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await applySessionApplicationPlan(
            RomaPowerModeSessionApplicationPlan.restoring(
                state: state,
                facts: sessionApplicationFacts(stateProvider: stateProvider)
            ),
            stateProvider: stateProvider
        )
    }

    private func applySessionApplicationPlan(
        _ plan: RomaPowerModeSessionApplicationPlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        await plan.applyRuntimeState(
            applyPreferenceApplication: applyPreferenceApplication,
            applyModelResourcePlan: { plan in
                await self.applyModelResourcePlan(plan, stateProvider: stateProvider)
            },
            applyLanguageApplicationPlan: applyLanguageApplicationPlan,
            postConfigurationApplied: {
                NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
            }
        )
    }

    private func applyPreferenceApplication(_ application: RomaPowerModePreferenceApplication) {
        guard let enhancementService else { return }

        let aiService = enhancementService.getAIService()
        application.applyRuntimeState(
            setEnhancementEnabled: { enhancementService.isEnhancementEnabled = $0 },
            setUseScreenCaptureContext: { enhancementService.useScreenCaptureContext = $0 },
            setSelectedPromptId: { enhancementService.selectedPromptId = $0 },
            setSelectedAIProvider: { aiService.selectedProvider = $0 },
            selectAIModel: { aiService.selectModel($0) },
            saveTextFormattingEnabled: { RomaTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled($0) },
            setPunctuationCleanupMode: { PunctuationCleanupMode.setCurrent($0) },
            saveLowercaseTranscription: { RomaTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription($0) }
        )
    }

    private func sessionApplicationFacts(
        stateProvider: any PowerModeStateProvider
    ) -> RomaPowerModeSessionApplicationFacts {
        RomaPowerModeSessionApplicationFacts(
            currentModelName: stateProvider.currentTranscriptionModel?.name,
            availableModelResourceFacts: stateProvider.allAvailableModels.map { $0.powerModeTranscriptionModelResourceFacts },
            availableLocalModelNames: Set(stateProvider.availableModels.map(\.name))
        )
    }

    private func applyLanguageApplicationPlan(_ plan: RomaPowerModeLanguageApplicationPlan) {
        plan.applyRuntimeState(
            saveSelectedLanguage: { language in
                RomaTranscriptionLanguagePreference.saveSelectedLanguage(language)
                RomaTranscriptionPromptPreference.saveLocalWhisperPromptForSelectedLanguage()
            },
            postLanguageDidChange: {
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        )
    }

    private func applyModelResourcePlan(
        _ plan: RomaPowerModeTranscriptionModelResourcePlan,
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
                if let localModel = RomaWhisperModelFiles.downloadedLocalModelFile(
                    forModelName: modelName,
                    in: stateProvider.availableModels
                ) {
                    try await stateProvider.loadModel(localModel)
                }
            },
            handleLocalModelLoadFailure: { modelName, error in
                print(
                    RomaPowerModeSessionDiagnostics.localModelLoadFailedMessage(
                        modelName: modelName,
                        errorDescription: String(describing: error)
                    )
                )
            }
        )
    }

    private func recoverSession() {
        RomaPowerModeSessionRecoveryPlan.plan(activeSession: loadSession()).applyRuntimeState(
            logRecoveringAbandonedSession: {
                print(RomaPowerModeSessionDiagnostics.recoveringAbandonedSessionMessage)
            },
            scheduleEndSession: {
                Task {
                    await self.endSession()
                }
            }
        )
    }

    private func saveSession(_ session: RomaPowerModeSession) {
        do {
            try RomaPowerModeSessionPreference.saveActiveSession(session)
        } catch {
            print(
                RomaPowerModeSessionDiagnostics.saveFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
        }
    }

    private func loadSession() -> RomaPowerModeSession? {
        do {
            return try RomaPowerModeSessionPreference.loadActiveSession()
        } catch {
            print(
                RomaPowerModeSessionDiagnostics.loadFailedMessage(
                    errorDescription: String(describing: error)
                )
            )
            return nil
        }
    }

}
