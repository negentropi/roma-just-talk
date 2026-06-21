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
            repairSelectedModeId()
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
        // Load modes
        self.modes = VoiceInkModeStorage.loadModes()
        
        // Load selected mode
        self.selectedModeId = VoiceInkModeStorage.loadSelectedModeId()
        

        self.apiKeyState = VoiceInkProviderAPIKeyState.loadingStoredKeys(
            verifiedProviders: VoiceInkProviderAPIKeyVerificationState.verifiedProviders(),
            loadStoredAPIKey: Self.loadAPIKey(for:)
        )
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = VoiceInkAudioSessionTimeoutPreference.timeoutSeconds()
        VoiceInkStartupPreferenceMigration.migrateLegacyPreferences(for: .iOS)
        let cleanupSettings = VoiceInkTranscriptionCleanupSettings.current()
        self.punctuationCleanupMode = cleanupSettings.punctuationMode
        self.isTextFormattingEnabled = cleanupSettings.isTextFormattingEnabled
        self.lowercaseTranscription = cleanupSettings.lowercaseTranscription
        self.removeFillerWords = cleanupSettings.removeFillerWords
        self.fillerWords = VoiceInkFillerWordPreference.words()
        self.wordReplacements = VoiceInkWordReplacementPreference.rules()
        self.customVocabularyTerms = VoiceInkCustomVocabularyPreference.terms()
        self.selectedTranscriptionLanguage = VoiceInkTranscriptionLanguagePreference.selectedLanguage()

        repairSelectedModeId()
        repairSelectedTranscriptionLanguage()
    }

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.runtimeAPIKey(for: provider) ?? ""
    }

    func storedAPIKey(for provider: VoiceInkProviderKind) -> String {
        apiKeyState.storedAPIKey(for: provider)
    }

    func setAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        var updatedState = apiKeyState
        let plan = updatedState.applyStoredAPIKey(key, for: provider)
        guard plan.shouldPersistStoredKey else { return }

        apiKeyState = updatedState
        saveAPIKey(key, for: provider)
        if let verificationFlag = plan.verificationFlagToPersist {
            VoiceInkProviderAPIKeyVerificationState.setVerified(verificationFlag, for: provider)
        }
    }
    
    func isKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
        apiKeyState.isReady(
            for: provider,
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }

    func apiKeyListRows() -> [VoiceInkProviderAPIKeyListRow] {
        apiKeyState.listRows(
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }

    func availableProviders(for use: VoiceInkProviderModelUse) -> [VoiceInkProviderKind] {
        apiKeyState.availableProviders(
            for: use,
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }

    var modeFormProviderAvailability: VoiceInkModeFormProviderAvailability {
        VoiceInkModeFormProviderAvailability(
            transcriptionProviders: availableProviders(for: .transcription),
            postProcessingProviders: availableProviders(for: .postProcessing)
        )
    }
    
    func setKeyVerified(_ verified: Bool, for provider: VoiceInkProviderKind) {
        var updatedState = apiKeyState
        let plan = updatedState.applyVerification(verified, for: provider)
        guard plan.shouldPersistVerificationFlag else { return }

        apiKeyState = updatedState
        VoiceInkProviderAPIKeyVerificationState.setVerified(verified, for: provider)
    }


    // MARK: - Modes Management
    
    private func repairSelectedModeId() {
        let repairedModeId = modes.repairedSelectedModeId(selectedModeId)
        if selectedModeId != repairedModeId {
            selectedModeId = repairedModeId
        }
    }
    
    // MARK: - Mode-based Settings

    var effectiveModeConfiguration: VoiceInkModeRuntimeConfiguration {
        modes.runtimeConfiguration(selectedModeId: selectedModeId)
    }

    var transcriptionCleanupConfiguration: VoiceInkTranscriptionCleanupConfiguration {
        VoiceInkTranscriptionCleanupConfiguration.current()
    }

    var localWhisperPrompt: String {
        VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage()
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
        modes = VoiceInkPreferenceList.removing(at: offsets, from: modes)
    }

    func applyFillerWordSubmissionPlan(_ plan: VoiceInkFillerWordSubmissionPlan) {
        if fillerWords != plan.updatedWords {
            fillerWords = plan.updatedWords
        }
    }

    func removeFillerWords(at offsets: IndexSet) {
        fillerWords = VoiceInkFillerWords.removing(at: offsets, from: fillerWords)
    }

    func applyWordReplacementSubmissionPlan(_ plan: VoiceInkWordReplacementSubmissionPlan) {
        let updatedRules = plan.applying(to: wordReplacements)
        if wordReplacements != updatedRules {
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
        let updatedTerms = plan.applying(to: customVocabularyTerms)
        if customVocabularyTerms != updatedTerms {
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
        let compatibleLanguage = modes.repairedSelectedTranscriptionLanguage(
            selectedTranscriptionLanguage,
            selectedModeId: selectedModeId
        )

        if selectedTranscriptionLanguage != compatibleLanguage {
            selectedTranscriptionLanguage = compatibleLanguage
        }
    }

    func ensureDefaultModeExists() {
        let plan = VoiceInkModeListPolicy.defaultModeRepairPlan(
            modes: modes,
            selectedModeId: selectedModeId
        )

        if plan.shouldReplaceModes {
            modes = plan.modes
        }

        if selectedModeId != plan.selectedModeId {
            selectedModeId = plan.selectedModeId
        }
    }

    func completeFirstTimeSetup() {
        ensureDefaultModeExists()
        VoiceInkOnboardingPreference.saveHasCompletedOnboarding()
    }

    private func saveAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        guard let account = provider.apiKeyAccount else { return }
        guard let status = VoiceInkKeychainValueStore.saveString(key, account: account) else { return }
        if status != errSecSuccess {
            VoiceInkIOSLogger.settings.error("Error saving API key to keychain: \(status, privacy: .public)")
        }
    }
    
    private static func loadAPIKey(for provider: VoiceInkProviderKind) -> String {
        guard let account = provider.apiKeyAccount else { return "" }
        return VoiceInkKeychainValueStore.loadString(account: account).value ?? ""
    }

    private static func deleteAPIKey(for provider: VoiceInkProviderKind) {
        guard let account = provider.apiKeyAccount else { return }
        VoiceInkKeychainValueStore.deleteValue(account: account)
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        let resetState = VoiceInkDefaultSettings.iOS.appSettingsResetState

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
        VoiceInkSharedPreferenceReset.clearCoreUserSettings()

        resetState.apiKeyProvidersToDelete.forEach(Self.deleteAPIKey)
    }
}
