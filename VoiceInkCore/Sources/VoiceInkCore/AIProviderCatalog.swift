import Foundation

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

public enum VoiceInkAIEnhancementConnectionStatusTone: Sendable, Equatable {
    case connected
    case disconnected
}

public enum VoiceInkAIEnhancementConnectionStatusPresentation: Sendable, Equatable {
    case checking
    case status(text: String, tone: VoiceInkAIEnhancementConnectionStatusTone)
}

public struct VoiceInkAIEnhancementProviderSettingsPresentation: Sendable, Equatable {
    public let connectedText: String
    public let disconnectedText: String

    public static let macOS = VoiceInkAIEnhancementProviderSettingsPresentation(
        connectedText: "Connected",
        disconnectedText: "Disconnected"
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
}

public struct VoiceInkAIEnhancementCredentialState: Equatable, Sendable {
    public let apiKey: String
    public let isAPIKeyValid: Bool

    public init(apiKey: String, isAPIKeyValid: Bool) {
        self.apiKey = apiKey
        self.isAPIKeyValid = isAPIKeyValid
    }
}

public enum VoiceInkAIEnhancementProviderKind: String, CaseIterable, Sendable {
    public static let missingVerificationCandidateMessage = "Environment variable is missing or empty"
    public static let invalidOrMissingBaseURLConfigurationMessage = "Invalid or missing base URL configuration"
    public static let defaultOllamaTextEnhancementModel = "mistral"
    public static let legacyOllamaServiceSelectedModelFallback = "llama2"
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

    public static func connectedTextEnhancementProviders(
        hasUserAPIKey: (Self) -> Bool,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> [Self] {
        selectableTextEnhancementProviders.filter { provider in
            provider.isConnectedForTextEnhancement(
                hasUserAPIKey: { hasUserAPIKey(provider) },
                isOllamaConnected: isOllamaConnected,
                isLocalCLIConfigured: isLocalCLIConfigured
            )
        }
    }

    public func isConnectedForTextEnhancement(
        hasUserAPIKey: () -> Bool,
        isOllamaConnected: Bool,
        isLocalCLIConfigured: Bool
    ) -> Bool {
        switch self {
        case .ollama:
            return isOllamaConnected
        case .localCLI:
            return isLocalCLIConfigured
        case .anthropic, .cerebras, .custom, .gemini, .groq, .mistral, .openAI, .openRouter:
            return hasUserAPIKey()
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
