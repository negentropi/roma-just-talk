import Foundation
import LLMkit
import VoiceInkCore

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
            applyCredentialStateForSelectedProvider()
            if selectedProvider.textEnhancementModelCatalogSource == .ollamaRuntime {
                Task {
                    await ollamaService.checkConnection()
                    await ollamaService.refreshModels()
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
            defaultModel: selectedProvider.defaultTextEnhancementModel()
        )
    }
    
    var availableModels: [String] {
        availableModels(for: selectedProvider)
    }

    var localCLICommandTemplate: String {
        localCLIService.commandTemplate
    }

    var localCLITemplateSelection: VoiceInkLocalCLITemplate {
        localCLIService.selectedTemplate
    }

    var localCLITimeoutSeconds: Double {
        localCLIService.timeoutSeconds
    }

    func availableModels(for provider: VoiceInkAIEnhancementProviderKind) -> [String] {
        provider.textEnhancementAvailableModels(
            ollamaModels: ollamaService.availableModels.map { $0.name },
            openRouterModels: openRouterModels
        )
    }
    
    init() {
        self.selectedProvider = VoiceInkAIEnhancementProviderPreference.selectedProvider(
            default: .gemini,
            from: userDefaults
        )

        applyCredentialStateForSelectedProvider()

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
    }

    private func applyCredentialStateForSelectedProvider() {
        let savedKey = selectedProvider.requiresUserAPIKey
            ? APIKeyManager.shared.getAPIKey(forProvider: selectedProvider.rawValue)
            : nil
        let credentialState = selectedProvider.textEnhancementCredentialState(
            savedAPIKey: savedKey,
            isLocalCLIConfigured: localCLIService.isConfigured
        )

        apiKey = credentialState.apiKey
        isAPIKeyValid = credentialState.isAPIKeyValid
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
        
        if selectedProvider.textEnhancementModelCatalogSource == .ollamaRuntime {
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

        let draft = apiKeyDraft(for: key)
        guard let resolvedKey = draft.resolvedVerificationCandidate() else {
            completion(false, VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage)
            return
        }

        verifyResolvedAPIKey(resolvedKey) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let plan = draft.verificationApplicationPlan(
                    for: result,
                    resolvedRuntimeKey: resolvedKey
                )

                if let runtimeAPIKey = plan.runtimeAPIKey {
                    self.apiKey = runtimeAPIKey
                    self.isAPIKeyValid = plan.isValid
                    if let keyToSave = plan.keyToSave {
                        APIKeyManager.shared.saveAPIKey(keyToSave, forProvider: self.selectedProvider.rawValue)
                    }
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    self.isAPIKeyValid = plan.isValid
                }
                completion(plan.isValid, plan.errorMessage)
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresUserAPIKey else {
            completion(true, nil)
            return
        }

        guard let resolvedKey = apiKeyDraft(for: key).resolvedVerificationCandidate() else {
            completion(false, VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage)
            return
        }

        verifyResolvedAPIKey(resolvedKey) { result in
            completion(result.isValid, result.errorMessage)
        }
    }

    private func apiKeyDraft(for key: String) -> VoiceInkAIEnhancementAPIKeyDraft {
        VoiceInkAIEnhancementAPIKeyDraft(
            provider: selectedProvider,
            enteredKey: key
        )
    }

    private func verifyResolvedAPIKey(
        _ resolvedKey: String,
        completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void
    ) {
        Task {
            let result: VoiceInkAPIKeyVerificationResult
            guard let route = selectedProvider.apiKeyVerificationRoute else {
                DispatchQueue.main.async {
                    completion(VoiceInkAPIKeyVerificationResult(
                        isValid: false,
                        errorMessage: self.selectedProvider.unsupportedAPIKeyVerificationMessage
                    ))
                }
                return
            }

            switch route {
            case .sharedProvider(let provider):
                let verification = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(
                    resolvedKey,
                    for: provider
                )
                result = verification
            case .anthropicMessages:
                result = apiKeyVerificationResult(
                    from: await AnthropicLLMClient.verifyAPIKey(resolvedKey)
                )
            case .openAICompatibleModels:
                guard let baseURL = selectedProvider.textEnhancementRequestURL() else {
                    DispatchQueue.main.async {
                        completion(VoiceInkAPIKeyVerificationResult(
                            isValid: false,
                            errorMessage: VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
                        ))
                    }
                    return
                }
                result = apiKeyVerificationResult(
                    from: await OpenAILLMClient.verifyAPIKey(
                        baseURL: baseURL,
                        apiKey: resolvedKey,
                        model: currentModel
                    )
                )
            case .openRouterModels:
                result = apiKeyVerificationResult(
                    from: await OpenRouterClient.verifyAPIKey(
                        resolvedKey,
                        model: currentModel
                    )
                )
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func apiKeyVerificationResult(
        from legacyResult: (Bool, String?)
    ) -> VoiceInkAPIKeyVerificationResult {
        VoiceInkAPIKeyVerificationResult(isValid: legacyResult.0, errorMessage: legacyResult.1)
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

    func loadLocalCLITemplate(_ template: VoiceInkLocalCLITemplate) {
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
        if selectedProvider.textEnhancementSettingsSurface == .localCLI {
            applyCredentialStateForSelectedProvider()
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
                if let refreshedModel = self.selectedProvider.textEnhancementModelToSelectAfterRefresh(
                    currentModel: self.currentModel,
                    refreshedModels: models,
                    defaultModel: self.selectedProvider.defaultTextEnhancementModel()
                ) {
                    self.selectModel(refreshedModel)
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
