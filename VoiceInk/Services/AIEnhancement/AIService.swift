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
        self.selectedProvider = VoiceInkAIEnhancementProviderPreference.selectedProvider(from: userDefaults)

        applyCredentialStateForSelectedProvider()

        selectedModels = VoiceInkAIEnhancementProviderPreference.selectedModels(from: userDefaults)
        openRouterModels = VoiceInkDynamicAIProviderPreference.openRouterModels(from: userDefaults)
    }

    private func applyTextEnhancementProviderSelectionPlan(_ plan: VoiceInkAIEnhancementProviderSelectionPlan) {
        plan.applyRuntimeState(
            applyPersistence: { [self] plan in
                VoiceInkAIEnhancementProviderPreference.applyProviderSelectionPlan(plan, to: userDefaults)
            },
            applyCredentialState: { [self] in
                applyCredentialStateForSelectedProvider()
            },
            refreshOllamaRuntimeModels: { [self] in
                Task {
                    await ollamaService.checkConnection()
                    await ollamaService.refreshModels()
                }
            },
            postSettingsChanged: {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }
        )
    }

    private func applyCredentialStateForSelectedProvider() {
        VoiceInkAIEnhancementCredentialStateResolutionPlan.resolving(
            provider: selectedProvider
        ).applyRuntimeState(
            loadSavedAPIKey: { APIKeyManager.shared.getAPIKey(forProvider: $0) },
            isLocalCLIConfigured: localCLIService.isConfigured,
            setCredentialState: { [self] credentialState in
                apiKey = credentialState.apiKey
                isAPIKeyValid = credentialState.isAPIKeyValid
            }
        )
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
        plan.applyRuntimeState(
            setSelectedModels: { [self] models in
                selectedModels = models
            },
            applyPersistence: { [self] plan in
                VoiceInkAIEnhancementProviderPreference.applyModelSelectionPlan(plan, to: userDefaults)
            },
            setOllamaRuntimeModel: { [self] ollamaRuntimeModel in
                updateSelectedOllamaModel(ollamaRuntimeModel)
            },
            sendObjectWillChange: { [self] in
                objectWillChange.send()
            },
            postSettingsChanged: {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }
        )
    }
    
    func saveAPIKey(_ key: String, completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void) {
        let draft = apiKeyDraft(for: key)
        draft.verificationRequestPlan().applyRuntimeState(
            completeImmediateResult: completion,
            verifyResolvedKey: { resolvedKey in
                verifyResolvedAPIKey(resolvedKey) { [weak self] result in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        let plan = draft.verificationApplicationPlan(
                            for: result,
                            resolvedRuntimeKey: resolvedKey
                        )

                        plan.applyRuntimeState(
                            saveKey: { APIKeyManager.shared.saveAPIKey($0, forProvider: $1) },
                            setAPIKey: { self.apiKey = $0 },
                            setAPIKeyValidity: { self.isAPIKeyValid = $0 },
                            postProviderKeyChanged: {
                                NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                            },
                            complete: completion
                        )
                    }
                }
            }
        )
    }
    
    func verifyAPIKey(_ key: String, completion: @escaping (VoiceInkAPIKeyVerificationResult) -> Void) {
        apiKeyDraft(for: key).verificationRequestPlan().applyRuntimeState(
            completeImmediateResult: completion,
            verifyResolvedKey: { resolvedKey in
                verifyResolvedAPIKey(resolvedKey, completion: completion)
            }
        )
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
            let dispatchPlan = VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: selectedProvider,
                currentModel: currentModel,
                requestURL: selectedProvider.textEnhancementRequestURL()
            )
            let result = await dispatchPlan.verifyResolvedAPIKey(
                resolvedKey,
                verifySharedProvider: { key, provider in
                    await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(key, for: provider)
                },
                verifyAnthropicMessages: { key in
                    VoiceInkAPIKeyVerificationResult(
                        legacyResult: await AnthropicLLMClient.verifyAPIKey(key)
                    )
                },
                verifyOpenAICompatibleModels: { requestURL, key, model in
                    VoiceInkAPIKeyVerificationResult(
                        legacyResult: await OpenAILLMClient.verifyAPIKey(
                            baseURL: requestURL,
                            apiKey: key,
                            model: model
                        )
                    )
                },
                verifyOpenRouterModels: { key, model in
                    VoiceInkAPIKeyVerificationResult(
                        legacyResult: await OpenRouterClient.verifyAPIKey(key, model: model)
                    )
                }
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
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
        plan.applyRuntimeState(
            deleteKey: { APIKeyManager.shared.deleteAPIKey(forProvider: $0) },
            setCredentialState: { [self] credentialState in
                apiKey = credentialState.apiKey
                isAPIKeyValid = credentialState.isAPIKeyValid
            },
            postProviderKeyChanged: {
                NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
            }
        )
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
        if selectedProvider == .localCLI {
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
        plan.applyOpenRouterRuntimeState(
            setOpenRouterModels: { [self] models in
                openRouterModels = models
            },
            applyPersistence: { [self] plan in
                VoiceInkDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
                    plan,
                    to: userDefaults
                )
            },
            setSelectedOpenRouterModel: { [self] model in
                selectedModels[.openRouter] = model
            },
            postSettingsChanged: {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            },
            sendObjectWillChange: { [self] in
                objectWillChange.send()
            }
        )
    }
}
