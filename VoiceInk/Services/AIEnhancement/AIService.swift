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
            applyTextEnhancementProviderSelectionPlan(
                VoiceInkAIEnhancementProviderSelectionPlan.selecting(selectedProvider)
            )
        }
    }
    
    @Published private var selectedModels: [VoiceInkAIEnhancementProviderKind: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    
    @Published private var openRouterModels: [String] = []
    
    var connectedProviders: [VoiceInkAIEnhancementProviderKind] {
        let providerKeyStorageNamesWithKeys = Set(
            VoiceInkAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck.filter {
                APIKeyManager.shared.hasAPIKey(forProvider: $0)
            }
        )

        VoiceInkAIEnhancementProviderKind.connectedTextEnhancementProviders(
            providerKeyStorageNamesWithKeys: providerKeyStorageNamesWithKeys,
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

        selectedModels = VoiceInkAIEnhancementProviderPreference.selectedModels(from: userDefaults)
        openRouterModels = VoiceInkDynamicAIProviderPreference.openRouterModels(from: userDefaults)
    }

    private func applyTextEnhancementProviderSelectionPlan(_ plan: VoiceInkAIEnhancementProviderSelectionPlan) {
        VoiceInkAIEnhancementProviderPreference.applyProviderSelectionPlan(plan, to: userDefaults)
        applyCredentialStateForSelectedProvider()

        if plan.shouldRefreshOllamaRuntimeModels {
            Task {
                await ollamaService.checkConnection()
                await ollamaService.refreshModels()
            }
        }

        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func applyCredentialStateForSelectedProvider() {
        let plan = VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(
            provider: selectedProvider
        )
        let savedKey = plan.providerKeyStorageNameToLoad.flatMap {
            APIKeyManager.shared.getAPIKey(forProvider: $0)
        }
        let credentialState = plan.credentialState(
            savedAPIKey: savedKey,
            isLocalCLIConfigured: localCLIService.isConfigured
        )

        apiKey = credentialState.apiKey
        isAPIKeyValid = credentialState.isAPIKeyValid
    }

    func selectModel(_ model: String) {
        guard let plan = VoiceInkAIEnhancementModelSelectionPlan.selecting(
            model,
            provider: selectedProvider,
            selectedModels: selectedModels
        ) else {
            return
        }

        applyTextEnhancementModelSelectionPlan(plan)
    }

    private func applyTextEnhancementModelSelectionPlan(_ plan: VoiceInkAIEnhancementModelSelectionPlan) {
        selectedModels = plan.selectedModels
        VoiceInkAIEnhancementProviderPreference.applyModelSelectionPlan(plan, to: userDefaults)

        if let ollamaModelToApply = plan.ollamaModelToApply {
            updateSelectedOllamaModel(ollamaModelToApply)
        }

        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void) {
        let draft = apiKeyDraft(for: key)
        guard let resolvedKey = resolvedKeyToVerify(
            from: draft.verificationRequestPlan(),
            completion: completion
        ) else {
            return
        }

        verifyResolvedAPIKey(resolvedKey) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let plan = draft.verificationApplicationPlan(
                    for: result,
                    resolvedRuntimeKey: resolvedKey
                )

                if let runtimeAPIKey = APIKeyManager.shared.applyAIEnhancementVerificationPlan(
                    plan
                ) {
                    self.apiKey = runtimeAPIKey
                    self.isAPIKeyValid = plan.isValid
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                } else {
                    self.isAPIKeyValid = plan.isValid
                }
                completion(VoiceInkAPIKeyVerificationResult(
                    isValid: plan.isValid,
                    errorMessage: plan.errorMessage
                ))
            }
        }
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void) {
        let draft = apiKeyDraft(for: key)
        guard let resolvedKey = resolvedKeyToVerify(
            from: draft.verificationRequestPlan(),
            completion: completion
        ) else {
            return
        }

        verifyResolvedAPIKey(resolvedKey, completion: completion)
    }

    private func apiKeyDraft(for key: String) -> VoiceInkAIEnhancementAPIKeyDraft {
        VoiceInkAIEnhancementAPIKeyDraft(
            provider: selectedProvider,
            enteredKey: key
        )
    }

    private func resolvedKeyToVerify(
        from plan: VoiceInkAIEnhancementAPIKeyVerificationRequestPlan,
        completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void
    ) -> String? {
        if let immediateResult = plan.immediateResult {
            completion(immediateResult)
            return nil
        }

        return plan.resolvedKeyToVerify
    }

    private func verifyResolvedAPIKey(
        _ resolvedKey: String,
        completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void
    ) {
        Task {
            let result: VoiceInkAPIKeyVerificationResult
            let dispatchPlan = VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: selectedProvider,
                currentModel: currentModel,
                requestURL: selectedProvider.textEnhancementRequestURL()
            )

            switch dispatchPlan.action {
            case .immediate(let immediateResult):
                result = immediateResult
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
            case .openAICompatibleModels(let requestURL, let model):
                result = apiKeyVerificationResult(
                    from: await OpenAILLMClient.verifyAPIKey(
                        baseURL: requestURL,
                        apiKey: resolvedKey,
                        model: model
                    )
                )
            case .openRouterModels(let model):
                result = apiKeyVerificationResult(
                    from: await OpenRouterClient.verifyAPIKey(
                        resolvedKey,
                        model: model
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
        guard let plan = VoiceInkAIEnhancementAPIKeyClearPlan.clearing(
            provider: selectedProvider
        ) else {
            return
        }

        applyTextEnhancementAPIKeyClearPlan(plan)
    }

    private func applyTextEnhancementAPIKeyClearPlan(_ plan: VoiceInkAIEnhancementAPIKeyClearPlan) {
        apiKey = plan.credentialStateAfterClear.apiKey
        isAPIKeyValid = plan.credentialStateAfterClear.isAPIKeyValid
        APIKeyManager.shared.deleteAPIKey(forProvider: plan.providerKeyStorageNameToDelete)
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
    
    func enhanceWithOllama(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
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
                let plan = VoiceInkAIEnhancementModelRefreshPlan.refreshed(
                    provider: self.selectedProvider,
                    currentModel: self.currentModel,
                    refreshedModels: models,
                    defaultModel: self.selectedProvider.defaultTextEnhancementModel()
                )
                self.applyOpenRouterModelRefreshPlan(plan)
            }
        } catch {
            await MainActor.run {
                self.applyOpenRouterModelRefreshPlan(.failed)
            }
        }
    }

    private func applyOpenRouterModelRefreshPlan(_ plan: VoiceInkAIEnhancementModelRefreshPlan) {
        openRouterModels = plan.refreshedModelNames
        if let refreshedModel = VoiceInkDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
            plan,
            to: userDefaults
        ) {
            selectedModels[.openRouter] = refreshedModel
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
        objectWillChange.send()
    }
}
