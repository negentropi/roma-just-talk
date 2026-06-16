import Foundation

public enum VoiceInkProviderModelUse: Sendable {
    case transcription
    case postProcessing
}

public enum VoiceInkTranscriptionTransport: Sendable {
    case openAICompatible
    case deepgram
    case localWhisper
}

public enum VoiceInkAPIKeyVerificationTransport: Sendable {
    case openAICompatibleModels
    case deepgramProjects
}

public enum VoiceInkProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini
    case localWhisper
    case voiceInk

    public var id: String { rawValue }

    public var displayName: String {
        persistedValue
    }

    private var persistedValue: String {
        switch self {
        case .groq:
            return "Groq"
        case .openAI:
            return "OpenAI"
        case .deepgram:
            return "Deepgram"
        case .cerebras:
            return "Cerebras"
        case .gemini:
            return "Gemini"
        case .localWhisper:
            return "Local (Whisper)"
        case .voiceInk:
            return "VoiceInk"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let provider = Self.provider(forPersistedValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid provider: \(value)"
            )
        }
        self = provider
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(persistedValue)
    }

    private static func provider(forPersistedValue value: String) -> VoiceInkProviderKind? {
        allCases.first { provider in
            provider.persistedValue == value || provider.rawValue == value
        }
    }

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.apiBaseURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.apiBaseURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.apiBaseURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.apiBaseURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.apiBaseURL
        case .localWhisper:
            return URL(string: "http://localhost")!
        case .voiceInk:
            return VoiceInkProviderEndpoint.voiceInkBackend.apiBaseURL
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return VoiceInkProviderEndpoint.groq.consoleURL
        case .openAI:
            return VoiceInkProviderEndpoint.openAI.consoleURL
        case .deepgram:
            return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .cerebras:
            return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .gemini:
            return VoiceInkProviderEndpoint.gemini.consoleURL
        case .localWhisper:
            return URL(string: "https://github.com/ggerganov/whisper.cpp")!
        case .voiceInk:
            return URL(string: "https://voiceink.app")!
        }
    }

    public var transcriptionTransport: VoiceInkTranscriptionTransport {
        switch self {
        case .deepgram:
            return .deepgram
        case .localWhisper:
            return .localWhisper
        case .groq, .openAI, .cerebras, .gemini, .voiceInk:
            return .openAICompatible
        }
    }

    public var apiKeyAccount: String? {
        switch self {
        case .groq:
            return VoiceInkProviderAPIKeyAccount.groq
        case .openAI:
            return VoiceInkProviderAPIKeyAccount.openAI
        case .deepgram:
            return VoiceInkProviderAPIKeyAccount.deepgram
        case .cerebras:
            return VoiceInkProviderAPIKeyAccount.cerebras
        case .gemini:
            return VoiceInkProviderAPIKeyAccount.gemini
        case .localWhisper, .voiceInk:
            return nil
        }
    }

    public var apiKeyVerificationStateKey: String? {
        switch self {
        case .groq:
            return "groqKeyVerified"
        case .openAI:
            return "openAIKeyVerified"
        case .deepgram:
            return "deepgramKeyVerified"
        case .cerebras:
            return "cerebrasKeyVerified"
        case .gemini:
            return "geminiKeyVerified"
        case .localWhisper, .voiceInk:
            return nil
        }
    }

    public var requiresUserAPIKey: Bool {
        apiKeyAccount != nil
    }

    public static var userAPIKeyProviders: [VoiceInkProviderKind] {
        allCases.filter(\.requiresUserAPIKey)
    }

    public var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        switch self {
        case .deepgram:
            return .deepgramProjects
        case .groq, .openAI, .cerebras, .gemini:
            return .openAICompatibleModels
        case .localWhisper, .voiceInk:
            return nil
        }
    }

    public var transcriptionModelProvider: VoiceInkTranscriptionModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .deepgram:
            return .deepgram
        case .gemini:
            return .gemini
        case .localWhisper:
            return .local
        case .voiceInk:
            return .voiceInk
        case .cerebras:
            return nil
        }
    }

    public var aiModelProvider: VoiceInkAIModelProvider? {
        switch self {
        case .groq:
            return .groq
        case .openAI:
            return .openAI
        case .cerebras:
            return .cerebras
        case .gemini:
            return .gemini
        case .deepgram, .localWhisper, .voiceInk:
            return nil
        }
    }

    public func fixedModel(for use: VoiceInkProviderModelUse) -> String? {
        switch (self, use) {
        case (.voiceInk, .transcription):
            return VoiceInkTranscriptionModelCatalog.voiceInkTranscriptionModel
        case (.voiceInk, .postProcessing):
            return VoiceInkAIModelCatalog.voiceInkPostProcessingModel
        default:
            return nil
        }
    }

    public func supportsModelUse(_ use: VoiceInkProviderModelUse) -> Bool {
        fixedModel(for: use) != nil || !models(for: use).isEmpty
    }

    public func defaultModel(for use: VoiceInkProviderModelUse) -> String? {
        fixedModel(for: use) ?? models(for: use).first
    }

    public func models(for use: VoiceInkProviderModelUse) -> [String] {
        switch use {
        case .transcription:
            guard let provider = transcriptionModelProvider else { return [] }
            return VoiceInkTranscriptionModelCatalog.modelNames(for: provider)
        case .postProcessing:
            guard let provider = aiModelProvider else { return [] }
            return VoiceInkAIModelCatalog.availableModels(for: provider)
        }
    }
}
