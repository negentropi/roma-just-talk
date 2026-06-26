import Foundation

public enum VoiceInkAIEnhancementProviderKeyChangeRequest {
    public static let notificationName = Notification.Name("aiProviderKeyChanged")
}

public enum VoiceInkAIEnhancementAPIKeyVerificationRoute: Sendable, Equatable {
    case sharedProvider(VoiceInkProviderKind)
    case anthropicMessages
    case openAICompatibleModels
    case openRouterModels
}

public enum VoiceInkAIEnhancementExecutionRoute: Sendable, Equatable {
    case ollama
    case localCLI
    case anthropicMessages
    case openAICompatibleChatCompletions
}

public struct VoiceInkAIEnhancementOpenAICompatibleRequestPlan {
    public let requestURL: URL
    public let requestParameters: VoiceInkAIChatRequestParameters
}

public struct VoiceInkAIEnhancementRequestExecutionPlan {
    private let route: VoiceInkAIEnhancementExecutionRoute
    private let modelName: String
    private let openAICompatibleRequest: VoiceInkAIEnhancementOpenAICompatibleRequestPlan?
    private let requestPreparationError: VoiceInkAIEnhancementError?

    public static func planning(
        provider: VoiceInkAIEnhancementProviderKind,
        modelName: String,
        defaults: UserDefaults = .standard
    ) -> VoiceInkAIEnhancementRequestExecutionPlan {
        let route = provider.textEnhancementExecutionRoute

        guard route == .openAICompatibleChatCompletions else {
            return VoiceInkAIEnhancementRequestExecutionPlan(
                route: route,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: nil
            )
        }

        guard let requestURL = provider.textEnhancementRequestURL(from: defaults) else {
            return VoiceInkAIEnhancementRequestExecutionPlan(
                route: route,
                modelName: modelName,
                openAICompatibleRequest: nil,
                requestPreparationError: .customError(provider.invalidTextEnhancementRequestURLMessage)
            )
        }

        return VoiceInkAIEnhancementRequestExecutionPlan(
            route: route,
            modelName: modelName,
            openAICompatibleRequest: VoiceInkAIEnhancementOpenAICompatibleRequestPlan(
                requestURL: requestURL,
                requestParameters: VoiceInkAIReasoningConfig.chatRequestParameters(
                    for: provider.aiModelProvider,
                    modelName: modelName
                )
            ),
            requestPreparationError: nil
        )
    }

    public func applyRuntimeState<Result>(
        ollama: (String) async throws -> Result,
        localCLI: (String) async throws -> Result,
        anthropicMessages: (String) async throws -> Result,
        openAICompatibleChatCompletions: (String, VoiceInkAIEnhancementOpenAICompatibleRequestPlan) async throws -> Result
    ) async throws -> Result {
        switch route {
        case .ollama:
            return try await ollama(modelName)
        case .localCLI:
            return try await localCLI(modelName)
        case .anthropicMessages:
            return try await anthropicMessages(modelName)
        case .openAICompatibleChatCompletions:
            return try await openAICompatibleChatCompletions(
                modelName,
                openAICompatibleRequestOrThrow()
            )
        }
    }

    private func openAICompatibleRequestOrThrow() throws -> VoiceInkAIEnhancementOpenAICompatibleRequestPlan {
        if let openAICompatibleRequest {
            return openAICompatibleRequest
        }

        if let requestPreparationError {
            throw requestPreparationError
        }

        preconditionFailure("OpenAI-compatible request plan is only available for OpenAI-compatible routes.")
    }
}

public enum VoiceInkAIEnhancementModelCatalogSource: Sendable, Equatable {
    case staticModels
    case ollamaRuntime
    case openRouterRemote
    case none
}

public enum VoiceInkAIEnhancementSettingsSurface: Sendable, Equatable {
    case apiKey
    case ollama
    case localCLI
    case custom
}

public struct VoiceInkAIEnhancementProviderSelectionPlan: Sendable, Equatable {
    public let selectedProviderToSave: VoiceInkAIEnhancementProviderKind
    public let shouldRefreshOllamaRuntimeModels: Bool

    public init(
        selectedProviderToSave: VoiceInkAIEnhancementProviderKind,
        shouldRefreshOllamaRuntimeModels: Bool
    ) {
        self.selectedProviderToSave = selectedProviderToSave
        self.shouldRefreshOllamaRuntimeModels = shouldRefreshOllamaRuntimeModels
    }

    public static func selecting(
        _ provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementProviderSelectionPlan {
        VoiceInkAIEnhancementProviderSelectionPlan(
            selectedProviderToSave: provider,
            shouldRefreshOllamaRuntimeModels: provider.textEnhancementModelCatalogSource == .ollamaRuntime
        )
    }
}

public extension VoiceInkAIEnhancementProviderSelectionPlan {
    func applyRuntimeState(
        applyPersistence: (VoiceInkAIEnhancementProviderSelectionPlan) -> Void,
        applyCredentialState: () -> Void,
        refreshOllamaRuntimeModels: () -> Void,
        postSettingsChanged: () -> Void
    ) {
        applyPersistence(self)
        applyCredentialState()
        if shouldRefreshOllamaRuntimeModels {
            refreshOllamaRuntimeModels()
        }
        postSettingsChanged()
    }
}

public struct VoiceInkAIEnhancementModelRefreshPlan: Sendable, Equatable {
    public let refreshedModelNames: [String]
    public let selectedModelToSave: String?

    public init(refreshedModelNames: [String], selectedModelToSave: String?) {
        self.refreshedModelNames = refreshedModelNames
        self.selectedModelToSave = selectedModelToSave
    }

    public static func refreshed(
        provider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        refreshedModels: [String],
        defaultModel: String
    ) -> VoiceInkAIEnhancementModelRefreshPlan {
        VoiceInkAIEnhancementModelRefreshPlan(
            refreshedModelNames: refreshedModels,
            selectedModelToSave: provider.textEnhancementModelToSelectAfterRefresh(
                currentModel: currentModel,
                refreshedModels: refreshedModels,
                defaultModel: defaultModel
            )
        )
    }

    public static let failed = VoiceInkAIEnhancementModelRefreshPlan(
        refreshedModelNames: [],
        selectedModelToSave: nil
    )
}

public extension VoiceInkAIEnhancementModelRefreshPlan {
    func applyOpenRouterRuntimeState(
        setOpenRouterModels: ([String]) -> Void,
        applyPersistence: (VoiceInkAIEnhancementModelRefreshPlan) -> String?,
        setSelectedOpenRouterModel: (String) -> Void,
        postSettingsChanged: () -> Void,
        sendObjectWillChange: () -> Void
    ) {
        setOpenRouterModels(refreshedModelNames)
        if let refreshedModel = applyPersistence(self) {
            setSelectedOpenRouterModel(refreshedModel)
            postSettingsChanged()
        }
        sendObjectWillChange()
    }
}

public struct VoiceInkAIEnhancementModelSelectionPlan: Sendable, Equatable {
    public let selectedModels: [VoiceInkAIEnhancementProviderKind: String]
    public let provider: VoiceInkAIEnhancementProviderKind
    public let selectedModelToSave: String
    public let ollamaModelToApply: String?

    public init(
        selectedModels: [VoiceInkAIEnhancementProviderKind: String],
        provider: VoiceInkAIEnhancementProviderKind,
        selectedModelToSave: String,
        ollamaModelToApply: String?
    ) {
        self.selectedModels = selectedModels
        self.provider = provider
        self.selectedModelToSave = selectedModelToSave
        self.ollamaModelToApply = ollamaModelToApply
    }

    public static func selecting(
        _ model: String,
        provider: VoiceInkAIEnhancementProviderKind,
        selectedModels: [VoiceInkAIEnhancementProviderKind: String]
    ) -> VoiceInkAIEnhancementModelSelectionPlan? {
        guard !model.isEmpty else { return nil }

        var updatedSelectedModels = selectedModels
        updatedSelectedModels[provider] = model

        return VoiceInkAIEnhancementModelSelectionPlan(
            selectedModels: updatedSelectedModels,
            provider: provider,
            selectedModelToSave: model,
            ollamaModelToApply: provider.textEnhancementModelCatalogSource == .ollamaRuntime ? model : nil
        )
    }
}

public extension VoiceInkAIEnhancementModelSelectionPlan {
    func applyRuntimeState(
        setSelectedModels: ([VoiceInkAIEnhancementProviderKind: String]) -> Void,
        applyPersistence: (VoiceInkAIEnhancementModelSelectionPlan) -> Void,
        setOllamaRuntimeModel: (String) -> Void,
        sendObjectWillChange: () -> Void,
        postSettingsChanged: () -> Void
    ) {
        setSelectedModels(selectedModels)
        applyPersistence(self)
        if let ollamaModelToApply {
            setOllamaRuntimeModel(ollamaModelToApply)
        }
        sendObjectWillChange()
        postSettingsChanged()
    }
}

public enum VoiceInkAIEnhancementConnectionStatusTone: Sendable, Equatable {
    case connected
    case disconnected
}

public enum VoiceInkAIEnhancementConnectionStatusPresentation: Sendable, Equatable {
    case checking
    case status(text: String, tone: VoiceInkAIEnhancementConnectionStatusTone)
}

public struct VoiceInkAIEnhancementAPIKeyControlPresentation: Sendable, Equatable {
    public let isVerificationProgressVisible: Bool
    public let isDefaultVerifyAndSaveButtonDisabled: Bool
    public let isCustomVerifyAndSaveButtonDisabled: Bool

    public init(
        isVerificationProgressVisible: Bool,
        isDefaultVerifyAndSaveButtonDisabled: Bool,
        isCustomVerifyAndSaveButtonDisabled: Bool
    ) {
        self.isVerificationProgressVisible = isVerificationProgressVisible
        self.isDefaultVerifyAndSaveButtonDisabled = isDefaultVerifyAndSaveButtonDisabled
        self.isCustomVerifyAndSaveButtonDisabled = isCustomVerifyAndSaveButtonDisabled
    }
}

public struct VoiceInkAIEnhancementProviderSettingsPresentation: Sendable, Equatable {
    public let sectionTitle: String
    public let providerPickerTitle: String
    public let modelPickerTitle: String
    public let noModelsLoadedText: String
    public let refreshButtonTitle: String
    public let defaultAPIKeyRemoveButtonTitle: String
    public let getAPIKeyButtonTitle: String
    public let errorAlertTitle: String
    public let errorAlertDismissButtonTitle: String
    public let connectedText: String
    public let disconnectedText: String
    public let apiKeyFieldTitle: String
    public let verifyAndSaveButtonTitle: String
    public let ollamaBaseURLFieldTitle: String
    public let ollamaSaveButtonTitle: String
    public let ollamaEditButtonTitle: String
    public let ollamaResetButtonHelp: String
    public let ollamaConnectionFailureMessage: String
    public let customProviderBaseURLFieldTitle: String
    public let customProviderBaseURLPlaceholder: String
    public let customProviderModelFieldTitle: String
    public let customProviderModelPlaceholder: String
    public let customProviderAPIKeySetText: String
    public let customProviderRemoveKeyButtonTitle: String

    public static let macOS = VoiceInkAIEnhancementProviderSettingsPresentation(
        sectionTitle: "AI Provider Integration",
        providerPickerTitle: "Provider",
        modelPickerTitle: "Model",
        noModelsLoadedText: "No models loaded",
        refreshButtonTitle: "Refresh",
        defaultAPIKeyRemoveButtonTitle: "Remove",
        getAPIKeyButtonTitle: "Get API Key",
        errorAlertTitle: "Error",
        errorAlertDismissButtonTitle: "OK",
        connectedText: "Connected",
        disconnectedText: "Disconnected",
        apiKeyFieldTitle: "API Key",
        verifyAndSaveButtonTitle: "Verify and Save",
        ollamaBaseURLFieldTitle: "Base URL",
        ollamaSaveButtonTitle: "Save",
        ollamaEditButtonTitle: "Edit",
        ollamaResetButtonHelp: "Reset to default",
        ollamaConnectionFailureMessage: "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct.",
        customProviderBaseURLFieldTitle: "API Endpoint URL",
        customProviderBaseURLPlaceholder: "e.g. https://api.openai.com/v1/chat/completions",
        customProviderModelFieldTitle: "Model Name",
        customProviderModelPlaceholder: "e.g. gemini-3.1-pro-preview, gpt-5.5",
        customProviderAPIKeySetText: "API Key Set",
        customProviderRemoveKeyButtonTitle: "Remove Key"
    )

    public func connectionStatus(
        surface: VoiceInkAIEnhancementSettingsSurface,
        isAPIKeyValid: Bool,
        isCheckingOllama: Bool,
        hasOllamaModels: Bool
    ) -> VoiceInkAIEnhancementConnectionStatusPresentation? {
        switch surface {
        case .ollama:
            if isCheckingOllama {
                return .checking
            }

            return hasOllamaModels
                ? .status(text: connectedText, tone: .connected)
                : .status(text: disconnectedText, tone: .disconnected)
        case .apiKey, .localCLI, .custom:
            return isAPIKeyValid
                ? .status(text: connectedText, tone: .connected)
                : nil
        }
    }

    public func ollamaServerText(baseURL: String) -> String {
        "Server: \(baseURL)"
    }

    public func canSubmitCustomProvider(
        baseURL: String,
        modelName: String,
        hasDraftAPIKey: Bool
    ) -> Bool {
        !baseURL.isEmpty && !modelName.isEmpty && hasDraftAPIKey
    }

    public func apiKeyControlPresentation(
        formState: VoiceInkAIEnhancementAPIKeyFormState,
        provider: VoiceInkAIEnhancementProviderKind,
        customProviderBaseURL: String,
        customProviderModelName: String
    ) -> VoiceInkAIEnhancementAPIKeyControlPresentation {
        let draft = formState.draft(for: provider)
        return VoiceInkAIEnhancementAPIKeyControlPresentation(
            isVerificationProgressVisible: formState.isVerifying,
            isDefaultVerifyAndSaveButtonDisabled: !draft.hasEnteredKey,
            isCustomVerifyAndSaveButtonDisabled: !canSubmitCustomProvider(
                baseURL: customProviderBaseURL,
                modelName: customProviderModelName,
                hasDraftAPIKey: draft.hasEnteredKey
            )
        )
    }
}

public struct VoiceInkAIEnhancementAPIKeyDraft: Equatable, Sendable {
    private let provider: VoiceInkAIEnhancementProviderKind
    private let providerKeyDraft: VoiceInkProviderAPIKeyDraft

    public init(
        provider: VoiceInkAIEnhancementProviderKind,
        enteredKey: String?,
        storedRuntimeKey: String? = nil
    ) {
        self.provider = provider
        self.providerKeyDraft = VoiceInkProviderAPIKeyDraft(
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public var hasEnteredKey: Bool {
        providerKeyDraft.hasEnteredKey
    }

    public var canVerify: Bool {
        provider.requiresUserAPIKey && providerKeyDraft.canVerify
    }

    public var keyToSaveAfterSuccessfulVerification: String? {
        guard provider.requiresUserAPIKey else {
            return nil
        }
        return providerKeyDraft.keyToSaveAfterSuccessfulVerification
    }

    public func resolvedVerificationCandidate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard provider.requiresUserAPIKey,
              let candidate = providerKeyDraft.verificationCandidate else {
            return nil
        }
        return VoiceInkAPIKeyReference.resolvedValue(candidate, environment: environment)
    }

    public func verificationRequestPlan(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VoiceInkAIEnhancementAPIKeyVerificationRequestPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(isValid: true, errorMessage: nil)
            )
        }

        guard let resolvedKey = resolvedVerificationCandidate(environment: environment) else {
            return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
                resolvedKeyToVerify: nil,
                immediateResult: VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: VoiceInkAIEnhancementProviderKind.missingVerificationCandidateMessage
                )
            )
        }

        return VoiceInkAIEnhancementAPIKeyVerificationRequestPlan(
            resolvedKeyToVerify: resolvedKey,
            immediateResult: nil
        )
    }

    public func verificationApplicationPlan(
        for result: VoiceInkAPIKeyVerificationResult,
        resolvedRuntimeKey: String
    ) -> VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
        guard provider.requiresUserAPIKey else {
            return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: true,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: nil
            )
        }

        guard result.isValid else {
            return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
                isValid: false,
                runtimeAPIKey: nil,
                keyToSave: nil,
                providerKeyStorageNameToSave: nil,
                errorMessage: result.errorMessage
            )
        }

        return VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan(
            isValid: true,
            runtimeAPIKey: resolvedRuntimeKey,
            keyToSave: keyToSaveAfterSuccessfulVerification,
            providerKeyStorageNameToSave: provider.userAPIKeyStorageName,
            errorMessage: nil
        )
    }
}

public struct VoiceInkAIEnhancementAPIKeyVerificationRequestPlan: Equatable, Sendable {
    private let resolvedKeyToVerify: String?
    private let immediateResult: VoiceInkAPIKeyVerificationResult?

    public init(
        resolvedKeyToVerify: String?,
        immediateResult: VoiceInkAPIKeyVerificationResult?
    ) {
        self.resolvedKeyToVerify = resolvedKeyToVerify
        self.immediateResult = immediateResult
    }

    public func applyRuntimeState(
        completeImmediateResult: (VoiceInkAPIKeyVerificationResult) -> Void,
        verifyResolvedKey: (String) -> Void
    ) {
        if let immediateResult {
            completeImmediateResult(immediateResult)
            return
        }

        if let resolvedKeyToVerify {
            verifyResolvedKey(resolvedKeyToVerify)
        }
    }
}

public struct VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan: Equatable, Sendable {
    private let isValid: Bool
    private let runtimeAPIKey: String?
    private let keyToSave: String?
    private let providerKeyStorageNameToSave: String?
    private let errorMessage: String?

    init(
        isValid: Bool,
        runtimeAPIKey: String?,
        keyToSave: String?,
        providerKeyStorageNameToSave: String?,
        errorMessage: String?
    ) {
        self.isValid = isValid
        self.runtimeAPIKey = runtimeAPIKey
        self.keyToSave = keyToSave
        self.providerKeyStorageNameToSave = providerKeyStorageNameToSave
        self.errorMessage = errorMessage
    }
}

struct VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan: Equatable, Sendable {
    let runtimeAPIKey: String
    let keyToSave: String?
    let providerKeyStorageNameToSave: String?

    init(
        runtimeAPIKey: String,
        keyToSave: String?,
        providerKeyStorageNameToSave: String?
    ) {
        self.runtimeAPIKey = runtimeAPIKey
        self.keyToSave = keyToSave
        self.providerKeyStorageNameToSave = providerKeyStorageNameToSave
    }
}

struct VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan: Equatable, Sendable {
    private let apiKeyToApply: String?
    private let isAPIKeyValid: Bool
    private let shouldPostProviderKeyChanged: Bool
    private let completionResult: VoiceInkAPIKeyVerificationResult

    init(
        apiKeyToApply: String?,
        isAPIKeyValid: Bool,
        shouldPostProviderKeyChanged: Bool,
        completionResult: VoiceInkAPIKeyVerificationResult
    ) {
        self.apiKeyToApply = apiKeyToApply
        self.isAPIKeyValid = isAPIKeyValid
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
        self.completionResult = completionResult
    }
}

extension VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
    var successPersistencePlan: VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan? {
        guard let runtimeAPIKey else { return nil }
        return VoiceInkAIEnhancementAPIKeyVerificationPersistencePlan(
            runtimeAPIKey: runtimeAPIKey,
            keyToSave: keyToSave,
            providerKeyStorageNameToSave: providerKeyStorageNameToSave
        )
    }

    var serviceStateApplicationPlan: VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan {
        let persistencePlan = successPersistencePlan
        return VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan(
            apiKeyToApply: persistencePlan?.runtimeAPIKey,
            isAPIKeyValid: isValid,
            shouldPostProviderKeyChanged: persistencePlan != nil,
            completionResult: VoiceInkAPIKeyVerificationResult(
                isValid: isValid,
                errorMessage: errorMessage
            )
        )
    }

    func applySuccessPersistence(
        saveKey: (String, String) -> Void
    ) {
        guard let persistencePlan = successPersistencePlan,
              let keyToSave = persistencePlan.keyToSave,
              let providerKeyStorageNameToSave = persistencePlan.providerKeyStorageNameToSave else {
            return
        }

        saveKey(keyToSave, providerKeyStorageNameToSave)
    }
}

public extension VoiceInkAIEnhancementAPIKeyVerificationApplicationPlan {
    func applyRuntimeState(
        saveKey: (String, String) -> Void,
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (VoiceInkAPIKeyVerificationResult) -> Void
    ) {
        applySuccessPersistence(saveKey: saveKey)
        serviceStateApplicationPlan.apply(
            setAPIKey: setAPIKey,
            setAPIKeyValidity: setAPIKeyValidity,
            postProviderKeyChanged: postProviderKeyChanged,
            complete: complete
        )
    }
}

extension VoiceInkAIEnhancementAPIKeyVerificationServiceStatePlan {
    func apply(
        setAPIKey: (String) -> Void,
        setAPIKeyValidity: (Bool) -> Void,
        postProviderKeyChanged: () -> Void,
        complete: (VoiceInkAPIKeyVerificationResult) -> Void
    ) {
        if let apiKeyToApply {
            setAPIKey(apiKeyToApply)
        }
        setAPIKeyValidity(isAPIKeyValid)
        if shouldPostProviderKeyChanged {
            postProviderKeyChanged()
        }
        complete(completionResult)
    }
}

fileprivate enum VoiceInkAIEnhancementAPIKeyVerificationDispatch: Equatable, Sendable {
    case immediate(VoiceInkAPIKeyVerificationResult)
    case sharedProvider(VoiceInkProviderKind)
    case anthropicMessages
    case openAICompatibleModels(requestURL: URL, model: String)
    case openRouterModels(model: String)
}

public struct VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan: Equatable, Sendable {
    private let provider: VoiceInkAIEnhancementProviderKind
    private let action: VoiceInkAIEnhancementAPIKeyVerificationDispatch

    private init(
        provider: VoiceInkAIEnhancementProviderKind,
        action: VoiceInkAIEnhancementAPIKeyVerificationDispatch
    ) {
        self.provider = provider
        self.action = action
    }

    public static func plan(
        provider: VoiceInkAIEnhancementProviderKind,
        currentModel: String,
        requestURL: URL?
    ) -> VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan {
        guard let route = provider.apiKeyVerificationRoute else {
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .immediate(VoiceInkAPIKeyVerificationResult(
                    isValid: false,
                    errorMessage: provider.unsupportedAPIKeyVerificationMessage
                ))
            )
        }

        switch route {
        case .sharedProvider(let sharedProvider):
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .sharedProvider(sharedProvider)
            )
        case .anthropicMessages:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .anthropicMessages
            )
        case .openAICompatibleModels:
            guard let requestURL else {
                return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                    provider: provider,
                    action: .immediate(VoiceInkAPIKeyVerificationResult(
                        isValid: false,
                        errorMessage: VoiceInkAIEnhancementProviderKind.invalidOrMissingBaseURLConfigurationMessage
                    ))
                )
            }

            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openAICompatibleModels(requestURL: requestURL, model: currentModel)
            )
        case .openRouterModels:
            return VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan(
                provider: provider,
                action: .openRouterModels(model: currentModel)
            )
        }
    }
}

public extension VoiceInkAIEnhancementAPIKeyVerificationDispatchPlan {
    func verifyResolvedAPIKey(
        _ resolvedKey: String,
        verifySharedProvider: (String, VoiceInkProviderKind) async -> VoiceInkAPIKeyVerificationResult,
        verifyAnthropicMessages: (String) async -> VoiceInkAPIKeyVerificationResult,
        verifyOpenAICompatibleModels: (URL, String, String) async -> VoiceInkAPIKeyVerificationResult,
        verifyOpenRouterModels: (String, String) async -> VoiceInkAPIKeyVerificationResult
    ) async -> VoiceInkAPIKeyVerificationResult {
        switch action {
        case .immediate(let immediateResult):
            return immediateResult
        case .sharedProvider(let provider):
            return await verifySharedProvider(resolvedKey, provider)
        case .anthropicMessages:
            return await verifyAnthropicMessages(resolvedKey)
        case .openAICompatibleModels(let requestURL, let model):
            return await verifyOpenAICompatibleModels(requestURL, resolvedKey, model)
        case .openRouterModels(let model):
            return await verifyOpenRouterModels(resolvedKey, model)
        }
    }
}

public struct VoiceInkAIEnhancementAPIKeyClearPlan: Equatable, Sendable {
    public let provider: VoiceInkAIEnhancementProviderKind
    public let providerKeyStorageNameToDelete: String
    public let credentialStateAfterClear: VoiceInkAIEnhancementCredentialState

    public init(
        provider: VoiceInkAIEnhancementProviderKind,
        providerKeyStorageNameToDelete: String,
        credentialStateAfterClear: VoiceInkAIEnhancementCredentialState
    ) {
        self.provider = provider
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
        self.credentialStateAfterClear = credentialStateAfterClear
    }

    public static func clearing(
        provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementAPIKeyClearPlan? {
        guard let providerKeyStorageNameToDelete = provider.userAPIKeyStorageName else { return nil }

        return VoiceInkAIEnhancementAPIKeyClearPlan(
            provider: provider,
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete,
            credentialStateAfterClear: VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: false
            )
        )
    }
}

public struct VoiceInkAIEnhancementAPIKeyClearPersistencePlan: Equatable, Sendable {
    public let providerKeyStorageNameToDelete: String

    public init(providerKeyStorageNameToDelete: String) {
        self.providerKeyStorageNameToDelete = providerKeyStorageNameToDelete
    }
}

public struct VoiceInkAIEnhancementAPIKeyClearServiceStatePlan: Equatable, Sendable {
    public let credentialStateAfterClear: VoiceInkAIEnhancementCredentialState
    public let shouldPostProviderKeyChanged: Bool

    public init(
        credentialStateAfterClear: VoiceInkAIEnhancementCredentialState,
        shouldPostProviderKeyChanged: Bool
    ) {
        self.credentialStateAfterClear = credentialStateAfterClear
        self.shouldPostProviderKeyChanged = shouldPostProviderKeyChanged
    }
}

public extension VoiceInkAIEnhancementAPIKeyClearPlan {
    var persistencePlan: VoiceInkAIEnhancementAPIKeyClearPersistencePlan {
        VoiceInkAIEnhancementAPIKeyClearPersistencePlan(
            providerKeyStorageNameToDelete: providerKeyStorageNameToDelete
        )
    }

    var serviceStateApplicationPlan: VoiceInkAIEnhancementAPIKeyClearServiceStatePlan {
        VoiceInkAIEnhancementAPIKeyClearServiceStatePlan(
            credentialStateAfterClear: credentialStateAfterClear,
            shouldPostProviderKeyChanged: true
        )
    }

    func applyClearPersistence(
        deleteKey: (String) -> Void
    ) {
        deleteKey(persistencePlan.providerKeyStorageNameToDelete)
    }
}

public extension VoiceInkAIEnhancementAPIKeyClearServiceStatePlan {
    func apply(
        setCredentialState: (VoiceInkAIEnhancementCredentialState) -> Void,
        postProviderKeyChanged: () -> Void
    ) {
        setCredentialState(credentialStateAfterClear)
        if shouldPostProviderKeyChanged {
            postProviderKeyChanged()
        }
    }
}

public struct VoiceInkAIEnhancementAPIKeyFormState: Equatable, Sendable {
    public var enteredKey: String
    public var verificationProgress: VoiceInkProviderAPIKeyVerificationProgress

    public init(
        enteredKey: String = "",
        verificationProgress: VoiceInkProviderAPIKeyVerificationProgress = .idle
    ) {
        self.enteredKey = enteredKey
        self.verificationProgress = verificationProgress
    }

    public var isVerifying: Bool {
        verificationProgress.isVerifying
    }

    public func draft(
        for provider: VoiceInkAIEnhancementProviderKind,
        storedRuntimeKey: String? = nil
    ) -> VoiceInkAIEnhancementAPIKeyDraft {
        VoiceInkAIEnhancementAPIKeyDraft(
            provider: provider,
            enteredKey: enteredKey,
            storedRuntimeKey: storedRuntimeKey
        )
    }

    public func verifying() -> Self {
        Self(
            enteredKey: enteredKey,
            verificationProgress: .verifying
        )
    }

    public func completedVerification() -> Self {
        Self()
    }

    public func verificationFailureAlertMessage(for result: VoiceInkAPIKeyVerificationResult) -> String? {
        VoiceInkProviderAPIKeyVerificationProgress.failure(message: result.errorMessage)
            .macOSInlineFeedback?
            .text
    }
}

public struct VoiceInkAIEnhancementCredentialState: Equatable, Sendable {
    public let apiKey: String
    public let isAPIKeyValid: Bool

    public init(apiKey: String, isAPIKeyValid: Bool) {
        self.apiKey = apiKey
        self.isAPIKeyValid = isAPIKeyValid
    }
}

public struct VoiceInkAIEnhancementCredentialStateResolutionPlan: Equatable, Sendable {
    public let provider: VoiceInkAIEnhancementProviderKind
    private let providerKeyStorageNameToLoad: String?

    public init(
        provider: VoiceInkAIEnhancementProviderKind,
        providerKeyStorageNameToLoad: String?
    ) {
        self.provider = provider
        self.providerKeyStorageNameToLoad = providerKeyStorageNameToLoad
    }

    public static func resolving(
        provider: VoiceInkAIEnhancementProviderKind
    ) -> VoiceInkAIEnhancementCredentialStateResolutionPlan {
        VoiceInkAIEnhancementCredentialStateResolutionPlan(
            provider: provider,
            providerKeyStorageNameToLoad: provider.userAPIKeyStorageName
        )
    }

    public func credentialState(
        savedAPIKey: String?,
        isLocalCLIConfigured: Bool
    ) -> VoiceInkAIEnhancementCredentialState {
        provider.textEnhancementCredentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        )
    }

    public func applyRuntimeState(
        loadSavedAPIKey: (String) -> String?,
        isLocalCLIConfigured: Bool,
        setCredentialState: (VoiceInkAIEnhancementCredentialState) -> Void
    ) {
        let savedAPIKey = providerKeyStorageNameToLoad.flatMap(loadSavedAPIKey)
        setCredentialState(credentialState(
            savedAPIKey: savedAPIKey,
            isLocalCLIConfigured: isLocalCLIConfigured
        ))
    }
}

public enum VoiceInkAIEnhancementProviderKind: String, CaseIterable, Sendable {
    public static let missingVerificationCandidateMessage = "Environment variable is missing or empty"
    public static let invalidOrMissingBaseURLConfigurationMessage = "Invalid or missing base URL configuration"
    public static let defaultOllamaTextEnhancementModel = "mistral"
    public static let legacyOllamaServiceSelectedModelFallback = "llama2"
    public static let ollamaTextEnhancementRequestTemperature: Double = 0.3
    public static let localCLITextEnhancementModel = "local-cli"

    case cerebras = "Cerebras"
    case groq = "Groq"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case ollama = "Ollama"
    case localCLI = "Local CLI"
    case custom = "Custom"

    public init?(storedValue: String) {
        guard let provider = Self.provider(forStoredValue: storedValue) else {
            return nil
        }
        self = provider
    }

    private static func provider(forStoredValue value: String) -> Self? {
        allCases.first { provider in
            provider.rawValue == value || provider.legacyStoredValues.contains(value)
        }
    }

    private var legacyStoredValues: [String] {
        switch self {
        case .groq:
            return ["GROQ"]
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .localCLI, .mistral, .ollama, .openAI, .openRouter, .soniox, .speechmatics:
            return []
        }
    }

    public var aiModelProvider: VoiceInkAIModelProvider? {
        switch self {
        case .anthropic:
            return .anthropic
        case .assemblyAI:
            return .assemblyAI
        case .cerebras:
            return .cerebras
        case .deepgram:
            return .deepgram
        case .elevenLabs:
            return .elevenLabs
        case .groq:
            return .groq
        case .gemini:
            return .gemini
        case .mistral:
            return .mistral
        case .openAI:
            return .openAI
        case .openRouter:
            return .openRouter
        case .soniox:
            return .soniox
        case .speechmatics:
            return .speechmatics
        case .ollama, .localCLI, .custom:
            return nil
        }
    }

    public var requiresUserAPIKey: Bool {
        switch self {
        case .ollama, .localCLI:
            return false
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .groq, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            return true
        }
    }

    public var userAPIKeyStorageName: String? {
        requiresUserAPIKey ? rawValue : nil
    }

    public func textEnhancementCredentialState(
        savedAPIKey: String?,
        isLocalCLIConfigured: Bool
    ) -> VoiceInkAIEnhancementCredentialState {
        guard requiresUserAPIKey else {
            return VoiceInkAIEnhancementCredentialState(
                apiKey: "",
                isAPIKeyValid: self == .localCLI ? isLocalCLIConfigured : true
            )
        }

        guard let savedAPIKey else {
            return VoiceInkAIEnhancementCredentialState(apiKey: "", isAPIKeyValid: false)
        }

        return VoiceInkAIEnhancementCredentialState(apiKey: savedAPIKey, isAPIKeyValid: true)
    }

    public var isSelectableForTextEnhancement: Bool {
        switch self {
        case .assemblyAI, .deepgram, .elevenLabs, .soniox, .speechmatics:
            return false
        case .anthropic, .cerebras, .custom, .gemini, .groq, .localCLI, .mistral, .ollama, .openAI, .openRouter:
            return true
        }
    }

    public static var selectableTextEnhancementProviders: [Self] {
        allCases.filter(\.isSelectableForTextEnhancement)
    }

    public static var textEnhancementProviderKeyStorageNamesToCheck: [String] {
        selectableTextEnhancementProviders.compactMap(\.userAPIKeyStorageName)
    }

    public static func connectedTextEnhancementProviders(
        providerKeyStorageNamesWithKeys: Set<String>,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> [Self] {
        selectableTextEnhancementProviders.filter { provider in
            provider.isConnectedForTextEnhancement(
                providerKeyStorageNamesWithKeys: providerKeyStorageNamesWithKeys,
                isOllamaConnected: isOllamaConnected,
                isLocalCLIConfigured: isLocalCLIConfigured
            )
        }
    }

    public func isConnectedForTextEnhancement(
        providerKeyStorageNamesWithKeys: Set<String>,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> Bool {
        switch self {
        case .ollama:
            return isOllamaConnected
        case .localCLI:
            return isLocalCLIConfigured
        case .anthropic, .cerebras, .custom, .gemini, .groq, .mistral, .openAI, .openRouter:
            guard let storageName = userAPIKeyStorageName else { return false }
            return providerKeyStorageNamesWithKeys.contains(storageName)
        case .assemblyAI, .deepgram, .elevenLabs, .soniox, .speechmatics:
            return false
        }
    }

    public var preservesUnavailableSelectedTextEnhancementModel: Bool {
        self == .ollama
    }

    public func defaultTextEnhancementModel(from defaults: UserDefaults = .standard) -> String {
        if let provider = aiModelProvider {
            return VoiceInkAIModelCatalog.defaultModel(for: provider)
        }

        switch self {
        case .ollama:
            return VoiceInkDynamicAIProviderPreference.ollamaSelectedModel(
                from: defaults,
                fallback: Self.defaultOllamaTextEnhancementModel
            )
        case .localCLI:
            return Self.localCLITextEnhancementModel
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderModel(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }

    public var staticTextEnhancementModels: [String] {
        if let provider = aiModelProvider {
            return VoiceInkAIModelCatalog.availableModels(for: provider)
        }

        switch self {
        case .ollama, .localCLI, .custom:
            return []
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelCatalog")
        }
    }

    public var textEnhancementModelCatalogSource: VoiceInkAIEnhancementModelCatalogSource {
        switch self {
        case .ollama:
            return .ollamaRuntime
        case .openRouter:
            return .openRouterRemote
        case .localCLI, .custom:
            return .none
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .soniox, .speechmatics:
            return .staticModels
        }
    }

    public var supportsUserInitiatedTextEnhancementModelRefresh: Bool {
        textEnhancementModelCatalogSource == .openRouterRemote
    }

    public var textEnhancementSettingsSurface: VoiceInkAIEnhancementSettingsSurface {
        switch self {
        case .ollama:
            return .ollama
        case .localCLI:
            return .localCLI
        case .custom:
            return .custom
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            return .apiKey
        }
    }

    public func textEnhancementAvailableModels(
        ollamaModels: [String],
        openRouterModels: [String]
    ) -> [String] {
        switch textEnhancementModelCatalogSource {
        case .ollamaRuntime:
            return ollamaModels
        case .openRouterRemote:
            return openRouterModels
        case .staticModels:
            return staticTextEnhancementModels
        case .none:
            return []
        }
    }

    public func textEnhancementRequestURLString(from defaults: UserDefaults = .standard) -> String {
        if let corePostProcessingURL = aiModelProvider?.postProcessingRequestURL {
            return corePostProcessingURL.absoluteString
        }

        switch self {
        case .ollama:
            return VoiceInkDynamicAIProviderPreference.ollamaBaseURL(from: defaults)
        case .localCLI:
            return ""
        case .custom:
            return VoiceInkDynamicAIProviderPreference.customProviderBaseURL(from: defaults)
        case .anthropic, .assemblyAI, .cerebras, .deepgram, .elevenLabs, .groq, .gemini, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            preconditionFailure("Core-backed providers should return from VoiceInkAIModelProvider.postProcessingRequestURL")
        }
    }

    public func textEnhancementRequestURL(from defaults: UserDefaults = .standard) -> URL? {
        URL(string: textEnhancementRequestURLString(from: defaults))
    }

    public func selectedTextEnhancementModel(
        _ selectedModel: String?,
        availableModels: [String],
        defaultModel: String
    ) -> String {
        guard let selectedModel,
              !selectedModel.isEmpty else {
            return defaultModel
        }

        if preservesUnavailableSelectedTextEnhancementModel || availableModels.contains(selectedModel) {
            return selectedModel
        }

        return defaultModel
    }

    public func textEnhancementModelToSelectAfterRefresh(
        currentModel: String,
        refreshedModels: [String],
        defaultModel: String
    ) -> String? {
        guard let firstRefreshedModel = refreshedModels.first else {
            return nil
        }

        switch self {
        case .ollama:
            return refreshedModels.contains(currentModel) ? nil : firstRefreshedModel
        case .openRouter:
            return currentModel == defaultModel ? firstRefreshedModel : nil
        case .anthropic, .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .groq, .gemini, .localCLI, .mistral, .openAI, .soniox, .speechmatics:
            return nil
        }
    }

    public var apiKeyVerificationRoute: VoiceInkAIEnhancementAPIKeyVerificationRoute? {
        switch self {
        case .assemblyAI:
            return .sharedProvider(.assemblyAI)
        case .deepgram:
            return .sharedProvider(.deepgram)
        case .elevenLabs:
            return .sharedProvider(.elevenLabs)
        case .gemini:
            return .sharedProvider(.gemini)
        case .mistral:
            return .sharedProvider(.mistral)
        case .soniox:
            return .sharedProvider(.soniox)
        case .speechmatics:
            return .sharedProvider(.speechmatics)
        case .anthropic:
            return .anthropicMessages
        case .cerebras, .custom, .groq, .openAI:
            return .openAICompatibleModels
        case .openRouter:
            return .openRouterModels
        case .ollama, .localCLI:
            return nil
        }
    }

    public var textEnhancementExecutionRoute: VoiceInkAIEnhancementExecutionRoute {
        switch self {
        case .ollama:
            return .ollama
        case .localCLI:
            return .localCLI
        case .anthropic:
            return .anthropicMessages
        case .assemblyAI, .cerebras, .custom, .deepgram, .elevenLabs, .gemini, .groq, .mistral, .openAI, .openRouter, .soniox, .speechmatics:
            return .openAICompatibleChatCompletions
        }
    }

    public var unsupportedAPIKeyVerificationMessage: String {
        "\(rawValue) does not support API key verification."
    }

    public var invalidTextEnhancementRequestURLMessage: String {
        "\(rawValue) has an invalid API endpoint URL. Please update it in AI settings."
    }

    public var apiKeyConsoleURL: URL? {
        aiModelProvider?.apiKeyConsoleURL
    }
}

public extension VoiceInkAIModelProvider {
    var postProcessingRequestURL: URL? {
        switch self {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .assemblyAI:
            return VoiceInkProviderEndpoint.assemblyAITranscriptsURL(from: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL)
        case .cerebras:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.cerebras.apiBaseURL)
        case .deepgram:
            return nil
        case .elevenLabs:
            return VoiceInkProviderEndpoint.elevenLabsSpeechToTextURL(from: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL)
        case .gemini:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.gemini.apiBaseURL)
        case .groq:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.groq.apiBaseURL)
        case .mistral:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.mistralAPIBaseURL)
        case .openAI:
            return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: VoiceInkProviderEndpoint.openAI.apiBaseURL)
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .soniox:
            return VoiceInkProviderEndpoint.sonioxAPIBaseURL
        case .speechmatics:
            return VoiceInkProviderEndpoint.speechmaticsAPIBaseURL
        }
    }

    var apiKeyConsoleURL: URL {
        switch self {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")!
        case .assemblyAI:
            return URL(string: "https://www.assemblyai.com/dashboard/api-keys")!
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/speech-synthesis")!
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.consoleURL
        case .groq:
            return VoiceInkProviderEndpoint.groq.consoleURL
        case .mistral:
            return URL(string: "https://console.mistral.ai/api-keys")!
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.consoleURL
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")!
        case .soniox:
            return URL(string: "https://console.soniox.com/")!
        case .speechmatics:
            return URL(string: "https://portal.speechmatics.com/manage-access/")!
        }
    }
}
