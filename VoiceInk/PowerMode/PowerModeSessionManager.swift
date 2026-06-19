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
            print("SessionManager not configured.")
            return
        }

        // Only capture baseline if NO session exists
        if loadSession() == nil {
            let newSession = VoiceInkPowerModeSession(
                id: UUID(),
                startTime: Date(),
                originalState: currentApplicationState(
                    stateProvider: stateProvider,
                    enhancementService: enhancementService
                )
            )
            saveSession(newSession)

            NotificationCenter.default.addObserver(self, selector: #selector(updateSessionSnapshot), name: .AppSettingsDidChange, object: nil)
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

        clearSession()
    }

    @objc func updateSessionSnapshot() {
        guard !isApplyingPowerModeConfig else { return }

        guard var session = loadSession(),
              let stateProvider = stateProvider,
              let enhancementService = enhancementService else { return }

        session.originalState = currentApplicationState(
            stateProvider: stateProvider,
            enhancementService: enhancementService
        )
        saveSession(session)
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

        await MainActor.run {
            applyPreferenceApplication(config.powerModePreferenceApplication)
        }

        await applyModelResourcePlan(
            modelResourcePlan(
                for: config.selectedTranscriptionModelName,
                stateProvider: stateProvider
            ),
            stateProvider: stateProvider
        )

        if let language = config.selectedLanguage {
            applyCompatibleLanguage(language, preferredModelName: config.selectedTranscriptionModelName)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func restoreState(_ state: VoiceInkPowerModeApplicationState) async {
        guard enhancementService != nil,
              let stateProvider = stateProvider else { return }

        await MainActor.run {
            applyPreferenceApplication(state.powerModePreferenceRestore)
        }

        await applyModelResourcePlan(
            modelResourcePlan(
                for: state.transcriptionModelName,
                stateProvider: stateProvider
            ),
            stateProvider: stateProvider
        )

        if let language = state.selectedLanguage {
            applyCompatibleLanguage(language, preferredModelName: state.transcriptionModelName)
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

    private func applyCompatibleLanguage(_ language: String, preferredModelName: String?) {
        guard let model = model(named: preferredModelName) ?? stateProvider?.currentTranscriptionModel else {
            VoiceInkTranscriptionLanguagePreference.saveSelectedLanguage(language)
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
            return
        }

        VoiceInkTranscriptionLanguagePreference.saveCompatibleLanguage(
            language,
            languages: model.transcriptionLanguageOptions,
            prefersNativeAppleEnglish: model.provider == .nativeApple
        )
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    private func model(named modelName: String?) -> (any TranscriptionModel)? {
        guard let modelName else { return nil }
        return stateProvider?.allAvailableModels.first { $0.name == modelName }
    }

    private func modelResourcePlan(
        for selectedModelName: String?,
        stateProvider: any PowerModeStateProvider
    ) -> VoiceInkPowerModeTranscriptionModelResourcePlan {
        VoiceInkPowerModeTranscriptionModelResourcePlan.plan(
            selectedModelName: selectedModelName,
            currentModelName: stateProvider.currentTranscriptionModel?.name,
            availableModels: stateProvider.allAvailableModels.map(modelResourceFacts(for:)),
            availableLocalModelNames: Set(stateProvider.availableModels.map(\.name))
        )
    }

    private func modelResourceFacts(
        for model: any TranscriptionModel
    ) -> VoiceInkPowerModeTranscriptionModelResourceFacts {
        VoiceInkPowerModeTranscriptionModelResourceFacts(
            name: model.name,
            loadsLocalWhisperModel: model.provider == .whisper
        )
    }

    private func applyModelResourcePlan(
        _ plan: VoiceInkPowerModeTranscriptionModelResourcePlan,
        stateProvider: any PowerModeStateProvider
    ) async {
        guard let selectedModelName = plan.selectedModelName,
              let selectedModel = stateProvider.allAvailableModels.first(where: { $0.name == selectedModelName }) else {
            return
        }

        stateProvider.setDefaultTranscriptionModel(selectedModel)

        switch plan.action {
        case .none:
            break
        case .cleanupOnly:
            await stateProvider.cleanupModelResources()
        case .cleanupAndLoadLocalModel(let modelName):
            await stateProvider.cleanupModelResources()
            if let localModel = stateProvider.availableModels.first(where: { $0.name == modelName }) {
                do {
                    try await stateProvider.loadModel(localModel)
                } catch {
                    print("Power Mode: Failed to load local model '\(localModel.name)': \(error)")
                }
            }
        }
    }

    private func recoverSession() {
        guard let session = loadSession() else { return }
        print("Recovering abandoned Power Mode session.")
        Task {
            await endSession()
        }
    }

    private func saveSession(_ session: VoiceInkPowerModeSession) {
        do {
            try VoiceInkPowerModeSessionPreference.saveActiveSession(session)
        } catch {
            print("Error saving Power Mode session: \(error)")
        }
    }

    private func loadSession() -> VoiceInkPowerModeSession? {
        do {
            return try VoiceInkPowerModeSessionPreference.loadActiveSession()
        } catch {
            print("Error loading Power Mode session: \(error)")
            return nil
        }
    }

    private func clearSession() {
        VoiceInkPowerModeSessionPreference.clear()
    }
}
