import Foundation
import Combine
import VoiceInkCore

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Modes system
    @Published var modes: [Mode] {
        didSet { saveModes() }
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
        guard let selectedModeId = selectedModeId else { return nil }
        return modes.first { $0.id == selectedModeId }
    }



    // Separate API keys per provider
    @Published var groqAPIKey: String {
        didSet { saveAPIKey(groqAPIKey, for: .groq) }
    }

    @Published var openAIAPIKey: String {
        didSet { saveAPIKey(openAIAPIKey, for: .openai) }
    }

    @Published var deepgramAPIKey: String {
        didSet { saveAPIKey(deepgramAPIKey, for: .deepgram) }
    }

    @Published var cerebrasAPIKey: String {
        didSet { saveAPIKey(cerebrasAPIKey, for: .cerebras) }
    }

    @Published var geminiAPIKey: String {
        didSet { saveAPIKey(geminiAPIKey, for: .gemini) }
    }
    
    // Track verification status per provider
    @Published var groqKeyVerified: Bool {
        didSet { saveKeyVerified(groqKeyVerified, for: .groq) }
    }
    
    @Published var openAIKeyVerified: Bool {
        didSet { saveKeyVerified(openAIKeyVerified, for: .openai) }
    }

    @Published var deepgramKeyVerified: Bool {
        didSet { saveKeyVerified(deepgramKeyVerified, for: .deepgram) }
    }

    @Published var cerebrasKeyVerified: Bool {
        didSet { saveKeyVerified(cerebrasKeyVerified, for: .cerebras) }
    }

    @Published var geminiKeyVerified: Bool {
        didSet { saveKeyVerified(geminiKeyVerified, for: .gemini) }
    }
    
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
        

        self.groqAPIKey = AppSettings.loadAPIKey(for: .groq)
        self.openAIAPIKey = AppSettings.loadAPIKey(for: .openai)
        self.deepgramAPIKey = AppSettings.loadAPIKey(for: .deepgram)
        self.cerebrasAPIKey = AppSettings.loadAPIKey(for: .cerebras)
        self.geminiAPIKey = AppSettings.loadAPIKey(for: .gemini)
        self.groqKeyVerified = Self.loadKeyVerified(for: .groq)
        self.openAIKeyVerified = Self.loadKeyVerified(for: .openai)
        self.deepgramKeyVerified = Self.loadKeyVerified(for: .deepgram)
        self.cerebrasKeyVerified = Self.loadKeyVerified(for: .cerebras)
        self.geminiKeyVerified = Self.loadKeyVerified(for: .gemini)
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: "audioSessionTimeoutSeconds") as? Int ?? 90

    }

    func apiKey(for provider: Provider) -> String {
        switch provider { 
        case .groq: return groqAPIKey
        case .openai: return openAIAPIKey
        case .deepgram: return deepgramAPIKey
        case .cerebras: return cerebrasAPIKey
        case .gemini: return geminiAPIKey
        case .local: return "local" // Local transcription doesn't need an API key
        case .voiceink: return "" // TODO: Replace with actual VoiceInk API key
        }
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        switch provider { 
        case .groq: 
            groqAPIKey = key
            // Reset verification status when key changes
            if groqAPIKey != key { groqKeyVerified = false }
        case .openai: 
            openAIAPIKey = key
            // Reset verification status when key changes
            if openAIAPIKey != key { openAIKeyVerified = false }
        case .deepgram:
            deepgramAPIKey = key
            // Reset verification status when key changes
            if deepgramAPIKey != key { deepgramKeyVerified = false }
        case .cerebras:
            cerebrasAPIKey = key
            // Reset verification status when key changes
            if cerebrasAPIKey != key { cerebrasKeyVerified = false }
        case .gemini:
            geminiAPIKey = key
            // Reset verification status when key changes
            if geminiAPIKey != key { geminiKeyVerified = false }
        case .local:
            break // Local provider doesn't use API keys
        case .voiceink:
            break // VoiceInk uses hardcoded API key
        }
    }
    
    func isKeyVerified(for provider: Provider) -> Bool {
        switch provider {
        case .groq: return groqKeyVerified && !groqAPIKey.isEmpty
        case .openai: return openAIKeyVerified && !openAIAPIKey.isEmpty
        case .deepgram: return deepgramKeyVerified && !deepgramAPIKey.isEmpty
        case .cerebras: return cerebrasKeyVerified && !cerebrasAPIKey.isEmpty
        case .gemini: return geminiKeyVerified && !geminiAPIKey.isEmpty
        case .local: return LocalModelManager.shared.hasAvailableModel
        case .voiceink: return true // VoiceInk uses hardcoded API key, always verified
        }
    }
    
    func setKeyVerified(_ verified: Bool, for provider: Provider) {
        switch provider {
        case .groq: groqKeyVerified = verified
        case .openai: openAIKeyVerified = verified
        case .deepgram: deepgramKeyVerified = verified
        case .cerebras: cerebrasKeyVerified = verified
        case .gemini: geminiKeyVerified = verified
        case .local: break // Local model status is handled by LocalModelManager
        case .voiceink: break // VoiceInk uses hardcoded API key, no verification needed
        }
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
    
    // MARK: - Mode-based Settings
    
    /// Get the effective transcription provider (from selected mode or first mode)
    var effectiveTranscriptionProvider: Provider {
        if let selectedMode = selectedMode {
            return selectedMode.transcriptionProvider
        } else if let firstMode = modes.first {
            return firstMode.transcriptionProvider
        } else {
            return .groq // Default fallback
        }
    }
    
    /// Get the effective transcription model (from selected mode or first mode)
    var effectiveTranscriptionModel: String {
        if let selectedMode = selectedMode {
            return selectedMode.transcriptionProvider.fixedModel(for: .transcription) ?? selectedMode.transcriptionModel
        } else if let firstMode = modes.first {
            return firstMode.transcriptionProvider.fixedModel(for: .transcription) ?? firstMode.transcriptionModel
        } else {
            return VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        }
    }
    
    /// Get the effective post-processing provider (from selected mode or first mode)
    var effectivePostProcessingProvider: Provider {
        if let selectedMode = selectedMode {
            return selectedMode.postProcessingProvider
        } else if let firstMode = modes.first {
            return firstMode.postProcessingProvider
        } else {
            return .groq // Default fallback
        }
    }
    
    /// Get the effective post-processing model (from selected mode or first mode)
    var effectivePostProcessingModel: String {
        if let selectedMode = selectedMode {
            return selectedMode.postProcessingProvider.fixedModel(for: .postProcessing) ?? selectedMode.postProcessingModel
        } else if let firstMode = modes.first {
            return firstMode.postProcessingProvider.fixedModel(for: .postProcessing) ?? firstMode.postProcessingModel
        } else {
            return effectivePostProcessingProvider.fixedModel(for: .postProcessing) ?? VoiceInkAIModelCatalog.firstAvailableModel(for: .groq) // Default fallback
        }
    }
    
    /// Get the effective custom prompt (from selected mode or first mode)
    var effectiveCustomPrompt: String {
        if let selectedMode = selectedMode {
            return selectedMode.effectivePrompt
        } else if let firstMode = modes.first {
            return firstMode.effectivePrompt
        } else {
            return "" // Default fallback
        }
    }
    
    /// Get whether post-processing is enabled (from selected mode or first mode)
    var effectiveIsPostProcessingEnabled: Bool {
        if let selectedMode = selectedMode {
            return selectedMode.isPostProcessingEnabled
        } else if let firstMode = modes.first {
            return firstMode.isPostProcessingEnabled
        } else {
            return false // Default fallback
        }
    }
    
    private func saveAPIKey(_ key: String, forKey account: String) {
        guard let data = key.data(using: .utf8) else { return }
        let status = KeychainService.save(key: account, data: data)
        if status != errSecSuccess {
            print("Error saving API key to keychain: \(status)")
        }
    }

    private func saveAPIKey(_ key: String, for provider: Provider) {
        guard let account = provider.apiKeyAccount else { return }
        saveAPIKey(key, forKey: account)
    }
    
    private static func loadAPIKey(forKey account: String) -> String {
        if let data = KeychainService.load(key: account), let key = String(data: data, encoding: .utf8) {
            return key
        }
        return ""
    }

    private static func loadAPIKey(for provider: Provider) -> String {
        guard let account = provider.apiKeyAccount else { return "" }
        return loadAPIKey(forKey: account)
    }

    private static func deleteAPIKey(for provider: Provider) {
        guard let account = provider.apiKeyAccount else { return }
        _ = KeychainService.delete(key: account)
    }

    private func saveKeyVerified(_ verified: Bool, for provider: Provider) {
        guard let key = provider.apiKeyVerificationStateKey else { return }
        UserDefaults.standard.set(verified, forKey: key)
    }

    private static func loadKeyVerified(for provider: Provider) -> Bool {
        guard let key = provider.apiKeyVerificationStateKey else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func clearKeyVerified(for provider: Provider) {
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
        groqKeyVerified = false
        openAIKeyVerified = false
        deepgramKeyVerified = false
        cerebrasKeyVerified = false
        geminiKeyVerified = false
        Self.clearKeyVerified(for: .groq)
        Self.clearKeyVerified(for: .openai)
        Self.clearKeyVerified(for: .deepgram)
        Self.clearKeyVerified(for: .cerebras)
        Self.clearKeyVerified(for: .gemini)
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = 90
        UserDefaults.standard.removeObject(forKey: "audioSessionTimeoutSeconds")

        // Clear API keys from memory and Keychain
        groqAPIKey = ""
        openAIAPIKey = ""
        deepgramAPIKey = ""
        cerebrasAPIKey = ""
        geminiAPIKey = ""
        Self.deleteAPIKey(for: .groq)
        Self.deleteAPIKey(for: .openai)
        Self.deleteAPIKey(for: .deepgram)
        Self.deleteAPIKey(for: .cerebras)
        Self.deleteAPIKey(for: .gemini)
    }
}
