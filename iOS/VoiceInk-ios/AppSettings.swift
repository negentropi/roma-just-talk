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

    func availableProviders(for use: VoiceInkProviderModelUse) -> [VoiceInkProviderKind] {
        providerAccessSnapshot.availableProviders(for: use)
    }

    var modeFormProviderAvailability: VoiceInkModeFormProviderAvailability {
        providerAccessSnapshot.modeFormProviderAvailability
    }
    
    func setKeyVerified(_ verified: Bool, for provider: VoiceInkProviderKind) {
        applyProviderAPIKeyStateUpdatePlan(
            apiKeyState.applyingVerification(verified, for: provider),
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
        guard plan.shouldApplyState else { return }

        apiKeyState = plan.state
        applyProviderAPIKeyStatePersistenceActions(plan.persistenceActions, for: provider)
    }

    private func applyProviderAPIKeyStatePersistenceActions(
        _ actions: [VoiceInkProviderAPIKeyStatePersistenceAction],
        for provider: VoiceInkProviderKind
    ) {
        for action in actions {
            switch action {
            case .persistStoredKey(let key):
                saveAPIKey(key, for: provider)
            case .persistVerificationFlag(let flag):
                VoiceInkProviderAPIKeyVerificationState.setVerified(flag, for: provider)
            }
        }
    }

    func applyAPIKeyVerificationPlan(
        _ plan: VoiceInkProviderAPIKeyVerificationApplicationPlan,
        for provider: VoiceInkProviderKind
    ) {
        guard let persistenceApplicationPlan = plan.successPersistenceApplicationPlan else { return }

        for action in persistenceApplicationPlan.actions {
            switch action {
            case .saveKey(let key):
                setAPIKey(key, for: provider)
            case .persistVerificationFlag(let flag):
                setKeyVerified(flag, for: provider)
            }
        }
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
        if let updatedWords = plan.updatedWordsIfChanged(from: fillerWords) {
            fillerWords = updatedWords
        }
    }

    func removeFillerWords(at offsets: IndexSet) {
        fillerWords = VoiceInkFillerWords.removing(at: offsets, from: fillerWords)
    }

    func applyWordReplacementSubmissionPlan(_ plan: VoiceInkWordReplacementSubmissionPlan) {
        if let updatedRules = plan.updatedRulesIfChanged(from: wordReplacements) {
            wordReplacements = updatedRules
        }
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
        if let updatedTerms = plan.updatedWordsIfChanged(from: customVocabularyTerms) {
            customVocabularyTerms = updatedTerms
        }
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
        for action in plan.applicationActions(
            currentSelectedModeId: selectedModeId,
            currentSelectedTranscriptionLanguage: selectedTranscriptionLanguage
        ) {
            switch action {
            case .replaceModes(let actionModes):
                modes = actionModes
            case .selectMode(let actionSelectedModeId):
                selectedModeId = actionSelectedModeId
            case .selectTranscriptionLanguage(let actionLanguage):
                selectedTranscriptionLanguage = actionLanguage
            }
        }
    }

    func completeFirstTimeSetup() {
        applyFirstTimeSetupPlan(VoiceInkIOSFirstTimeSetupPolicy.plan(
            modes: modes,
            selectedModeId: selectedModeId,
            selectedTranscriptionLanguage: selectedTranscriptionLanguage
        ))
    }

    private func applyFirstTimeSetupPlan(_ plan: VoiceInkIOSFirstTimeSetupPlan) {
        for action in plan.applicationActions {
            switch action {
            case .applyModeSettingsRepair(let modeSettingsRepairPlan):
                applyModeSettingsRepairPlan(modeSettingsRepairPlan)
            case .saveHasCompletedOnboarding:
                VoiceInkOnboardingPreference.saveHasCompletedOnboarding()
            }
        }
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
        for action in VoiceInkDefaultSettings.iOS.appSettingsResetState.applicationActions {
            applyAppSettingsResetAction(action)
        }
    }

    private func applyAppSettingsResetAction(_ action: VoiceInkAppSettingsResetAction) {
        switch action {
        case .applyResetState(let resetState):
            applyAppSettingsResetState(resetState)
        case .clearCoreUserSettings:
            VoiceInkSharedPreferenceReset.clearCoreUserSettings()
        case .deleteProviderAPIKeys(let providers):
            providers.forEach(Self.deleteAPIKey)
        }
    }

    private func applyAppSettingsResetState(_ resetState: VoiceInkAppSettingsResetState) {
        modes = resetState.modes
        selectedModeId = resetState.selectedModeId
        apiKeyState = resetState.apiKeyState
        audioSessionTimeoutSeconds = resetState.audioSessionTimeoutSeconds

        let cleanupSettings = resetState.transcriptionCleanupSettings
        punctuationCleanupMode = cleanupSettings.punctuationMode
        isTextFormattingEnabled = cleanupSettings.isTextFormattingEnabled
        lowercaseTranscription = cleanupSettings.lowercaseTranscription
        removeFillerWords = cleanupSettings.removeFillerWords
        fillerWords = resetState.fillerWords
        wordReplacements = resetState.wordReplacements
        customVocabularyTerms = resetState.customVocabularyTerms
        selectedTranscriptionLanguage = resetState.selectedTranscriptionLanguage
    }
}
