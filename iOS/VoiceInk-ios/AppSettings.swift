import Foundation
import Combine
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
        

        let storedAPIKeys = Dictionary(
            uniqueKeysWithValues: VoiceInkProviderKind.userAPIKeyProviders.map { provider in
                (provider, Self.loadAPIKey(for: provider))
            }
        )
        self.apiKeyState = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: storedAPIKeys,
            verifiedProviders: VoiceInkProviderAPIKeyVerificationState.verifiedProviders()
        )
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = VoiceInkAudioSessionTimeoutPreference.timeoutSeconds()
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
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
        guard provider.requiresUserAPIKey else {
            return
        }

        var updatedState = apiKeyState
        let didResetVerification = updatedState.setStoredAPIKey(key, for: provider)
        apiKeyState = updatedState
        saveAPIKey(key, for: provider)

        if didResetVerification {
            VoiceInkProviderAPIKeyVerificationState.setVerified(false, for: provider)
        }
    }
    
    func isKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
        apiKeyState.isReady(
            for: provider,
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }
    
    func setKeyVerified(_ verified: Bool, for provider: VoiceInkProviderKind) {
        var updatedState = apiKeyState
        guard updatedState.setVerified(verified, for: provider) else {
            return
        }

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
        modes.append(mode)
    }

    func updateMode(_ updatedMode: Mode, replacing modeId: UUID) {
        guard let index = modes.firstIndex(where: { $0.id == modeId }) else {
            return
        }

        modes[index] = updatedMode
    }

    func removeModes(at offsets: IndexSet) {
        modes = VoiceInkPreferenceList.removing(at: offsets, from: modes)
    }

    func addFillerWord(_ word: String) -> Bool {
        guard let updatedWords = VoiceInkFillerWords.adding(word, to: fillerWords) else {
            return false
        }

        fillerWords = updatedWords
        return true
    }

    func removeFillerWords(at offsets: IndexSet) {
        fillerWords = VoiceInkFillerWords.removing(at: offsets, from: fillerWords)
    }

    @discardableResult
    func addWordReplacement(original: String, replacement: String) -> String? {
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: original,
            replacement: replacement,
            existingOriginalTexts: wordReplacements.map(\.originalText)
        )

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard plan.shouldInsert else {
            return nil
        }

        wordReplacements.append(VoiceInkWordReplacementRule(
            originalText: plan.originalText,
            replacementText: plan.replacementText
        ))
        return nil
    }

    func removeWordReplacements(at offsets: IndexSet) {
        wordReplacements = VoiceInkPreferenceList.removing(at: offsets, from: wordReplacements)
    }

    var runtimeWordReplacementRules: [VoiceInkWordReplacementRule] {
        VoiceInkWordReplacementEngine.sortedRules(wordReplacements)
    }

    @discardableResult
    func addCustomVocabularyTerms(_ input: String) -> String? {
        let plan = VoiceInkDictionaryPolicy.vocabularyInsertPlan(
            input: input,
            existingWords: customVocabularyTerms
        )

        if let errorMessage = plan.errorMessage {
            return errorMessage
        }

        guard plan.shouldInsert else {
            return nil
        }

        customVocabularyTerms.append(contentsOf: plan.wordsToInsert)
        return nil
    }

    func removeCustomVocabularyTerms(at offsets: IndexSet) {
        customVocabularyTerms = VoiceInkPreferenceList.removing(at: offsets, from: customVocabularyTerms)
    }

    var runtimeCustomVocabularyTerms: [String] {
        VoiceInkCustomVocabularyTerms.normalized(customVocabularyTerms)
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
        guard modes.isEmpty else {
            repairSelectedModeId()
            return
        }

        let defaultSelection = Mode.defaultModesAndSelection()
        modes = defaultSelection.modes
        selectedModeId = defaultSelection.selectedModeId
    }

    func completeFirstTimeSetup() {
        ensureDefaultModeExists()
        VoiceInkOnboardingPreference.saveHasCompletedOnboarding()
    }

    private func saveAPIKey(_ key: String, forKey account: String) {
        guard let data = key.data(using: .utf8) else { return }
        let status = KeychainService.save(key: account, data: data)
        if status != errSecSuccess {
            print("Error saving API key to keychain: \(status)")
        }
    }

    private func saveAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        guard let account = provider.apiKeyAccount else { return }
        saveAPIKey(key, forKey: account)
    }
    
    private static func loadAPIKey(forKey account: String) -> String {
        if let data = KeychainService.load(key: account), let key = String(data: data, encoding: .utf8) {
            return key
        }
        return ""
    }

    private static func loadAPIKey(for provider: VoiceInkProviderKind) -> String {
        guard let account = provider.apiKeyAccount else { return "" }
        return loadAPIKey(forKey: account)
    }

    private static func deleteAPIKey(for provider: VoiceInkProviderKind) {
        guard let account = provider.apiKeyAccount else { return }
        _ = KeychainService.delete(key: account)
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        let defaults = VoiceInkDefaultSettings.iOS

        // Clear modes and selection
        modes = []
        selectedModeId = nil

        // Clear verification flags
        apiKeyState = VoiceInkProviderAPIKeyState()
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = defaults.audioSessionTimeoutSeconds

        // Reset transcription cleanup preferences
        let cleanupSettings = defaults.transcriptionCleanupSettings
        punctuationCleanupMode = cleanupSettings.punctuationMode
        isTextFormattingEnabled = cleanupSettings.isTextFormattingEnabled
        lowercaseTranscription = cleanupSettings.lowercaseTranscription
        removeFillerWords = cleanupSettings.removeFillerWords
        fillerWords = defaults.fillerWords
        wordReplacements = []
        customVocabularyTerms = []
        selectedTranscriptionLanguage = defaults.selectedTranscriptionLanguage
        VoiceInkSharedPreferenceReset.clearCoreUserSettings()

        // Clear API keys from memory and Keychain
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.deleteAPIKey)
    }
}
