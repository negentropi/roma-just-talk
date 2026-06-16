import Foundation
import Combine
import VoiceInkCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Modes system
    @Published var modes: [Mode] {
        didSet {
            saveModes()
            repairSelectedModeId()
        }
    }
    
    @Published var selectedModeId: UUID? {
        didSet { 
            if let id = selectedModeId {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedModeId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedModeId")
            }
        }
    }
    
    var selectedMode: Mode? {
        modes.activeMode(selectedModeId: selectedModeId)
    }

    @Published private var apiKeysByProvider: [VoiceInkProviderKind: String]
    @Published private var verifiedAPIKeyProviders: Set<VoiceInkProviderKind>
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(audioSessionTimeoutSeconds, forKey: "audioSessionTimeoutSeconds") }
    }


    private init() {
        // Load modes
        self.modes = Self.loadModes()
        
        // Load selected mode
        if let selectedModeIdString = UserDefaults.standard.string(forKey: "selectedModeId"),
           let selectedModeId = UUID(uuidString: selectedModeIdString) {
            self.selectedModeId = selectedModeId
        } else {
            self.selectedModeId = nil
        }
        

        self.apiKeysByProvider = Dictionary(
            uniqueKeysWithValues: VoiceInkProviderKind.userAPIKeyProviders.map { provider in
                (provider, Self.loadAPIKey(for: provider))
            }
        )
        self.verifiedAPIKeyProviders = Set(
            VoiceInkProviderKind.userAPIKeyProviders.filter { Self.loadKeyVerified(for: $0) }
        )
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: "audioSessionTimeoutSeconds") as? Int ?? 90

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
    
    private func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "modes")
        }
    }
    
    private static func loadModes() -> [Mode] {
        guard let data = UserDefaults.standard.data(forKey: "modes"),
              let modes = try? JSONDecoder().decode([Mode].self, from: data) else {
            return []
        }
        return modes
    }

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
        UserDefaults.standard.removeObject(forKey: "modes")
        UserDefaults.standard.removeObject(forKey: "selectedModeId")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // Clear verification flags
        verifiedAPIKeyProviders = []
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.clearKeyVerified)
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = 90
        UserDefaults.standard.removeObject(forKey: "audioSessionTimeoutSeconds")

        // Clear API keys from memory and Keychain
        apiKeysByProvider = [:]
        VoiceInkProviderKind.userAPIKeyProviders.forEach(Self.deleteAPIKey)
    }
}
