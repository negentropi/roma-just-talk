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
    
    var selectedMode: Mode? {
        modes.activeMode(selectedModeId: selectedModeId)
    }

    @Published private var apiKeysByProvider: [VoiceInkProviderKind: String]
    @Published private var verifiedAPIKeyProviders: Set<VoiceInkProviderKind>
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(audioSessionTimeoutSeconds, forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) }
    }

    @Published var punctuationCleanupMode: PunctuationCleanupMode {
        didSet { PunctuationCleanupMode.setCurrent(punctuationCleanupMode) }
    }

    @Published var isTextFormattingEnabled: Bool {
        didSet { UserDefaults.standard.set(isTextFormattingEnabled, forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled) }
    }

    @Published var lowercaseTranscription: Bool {
        didSet { UserDefaults.standard.set(lowercaseTranscription, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription) }
    }

    @Published var removeFillerWords: Bool {
        didSet { UserDefaults.standard.set(removeFillerWords, forKey: VoiceInkUserDefaultsKey.removeFillerWords) }
    }

    @Published var fillerWords: [String] {
        didSet { UserDefaults.standard.set(fillerWords, forKey: VoiceInkUserDefaultsKey.fillerWords) }
    }

    @Published var selectedTranscriptionLanguage: String {
        didSet {
            UserDefaults.standard.set(selectedTranscriptionLanguage, forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
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
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        self.punctuationCleanupMode = PunctuationCleanupMode.current()
        self.isTextFormattingEnabled = UserDefaults.standard.object(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled) as? Bool
            ?? VoiceInkPreferenceDefault.isTextFormattingEnabled
        self.lowercaseTranscription = UserDefaults.standard.object(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription) as? Bool
            ?? VoiceInkPreferenceDefault.lowercaseTranscription
        self.removeFillerWords = UserDefaults.standard.object(forKey: VoiceInkUserDefaultsKey.removeFillerWords) as? Bool
            ?? VoiceInkPreferenceDefault.removeFillerWords
        self.fillerWords = UserDefaults.standard.stringArray(forKey: VoiceInkUserDefaultsKey.fillerWords)
            ?? VoiceInkFillerWords.defaultWords
        self.selectedTranscriptionLanguage = UserDefaults.standard.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            ?? VoiceInkLanguageCatalog.autoDetectCode

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

    func addFillerWord(_ word: String) -> Bool {
        guard let updatedWords = VoiceInkFillerWords.adding(word, to: fillerWords) else {
            return false
        }

        fillerWords = updatedWords
        return true
    }

    func removeFillerWords(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            fillerWords.remove(at: index)
        }
    }

    var availableTranscriptionLanguages: [String: String] {
        guard let provider = selectedMode?.transcriptionProvider else {
            return VoiceInkLanguageCatalog.whisperLanguages()
        }
        return VoiceInkLanguageCatalog.languages(for: provider)
    }

    func setSelectedTranscriptionLanguage(_ language: String) {
        selectedTranscriptionLanguage = language
        repairSelectedTranscriptionLanguage()
    }

    func repairSelectedTranscriptionLanguage() {
        let compatibleLanguage = VoiceInkTranscriptionLanguageSupport.validLanguageOrFallback(
            selectedTranscriptionLanguage,
            languages: availableTranscriptionLanguages
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

        let defaultMode = Mode.defaultLocalWhisper()
        modes = [defaultMode]
        selectedModeId = defaultMode.id
    }

    func completeFirstTimeSetup() {
        ensureDefaultModeExists()
        UserDefaults.standard.set(true, forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)
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
            providerName: provider.displayName
        )
    }

    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        // Clear modes and selection
        modes = []
        selectedModeId = nil
        VoiceInkModeStorage.clear()
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.hasCompletedOnboarding)

        // Clear verification flags
        verifiedAPIKeyProviders = []
        VoiceInkProviderAPIKeyVerificationState.clearAll()
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)

        // Reset transcription cleanup preferences
        punctuationCleanupMode = .keep
        isTextFormattingEnabled = VoiceInkPreferenceDefault.isTextFormattingEnabled
        lowercaseTranscription = VoiceInkPreferenceDefault.lowercaseTranscription
        removeFillerWords = VoiceInkPreferenceDefault.removeFillerWords
        fillerWords = VoiceInkFillerWords.defaultWords
        UserDefaults.standard.removeObject(forKey: PunctuationCleanupMode.userDefaultsKey)
        UserDefaults.standard.set(false, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.isTextFormattingEnabled)
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.removeFillerWords)
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.fillerWords)
        selectedTranscriptionLanguage = VoiceInkLanguageCatalog.autoDetectCode
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)

        // Clear API keys from memory and Keychain
        apiKeysByProvider = [:]
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.deleteAPIKey)
    }
}
