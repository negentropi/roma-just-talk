import Foundation
import LLMkit
import RomaCore

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = RomaDynamicAIProviderPreference.customProviderBaseURL() {
        didSet {
            RomaDynamicAIProviderPreference.saveCustomProviderBaseURL(customBaseURL, to: userDefaults)
        }
    }
    @Published var customModel: String = RomaDynamicAIProviderPreference.customProviderModel() {
        didSet {
            RomaDynamicAIProviderPreference.saveCustomProviderModel(customModel, to: userDefaults)
        }
    }
    @Published var selectedProvider: RomaAIEnhancementProviderKind {
        didSet {
            applyTextEnhancementProviderSelectionPlan(
                RomaAIEnhancementProviderSelectionPlan.selecting(selectedProvider)
            )
        }
    }
    
    @Published private var selectedModels: [RomaAIEnhancementProviderKind: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    
    @Published private var openRouterModels: [String] = []
    
    var connectedProviders: [RomaAIEnhancementProviderKind] {
        let providerKeyStorageNamesWithKeys = Set(
            RomaAIEnhancementProviderKind.textEnhancementProviderKeyStorageNamesToCheck.filter {
                APIKeyManager.shared.hasAPIKey(forProvider: $0)
            }
        )

        return RomaAIEnhancementProviderKind.connectedTextEnhancementProviders(
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

    var localCLITemplateSelection: RomaLocalCLITemplate {
        localCLIService.selectedTemplate
    }

    var localCLITimeoutSeconds: Double {
        localCLIService.timeoutSeconds
    }

    func availableModels(for provider: RomaAIEnhancementProviderKind) -> [String] {
        provider.textEnhancementAvailableModels(
            ollamaModels: ollamaService.availableModels.map { $0.name },
            openRouterModels: openRouterModels
        )
    }
    
    init() {
        self.selectedProvider = RomaAIEnhancementProviderPreference.selectedProvider(from: userDefaults)

        applyCredentialStateForSelectedProvider()

        selectedModels = RomaAIEnhancementProviderPreference.selectedModels(from: userDefaults)
        openRouterModels = RomaDynamicAIProviderPreference.openRouterModels(from: userDefaults)
    }

    private func applyTextEnhancementProviderSelectionPlan(_ plan: RomaAIEnhancementProviderSelectionPlan) {
        plan.applyRuntimeState(
            applyPersistence: { [self] plan in
                RomaAIEnhancementProviderPreference.applyProviderSelectionPlan(plan, to: userDefaults)
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
        RomaAIEnhancementCredentialStateResolutionPlan.resolving(
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
        guard let plan = RomaAIEnhancementModelSelectionPlan.selecting(
            model,
            provider: selectedProvider,
            selectedModels: selectedModels
        ) else {
            return
        }

        applyTextEnhancementModelSelectionPlan(plan)
    }

    private func applyTextEnhancementModelSelectionPlan(_ plan: RomaAIEnhancementModelSelectionPlan) {
        plan.applyRuntimeState(
            setSelectedModels: { [self] models in
                selectedModels = models
            },
            applyPersistence: { [self] plan in
                RomaAIEnhancementProviderPreference.applyModelSelectionPlan(plan, to: userDefaults)
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
    
    func saveAPIKey(_ key: String, completion: @escaping (RomaAPIKeyVerificationResult) -> Void) {
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
    
    func verifyAPIKey(_ key: String, completion: @escaping (RomaAPIKeyVerificationResult) -> Void) {
        apiKeyDraft(for: key).verificationRequestPlan().applyRuntimeState(
            completeImmediateResult: completion,
            verifyResolvedKey: { resolvedKey in
                verifyResolvedAPIKey(resolvedKey, completion: completion)
            }
        )
    }

    private func apiKeyDraft(for key: String) -> RomaAIEnhancementAPIKeyDraft {
        RomaAIEnhancementAPIKeyDraft(
            provider: selectedProvider,
            enteredKey: key
        )
    }

    private func verifyResolvedAPIKey(
        _ resolvedKey: String,
        completion: @escaping (RomaAPIKeyVerificationResult) -> Void
    ) {
        Task {
            let dispatchPlan = RomaAIEnhancementAPIKeyVerificationDispatchPlan.plan(
                provider: selectedProvider,
                currentModel: currentModel,
                requestURL: selectedProvider.textEnhancementRequestURL()
            )
            let result = await dispatchPlan.verifyResolvedAPIKey(
                resolvedKey,
                verifySharedProvider: { key, provider in
                    await RomaProviderAPIKeyVerifier().verifyAPIKeyDetailed(key, for: provider)
                },
                verifyAnthropicMessages: { key in
                    RomaAPIKeyVerificationResult(
                        legacyResult: await AnthropicLLMClient.verifyAPIKey(key)
                    )
                },
                verifyOpenAICompatibleModels: { requestURL, key, model in
                    RomaAPIKeyVerificationResult(
                        legacyResult: await OpenAILLMClient.verifyAPIKey(
                            baseURL: requestURL,
                            apiKey: key,
                            model: model
                        )
                    )
                },
                verifyOpenRouterModels: { key, model in
                    RomaAPIKeyVerificationResult(
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
        guard let plan = RomaAIEnhancementAPIKeyClearPlan.clearing(
            provider: selectedProvider
        ) else {
            return
        }

        applyTextEnhancementAPIKeyClearPlan(plan)
    }

    private func applyTextEnhancementAPIKeyClearPlan(_ plan: RomaAIEnhancementAPIKeyClearPlan) {
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

    func loadLocalCLITemplate(_ template: RomaLocalCLITemplate) {
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
                let plan = RomaAIEnhancementModelRefreshPlan.refreshed(
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

    private func applyOpenRouterModelRefreshPlan(_ plan: RomaAIEnhancementModelRefreshPlan) {
        plan.applyOpenRouterRuntimeState(
            setOpenRouterModels: { [self] models in
                openRouterModels = models
            },
            applyPersistence: { [self] plan in
                RomaDynamicAIProviderPreference.applyOpenRouterModelRefreshPlan(
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
