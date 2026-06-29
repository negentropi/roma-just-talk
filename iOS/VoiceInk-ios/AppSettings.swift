import Foundation
import Combine
import OSLog
import VoiceInkCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var localModelAvailabilityCancellable: AnyCancellable?

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

    @Published var punctuationCleanupMode: PunctuationCleanupMode {
        didSet { PunctuationCleanupMode.setCurrent(punctuationCleanupMode) }
    }

    @Published var isTextFormattingEnabled: Bool {
        didSet { VoiceInkTranscriptionCleanupPreferenceStorage.saveTextFormattingEnabled(isTextFormattingEnabled) }
    }

    @Published var lowercaseTranscription: Bool {
        didSet { VoiceInkTranscriptionCleanupPreferenceStorage.saveLowercaseTranscription(lowercaseTranscription) }
    }

    @Published var removeFillerWords: Bool {
        didSet { VoiceInkTranscriptionCleanupPreferenceStorage.saveRemoveFillerWords(removeFillerWords) }
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
        self.punctuationCleanupMode = startupState.transcriptionCleanupSettings.punctuationMode
        self.isTextFormattingEnabled = startupState.transcriptionCleanupSettings.isTextFormattingEnabled
        self.lowercaseTranscription = startupState.transcriptionCleanupSettings.lowercaseTranscription
        self.removeFillerWords = startupState.transcriptionCleanupSettings.removeFillerWords
        self.fillerWords = startupState.fillerWords
        self.wordReplacements = startupState.wordReplacements
        self.customVocabularyTerms = startupState.customVocabularyTerms
        self.selectedTranscriptionLanguage = startupState.selectedTranscriptionLanguage

        observeLocalModelAvailability()
        repairSelectedTranscriptionLanguage()
    }

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.runtimeAPIKey(for: provider) ?? ""
    }

    var providerAccess: VoiceInkProviderAccessSnapshot {
        VoiceInkProviderAccessSnapshot(
            apiKeyState: apiKeyState,
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }

    private func observeLocalModelAvailability() {
        localModelAvailabilityCancellable = LocalModelManager.shared.$localModelAvailabilityRevision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
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

    func retranscribeStoredAudio(_ note: Transcription) async -> VoiceInkStoredAudioRetranscriptionOutcome {
        await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
            note,
            iOSAppSettingsRunSnapshotProvider: { [self] in
                await VoiceInkIOSAppSettingsRunSnapshot(
                    modes: modes,
                    selectedModeId: selectedModeId,
                    selectedTranscriptionLanguage: selectedTranscriptionLanguage,
                    wordReplacementRules: wordReplacements,
                    customVocabulary: customVocabularyTerms
                )
            },
            apiKeyProvider: { [self] provider in
                await apiKey(for: provider)
            },
            localWhisperServiceFactory: {
                WhisperTranscriptionService()
            }
        )
    }

    func addMode(_ mode: Mode) {
        modes = VoiceInkModeListPolicy.appending(mode, to: modes)
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

    func repairSelectedTranscriptionLanguage() {
        applyModeSettingsRepairPlan(
            VoiceInkModeSettingsPolicy.repairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            )
        )
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
            }
        )
    }

    private func saveAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        let result = VoiceInkProviderAPIKeyStorage.saveStoredKey(key, for: provider)
        if result.shouldReportFailure, let status = result.status {
            VoiceInkIOSLogger.settings.error("\(VoiceInkProviderAPIKeyStorageDiagnostics.saveFailureMessage(status: status), privacy: .public)")
        }
    }

    private static func deleteAPIKey(for provider: VoiceInkProviderKind) {
        VoiceInkProviderAPIKeyStorage.deleteStoredKey(for: provider)
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        VoiceInkDefaultSettings.iOS.appSettingsResetState.applyRuntimeState(
            setModes: { [self] in modes = $0 },
            setSelectedModeId: { [self] in selectedModeId = $0 },
            setAPIKeyState: { [self] in apiKeyState = $0 },
            setAudioSessionTimeoutSeconds: { [self] in audioSessionTimeoutSeconds = $0 },
            setTranscriptionCleanupSettings: { [self] cleanupSettings in
                punctuationCleanupMode = cleanupSettings.punctuationMode
                isTextFormattingEnabled = cleanupSettings.isTextFormattingEnabled
                lowercaseTranscription = cleanupSettings.lowercaseTranscription
                removeFillerWords = cleanupSettings.removeFillerWords
            },
            setFillerWords: { [self] in fillerWords = $0 },
            setWordReplacements: { [self] in wordReplacements = $0 },
            setCustomVocabularyTerms: { [self] in customVocabularyTerms = $0 },
            setSelectedTranscriptionLanguage: { [self] in selectedTranscriptionLanguage = $0 },
            clearCoreUserSettings: {
                VoiceInkSharedPreferenceReset.clearCoreUserSettings()
            },
            deleteProviderAPIKeys: { providers in
                providers.forEach(Self.deleteAPIKey)
            }
        )
    }
}
