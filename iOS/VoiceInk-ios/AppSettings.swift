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
    
    @Published private var apiKeysByProvider: [VoiceInkProviderKind: String]
    @Published private var verifiedAPIKeyProviders: Set<VoiceInkProviderKind>
    
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
        didSet { VoiceInkIOSWordReplacementPreference.save(wordReplacements) }
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
        

        self.apiKeysByProvider = Dictionary(
            uniqueKeysWithValues: VoiceInkProviderKind.userAPIKeyProviders.map { provider in
                (provider, Self.loadAPIKey(for: provider))
            }
        )
        self.verifiedAPIKeyProviders = VoiceInkProviderAPIKeyVerificationState.verifiedProviders()
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = VoiceInkAudioSessionTimeoutPreference.timeoutSeconds()
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        let cleanupSettings = VoiceInkTranscriptionCleanupSettings.current()
        self.punctuationCleanupMode = cleanupSettings.punctuationMode
        self.isTextFormattingEnabled = cleanupSettings.isTextFormattingEnabled
        self.lowercaseTranscription = cleanupSettings.lowercaseTranscription
        self.removeFillerWords = cleanupSettings.removeFillerWords
        self.fillerWords = VoiceInkFillerWordPreference.words()
        self.wordReplacements = VoiceInkIOSWordReplacementPreference.rules()
        self.selectedTranscriptionLanguage = VoiceInkTranscriptionLanguagePreference.selectedLanguage()

        repairSelectedModeId()
        repairSelectedTranscriptionLanguage()
    }

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        runtimeAPIKey(for: provider) ?? ""
    }

    func storedAPIKey(for provider: VoiceInkProviderKind) -> String {
        apiKeysByProvider[provider] ?? ""
    }

    func setAPIKey(_ key: String, for provider: VoiceInkProviderKind) {
        guard provider.requiresUserAPIKey else {
            return
        }

        let oldKey = apiKeysByProvider[provider] ?? ""
        apiKeysByProvider[provider] = key
        saveAPIKey(key, for: provider)

        if oldKey != key {
            setKeyVerified(false, for: provider)
        }
    }
    
    func isKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
        provider.isReady(
            userAPIKey: runtimeAPIKey(for: provider) ?? "",
            userAPIKeyVerified: verifiedAPIKeyProviders.contains(provider),
            localWhisperModelAvailable: LocalModelManager.shared.hasAvailableModel
        )
    }
    
    func setKeyVerified(_ verified: Bool, for provider: VoiceInkProviderKind) {
        guard provider.requiresUserAPIKey else {
            return
        }

        if verified {
            verifiedAPIKeyProviders.insert(provider)
        } else {
            verifiedAPIKeyProviders.remove(provider)
        }
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
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = VoiceInkDictionaryPolicy.wordReplacementInsertPlan(
            original: trimmedOriginal,
            replacement: trimmedReplacement,
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
        wordReplacements = wordReplacements.enumerated().compactMap { index, rule in
            offsets.contains(index) ? nil : rule
        }
    }

    var runtimeWordReplacementRules: [VoiceInkWordReplacementRule] {
        VoiceInkWordReplacementEngine.sortedRules(wordReplacements)
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

    private func runtimeAPIKey(for provider: VoiceInkProviderKind) -> String? {
        guard provider.requiresUserAPIKey else {
            return provider.runtimeAPIKeyIfAvailable(userAPIKey: "")
        }

        return VoiceInkProviderAPIKeyLookup.usableAPIKey(
            storedKey: apiKeysByProvider[provider],
            provider: provider
        )
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        let defaults = VoiceInkDefaultSettings.iOS

        // Clear modes and selection
        modes = []
        selectedModeId = nil

        // Clear verification flags
        verifiedAPIKeyProviders = []
        
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
        selectedTranscriptionLanguage = defaults.selectedTranscriptionLanguage
        VoiceInkSharedPreferenceReset.clearCoreUserSettings()
        VoiceInkIOSWordReplacementPreference.clear()

        // Clear API keys from memory and Keychain
        apiKeysByProvider = [:]
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.deleteAPIKey)
    }
}

enum VoiceInkIOSWordReplacementPreference {
    static let key = "voiceInkIOSWordReplacements"

    static func rules(from defaults: UserDefaults = .standard) -> [VoiceInkWordReplacementRule] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([VoiceInkWordReplacementRule].self, from: data)) ?? []
    }

    static func save(_ rules: [VoiceInkWordReplacementRule], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(rules) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
