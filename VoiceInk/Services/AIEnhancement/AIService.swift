import Foundation
import LLMkit
import VoiceInkCore

extension VoiceInkAIEnhancementProviderKind {
    var baseURL: String {
        if let corePostProcessingURL = aiModelProvider?.postProcessingRequestURL {
            return corePostProcessingURL.absoluteString
        }

        switch self {
        case .ollama:
            return VoiceInkDynamicAIProviderPreference.ollamaBaseURL()
        case .localCLI:
            return ""
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderBaseURL()
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkProviderEndpoint")
        }
    }
    
    var defaultModel: String {
        if let provider = aiModelProvider {
            return VoiceInkAIModelCatalog.defaultModel(for: provider)
        }

        switch self {
        case .ollama:
            return VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(fallback: "mistral")
        case .localCLI:
            return "local-cli"
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderModel()
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }
    
    var availableModels: [String] {
        if let provider = aiModelProvider {
            return VoiceInkAIModelCatalog.availableModels(for: provider)
        }

        switch self {
        case .ollama:
            return []
        case .localCLI:
            return []
        case .custom:
            return []
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }

}

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = VoiceInkDynamicAIProviderPreference.customProviderBaseURL() {
        didSet {
            VoiceInkDynamicAIProviderPreference.saveCustomProviderBaseURL(customBaseURL, to: userDefaults)
        }
    }
    @Published var customModel: String = VoiceInkDynamicAIProviderPreference.customProviderModel() {
        didSet {
            VoiceInkDynamicAIProviderPreference.saveCustomProviderModel(customModel, to: userDefaults)
        }
    }
    @Published var selectedProvider: VoiceInkAIEnhancementProviderKind {
        didSet {
            VoiceInkAIEnhancementProviderPreference.saveSelectedProviderRawValue(
                selectedProvider.rawValue,
                to: userDefaults
            )
            if selectedProvider.requiresUserAPIKey {
                if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue) {
                    self.apiKey = savedKey
                    self.isAPIKeyValid = true
                } else {
                    self.apiKey = ""
                    self.isAPIKeyValid = false
                }
            } else {
                self.apiKey = ""
                self.isAPIKeyValid = selectedProvider == .localCLI ? localCLIService.isConfigured : true
                if selectedProvider == .ollama {
                    Task {
                        await ollamaService.checkConnection()
                        await ollamaService.refreshModels()
                    }
                }
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }
    
    @Published private var selectedModels: [VoiceInkAIEnhancementProviderKind: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    
    @Published private var openRouterModels: [String] = []
    
    var connectedProviders: [VoiceInkAIEnhancementProviderKind] {
        VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
            hasUserAPIKey: { APIKeyManager.shared.hasAPIKey(forProvider: $0.rawValue) },
            isOllamaConnected: ollamaService.isConnected,
            isLocalCLIConfigured: localCLIService.isConfigured
        )
    }
    
    var currentModel: String {
        selectedProvider.selectedTextEnhancementModel(
            selectedModels[selectedProvider],
            availableModels: availableModels,
            defaultModel: selectedProvider.defaultModel
        )
    }
    
    var availableModels: [String] {
        availableModels(for: selectedProvider)
    }

    var localCLICommandTemplate: String {
        localCLIService.commandTemplate
    }

    var localCLITemplateSelection: LocalCLITemplate {
        localCLIService.selectedTemplate
    }

    var localCLITimeoutSeconds: Double {
        localCLIService.timeoutSeconds
    }

    func availableModels(for provider: VoiceInkAIEnhancementProviderKind) -> [String] {
        if provider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if provider == .openRouter {
            return openRouterModels
        }
        return provider.availableModels
    }
    
    init() {
        self.selectedProvider = VoiceInkAIEnhancementProviderPreference.selectedProvider(
            default: .gemini,
            from: userDefaults
        )

        if selectedProvider.requiresUserAPIKey {
            if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue) {
                self.apiKey = savedKey
                self.isAPIKeyValid = true
            }
        } else {
            self.isAPIKeyValid = selectedProvider == .localCLI ? localCLIService.isConfigured : true
        }

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
    }
    
    private func loadSavedModelSelections() {
        for provider in VoiceInkAIEnhancementProviderKind.allCases {
            if let savedModel = VoiceInkAIEnhancementProviderPreference.selectedModel(
                for: provider.rawValue,
                from: userDefaults
            ) {
                selectedModels[provider] = savedModel
            }
        }
    }
    
    private func loadSavedOpenRouterModels() {
        openRouterModels = VoiceInkDynamicAIProviderPreference.openRouterModels(from: userDefaults)
    }
    
    private func saveOpenRouterModels() {
        VoiceInkDynamicAIProviderPreference.saveOpenRouterModels(openRouterModels, to: userDefaults)
    }
    
    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        
        selectedModels[selectedProvider] = model
        VoiceInkAIEnhancementProviderPreference.saveSelectedModel(
            model,
            for: selectedProvider.rawValue,
            to: userDefaults
        )
        
        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }
        
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresUserAPIKey else {
            completion(true, nil)
            return
        }

        guard let resolvedKey = VoiceInkAPIKeyReference.resolvedValue(key) else {
            completion(false, "Environment variable is missing or empty")
            return
        }

        verifyAPIKey(key) { [weak self] isValid, errorMessage in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isValid {
                    self.apiKey = resolvedKey
                    self.isAPIKeyValid = true
                    APIKeyManager.shared.saveAPIKey(key, forProvider: self.selectedProvider.rawValue)
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    self.isAPIKeyValid = false
                }
                completion(isValid, errorMessage)
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresUserAPIKey else {
            completion(true, nil)
            return
        }

        guard let resolvedKey = VoiceInkAPIKeyReference.resolvedValue(key) else {
            completion(false, "Environment variable is missing or empty")
            return
        }

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            guard let route = selectedProvider.apiKeyVerificationRoute else {
                DispatchQueue.main.async {
                    completion(false, "\(self.selectedProvider.rawValue) does not support API key verification.")
                }
                return
            }

            switch route {
            case .sharedProvider(let provider):
                let verification = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(
                    resolvedKey,
                    for: provider
                )
                result = (verification.isValid, verification.errorMessage)
            case .anthropicMessages:
                result = await AnthropicLLMClient.verifyAPIKey(resolvedKey)
            case .openAICompatibleModels:
                guard let baseURL = URL(string: selectedProvider.baseURL) else {
                    DispatchQueue.main.async {
                        completion(false, "Invalid or missing base URL configuration")
                    }
                    return
                }
                result = await OpenAILLMClient.verifyAPIKey(
                    baseURL: baseURL,
                    apiKey: resolvedKey,
                    model: currentModel
                )
            case .openRouterModels:
                result = await OpenRouterClient.verifyAPIKey(resolvedKey, model: currentModel)
            }
            DispatchQueue.main.async {
                completion(result.isValid, result.errorMessage)
            }
        }
    }
    
    func clearAPIKey() {
        guard selectedProvider.requiresUserAPIKey else { return }

        apiKey = ""
        isAPIKeyValid = false
        APIKeyManager.shared.deleteAPIKey(forProvider: selectedProvider.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }
    
    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.ollamaService.checkConnection()
            DispatchQueue.main.async {
                completion(self.ollamaService.isConnected)
            }
        }
    }
    
    func fetchOllamaModels() async -> [OllamaModel] {
        await ollamaService.refreshModels()
        return ollamaService.availableModels
    }
    
    func enhanceWithOllama(text: String, systemPrompt: String, timeout: TimeInterval = 30) async throws -> String {
        try await ollamaService.enhance(text, withSystemPrompt: systemPrompt, timeout: timeout)
    }
    
    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
    }
    
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
    }

    func loadLocalCLITemplate(_ template: LocalCLITemplate) {
        localCLIService.loadTemplate(template)
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLICommandTemplate(_ command: String) {
        localCLIService.commandTemplate = command
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLITimeoutSeconds(_ timeout: Double) {
        localCLIService.timeoutSeconds = timeout
        refreshLocalCLIConfigurationState()
    }

    func enhanceWithLocalCLI(systemPrompt: String, userPrompt: String) async throws -> String {
        try await localCLIService.enhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    private func refreshLocalCLIConfigurationState() {
        if selectedProvider == .localCLI {
            isAPIKeyValid = localCLIService.isConfigured
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func fetchOpenRouterModels() async {
        do {
            let models = try await OpenRouterClient.fetchModels()
            await MainActor.run {
                self.openRouterModels = models
                self.saveOpenRouterModels()
                if self.selectedProvider == .openRouter && self.currentModel == self.selectedProvider.defaultModel && !models.isEmpty {
                    self.selectModel(models.first!)
                }
                self.objectWillChange.send()
            }
        } catch {
            await MainActor.run {
                self.openRouterModels = []
                self.saveOpenRouterModels()
                self.objectWillChange.send()
            }
        }
    }
}
