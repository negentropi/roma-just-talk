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
        guard let enhancementService = enhancementService,
              let stateProvider = stateProvider else { return }

        await MainActor.run {
            enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
            enhancementService.useScreenCaptureContext = config.useScreenCapture

            if config.isAIEnhancementEnabled {
                if let selectedPromptUUID = config.selectedPromptUUID {
                    enhancementService.selectedPromptId = selectedPromptUUID
                }

                let aiService = enhancementService.getAIService()
                if let provider = config.selectedAIProviderKind {
                    aiService.selectedProvider = provider
                }
                if let model = config.selectedAIModel {
                    aiService.selectModel(model)
                }
            }

            VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(config.isTextFormattingEnabled)
            PunctuationCleanupMode.setCurrent(config.punctuationCleanupMode)
            VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(config.lowercaseTranscription)
        }

        if let modelName = config.selectedTranscriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }

        if let language = config.selectedLanguage {
            applyCompatibleLanguage(language, preferredModelName: config.selectedTranscriptionModelName)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .powerModeConfigurationApplied, object: nil)
        }
    }

    private func restoreState(_ state: VoiceInkPowerModeApplicationState) async {
        guard let enhancementService = enhancementService,
              let stateProvider = stateProvider else { return }

        await MainActor.run {
            enhancementService.isEnhancementEnabled = state.isEnhancementEnabled
            enhancementService.useScreenCaptureContext = state.useScreenCaptureContext
            enhancementService.selectedPromptId = state.selectedPromptUUID

            let aiService = enhancementService.getAIService()
            if let provider = state.selectedAIProviderKind {
                aiService.selectedProvider = provider
            }
            if let model = state.selectedAIModel {
                aiService.selectModel(model)
            }

            let cleanupRestore = state.cleanupRestore
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

        if let modelName = state.transcriptionModelName,
           let selectedModel = await stateProvider.allAvailableModels.first(where: { $0.name == modelName }),
           stateProvider.currentTranscriptionModel?.name != modelName {
            await handleModelChange(to: selectedModel)
        }

        if let language = state.selectedLanguage {
            applyCompatibleLanguage(language, preferredModelName: state.transcriptionModelName)
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

    private func handleModelChange(to newModel: any TranscriptionModel) async {
        guard let stateProvider = stateProvider else { return }

        await stateProvider.setDefaultTranscriptionModel(newModel)

        switch newModel.provider {
        case .whisper:
            await stateProvider.cleanupModelResources()
            if let whisperModel = await stateProvider.availableModels.first(where: { $0.name == newModel.name }) {
                do {
                    try await stateProvider.loadModel(whisperModel)
                } catch {
                    print("Power Mode: Failed to load local model '\(whisperModel.name)': \(error)")
                }
            }
        case .fluidAudio:
            await stateProvider.cleanupModelResources()
        default:
            await stateProvider.cleanupModelResources()
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
