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
        }
    }
    
    @Published var selectedModeId: UUID? {
        didSet { VoiceInkModeStorage.saveSelectedModeId(selectedModeId) }
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

    @Published var lowercaseTranscription: Bool {
        didSet { UserDefaults.standard.set(lowercaseTranscription, forKey: VoiceInkUserDefaultsKey.lowercaseTranscription) }
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
        self.verifiedAPIKeyProviders = Set(
            VoiceInkProviderKind.userAPIKeyProviders.filter { Self.loadKeyVerified(for: $0) }
        )
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds) as? Int
            ?? VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
        PunctuationCleanupMode.migrateLegacyUserDefaultIfNeeded()
        self.punctuationCleanupMode = PunctuationCleanupMode.current()
        self.lowercaseTranscription = UserDefaults.standard.bool(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)

        repairSelectedModeId()
    }

    func apiKey(for provider: VoiceInkProviderKind) -> String {
        provider.runtimeAPIKey(userAPIKey: apiKeysByProvider[provider] ?? "")
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
            userAPIKey: apiKeysByProvider[provider] ?? "",
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
        saveKeyVerified(verified, for: provider)
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
        VoiceInkTranscriptionCleanupConfiguration(
            punctuationMode: punctuationCleanupMode,
            shouldLowercase: lowercaseTranscription
        )
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

    private func saveKeyVerified(_ verified: Bool, for provider: VoiceInkProviderKind) {
        guard let key = provider.apiKeyVerificationStateKey else { return }
        UserDefaults.standard.set(verified, forKey: key)
    }

    private static func loadKeyVerified(for provider: VoiceInkProviderKind) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func clearKeyVerified(for provider: VoiceInkProviderKind) {
        guard let key = provider.apiKeyVerificationStateKey else { return }
        UserDefaults.standard.removeObject(forKey: key)
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
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.clearKeyVerified)
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.audioSessionTimeoutSeconds)

        // Reset transcription cleanup preferences
        punctuationCleanupMode = .keep
        lowercaseTranscription = false
        UserDefaults.standard.removeObject(forKey: PunctuationCleanupMode.userDefaultsKey)
        UserDefaults.standard.set(false, forKey: PunctuationCleanupMode.legacyRemovePunctuationKey)
        UserDefaults.standard.removeObject(forKey: VoiceInkUserDefaultsKey.lowercaseTranscription)

        // Clear API keys from memory and Keychain
        apiKeysByProvider = [:]
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.deleteAPIKey)
    }
}
