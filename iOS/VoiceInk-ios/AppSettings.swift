import Foundation
import Combine
import OSLog
import VoiceInkCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Modes system
    @Published var modes: [Mode] {
        didSet {
            VoiceInkModeStorage.saveModes(modes)
            repairModeSettingsSelection()
        }
    }
    
    @Published var selectedModeId: UUID? {
        didSet {
            VoiceInkModeStorage.saveSelectedModeId(selectedModeId)
            repairModeSettingsSelection()
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

        repairModeSettingsSelection()
    }

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.runtimeAPIKey(for: provider) ?? ""
    }

    func storedAPIKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.storedAPIKey(for: provider)
    }

    private var providerAccessSnapshot: VoiceInkProviderAccessSnapshot {
        VoiceInkProviderAccessSnapshot(
            apiKeyState: apiKeyState,
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }

    func setAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingStoredAPIKey(key, for: provider),
            for: provider
        )
    }
    
    func isKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
        providerAccessSnapshot.isKeyVerified(for: provider)
    }

    func apiKeyListRows() -> [VoiceInkProviderAPIKeyListRow] {
        providerAccessSnapshot.apiKeyListRows()
    }

    var modeFormProviderAvailability: VoiceInkModeFormProviderAvailability {
        providerAccessSnapshot.modeFormProviderAvailability
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
    
    private func repairModeSettingsSelection() {
        applyModeSettingsRepairPlan(
            VoiceInkModeSettingsPolicy.repairPlan(
                modes: modes,
                selectedModeId: selectedModeId,
                selectedTranscriptionLanguage: selectedTranscriptionLanguage
            )
        )
    }
    
    // MARK: - Mode-based Settings

    var transcriptionRunSettings: VoiceInkTranscriptionRunSettings {
        VoiceInkTranscriptionRunSettingsPolicy.iOSAppSettingsSnapshot(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage,
            wordReplacementRules: wordReplacements,
            customVocabulary: customVocabularyTerms
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

    func applyFillerWordSubmissionPlan(_ plan: VoiceInkFillerWordSubmissionPlan) {
        plan.applyRuntimeState(currentWords: fillerWords) { fillerWords = $0 }
    }

    func removeFillerWords(at offsets: IndexSet) {
        fillerWords = VoiceInkFillerWords.removing(at: offsets, from: fillerWords)
    }

    func applyWordReplacementSubmissionPlan(_ plan: VoiceInkWordReplacementSubmissionPlan) {
        plan.applyRuntimeState(currentRules: wordReplacements) { wordReplacements = $0 }
    }

    func sortedWordReplacements(
        mode: VoiceInkWordReplacementSortMode
    ) -> [VoiceInkWordReplacementRule] {
        VoiceInkDictionaryListSortPolicy.sortedWordReplacements(
            wordReplacements,
            mode: mode,
            originalText: { $0.originalText },
            replacementText: { $0.replacementText }
        )
    }

    func removeWordReplacements(
        atSortedOffsets offsets: IndexSet,
        mode: VoiceInkWordReplacementSortMode
    ) {
        wordReplacements = VoiceInkDictionaryListSortPolicy.removingWordReplacements(
            atSortedOffsets: offsets,
            from: wordReplacements,
            mode: mode,
            originalText: { $0.originalText },
            replacementText: { $0.replacementText }
        )
    }

    func applyCustomVocabularySubmissionPlan(_ plan: VoiceInkVocabularySubmissionPlan) {
        plan.applyRuntimeState(currentWords: customVocabularyTerms) { customVocabularyTerms = $0 }
    }

    func sortedCustomVocabularyTerms(mode: VoiceInkVocabularySortMode) -> [String] {
        VoiceInkDictionaryListSortPolicy.sortedVocabulary(
            customVocabularyTerms,
            mode: mode,
            word: { $0 }
        )
    }

    func removeCustomVocabularyTerms(
        atSortedOffsets offsets: IndexSet,
        mode: VoiceInkVocabularySortMode
    ) {
        customVocabularyTerms = VoiceInkDictionaryListSortPolicy.removingVocabulary(
            atSortedOffsets: offsets,
            from: customVocabularyTerms,
            mode: mode,
            word: { $0 }
        )
    }

    var availableTranscriptionLanguages: [String: String] {
        modes.transcriptionLanguages(selectedModeId: selectedModeId)
    }

    func setSelectedTranscriptionLanguage(_ language: String) {
        selectedTranscriptionLanguage = language
        repairSelectedTranscriptionLanguage()
    }

    func repairSelectedTranscriptionLanguage() {
        repairModeSettingsSelection()
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
