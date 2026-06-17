import Foundation
import LLMkit
import VoiceInkCore

typealias AIProvider = VoiceInkAIEnhancementProviderKind

extension AIProvider {
    var baseURL: String {
        if let corePostProcessingURL = coreAIModelProvider?.postProcessingRequestURL {
            return corePostProcessingURL.absoluteString
        }

        switch self {
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .localCLI:
            return ""
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkProviderEndpoint")
        }
    }
    
    var defaultModel: String {
        if let provider = coreAIModelProvider {
            return VoiceInkAIModelCatalog.defaultModel(for: provider)
        }

        switch self {
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .localCLI:
            return "local-cli"
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderModel") ?? ""
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }
    
    var availableModels: [String] {
        if let provider = coreAIModelProvider {
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

    var coreAIModelProvider: VoiceInkAIModelProvider? {
        aiModelProvider
    }

    var apiKeyConsoleURL: URL? {
        coreAIModelProvider?.apiKeyConsoleURL
    }

    var requiresAPIKey: Bool {
        requiresUserAPIKey
    }
}

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? "" {
        didSet {
            userDefaults.set(customBaseURL, forKey: "customProviderBaseURL")
        }
    }
    @Published var customModel: String = UserDefaults.standard.string(forKey: "customProviderModel") ?? "" {
        didSet {
            userDefaults.set(customModel, forKey: "customProviderModel")
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            if selectedProvider.requiresAPIKey {
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
    
    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    
    @Published private var openRouterModels: [String] = []
    
    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            if provider == .ollama {
                return ollamaService.isConnected
            } else if provider == .localCLI {
                return localCLIService.isConfigured
            } else if provider.requiresAPIKey {
                return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
            }
            return false
        }
    }
    
    var currentModel: String {
        if let selectedModel = selectedModels[selectedProvider],
           !selectedModel.isEmpty,
           (selectedProvider == .ollama && !selectedModel.isEmpty) || availableModels.contains(selectedModel) {
            return selectedModel
        }
        return selectedProvider.defaultModel
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

    func availableModels(for provider: AIProvider) -> [String] {
        if provider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if provider == .openRouter {
            return openRouterModels
        }
        return provider.availableModels
    }
    
    init() {
        if userDefaults.string(forKey: "selectedAIProvider") == "GROQ" {
            userDefaults.set("Groq", forKey: "selectedAIProvider")
        }

        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
           let provider = AIProvider(rawValue: savedProvider) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }

        if selectedProvider.requiresAPIKey {
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
        for provider in AIProvider.allCases {
            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }
    
    private func loadSavedOpenRouterModels() {
        if let savedModels = userDefaults.array(forKey: "openRouterModels") as? [String] {
            openRouterModels = savedModels
        }
    }
    
    private func saveOpenRouterModels() {
        userDefaults.set(openRouterModels, forKey: "openRouterModels")
    }
    
    func selectModel(_ model: String) {
        guard !model.isEmpty else { return }
        
        selectedModels[selectedProvider] = model
        let key = "\(selectedProvider.rawValue)SelectedModel"
        userDefaults.set(model, forKey: key)
        
        if selectedProvider == .ollama {
            updateSelectedOllamaModel(model)
        }
        
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        guard let resolvedKey = APIKeyManager.resolveAPIKeyReference(key) else {
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
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        guard let resolvedKey = APIKeyManager.resolveAPIKeyReference(key) else {
            completion(false, "Environment variable is missing or empty")
            return
        }

        Task {
            let result: (isValid: Bool, errorMessage: String?)
            guard let transport = selectedProvider.apiKeyVerificationTransport else {
                DispatchQueue.main.async {
                    completion(false, "\(self.selectedProvider.rawValue) does not support API key verification.")
                }
                return
            }

            switch transport {
            case .anthropicMessages:
                result = await AnthropicLLMClient.verifyAPIKey(resolvedKey)
            case .assemblyAITranscripts:
                result = await AssemblyAIClient.verifyAPIKey(resolvedKey)
            case .deepgramProjects:
                result = await DeepgramClient.verifyAPIKey(resolvedKey)
            case .elevenLabsUser:
                result = await ElevenLabsClient.verifyAPIKey(resolvedKey)
            case .geminiModels:
                result = await GeminiTranscriptionClient.verifyAPIKey(resolvedKey)
            case .mistralModels:
                result = await MistralTranscriptionClient.verifyAPIKey(resolvedKey)
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
            case .sonioxFiles:
                result = await SonioxClient.verifyAPIKey(resolvedKey)
            case .speechmaticsJobs:
                result = await SpeechmaticsClient.verifyAPIKey(resolvedKey)
            }
            DispatchQueue.main.async {
                completion(result.isValid, result.errorMessage)
            }
        }
    }
    
    func clearAPIKey() {
        guard selectedProvider.requiresAPIKey else { return }

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
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }
    
    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
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
