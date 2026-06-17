import Foundation

public enum VoiceInkAIEnhancementAPIKeyVerificationTransport: Sendable, Equatable {
    case anthropicMessages
    case openAICompatibleModels
    case geminiModels
    case elevenLabsUser
    case deepgramProjects
    case mistralModels
    case sonioxFiles
    case speechmaticsJobs
    case assemblyAITranscripts
    case openRouterModels
}

public enum VoiceInkAIEnhancementProviderKind: String, CaseIterable, Sendable {
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

    public var preservesUnavailableSelectedTextEnhancementModel: Bool {
        self == .ollama
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

    public var apiKeyVerificationTransport: VoiceInkAIEnhancementAPIKeyVerificationTransport? {
        switch self {
        case .anthropic:
            return .anthropicMessages
        case .assemblyAI:
            return .assemblyAITranscripts
        case .cerebras, .custom, .groq, .openAI:
            return .openAICompatibleModels
        case .deepgram:
            return .deepgramProjects
        case .elevenLabs:
            return .elevenLabsUser
        case .gemini:
            return .geminiModels
        case .mistral:
            return .mistralModels
        case .openRouter:
            return .openRouterModels
        case .soniox:
            return .sonioxFiles
        case .speechmatics:
            return .speechmaticsJobs
        case .ollama, .localCLI:
            return nil
        }
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
