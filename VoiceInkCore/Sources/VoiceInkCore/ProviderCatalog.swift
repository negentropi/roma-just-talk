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

public enum VoiceInkTranscriptionServiceKind: Sendable {
    case remote
    case localWhisper
}

public enum VoiceInkAPIKeyVerificationTransport: Sendable, Equatable {
    case openAICompatibleModels
    case deepgramProjects
}

public enum VoiceInkProviderAccessRequirement: Sendable {
    case userAPIKey(account: String, verificationStateKey: String, verificationTransport: VoiceInkAPIKeyVerificationTransport)
    case localWhisperModel
    case bundledService
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

    public var transcriptionServiceKind: VoiceInkTranscriptionServiceKind {
        switch transcriptionTransport {
        case .openAICompatible, .deepgram:
            return .remote
        case .localWhisper:
            return .localWhisper
        }
    }

    public var accessRequirement: VoiceInkProviderAccessRequirement {
        switch self {
        case .groq:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.groq,
                verificationStateKey: "groqKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .openAI:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.openAI,
                verificationStateKey: "openAIKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .deepgram:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.deepgram,
                verificationStateKey: "deepgramKeyVerified",
                verificationTransport: .deepgramProjects
            )
        case .cerebras:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.cerebras,
                verificationStateKey: "cerebrasKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .gemini:
            return .userAPIKey(
                account: VoiceInkProviderAPIKeyAccount.gemini,
                verificationStateKey: "geminiKeyVerified",
                verificationTransport: .openAICompatibleModels
            )
        case .localWhisper:
            return .localWhisperModel
        case .voiceInk:
            return .bundledService
        }
    }

    public var apiKeyAccount: String? {
        guard case let .userAPIKey(account, _, _) = accessRequirement else {
            return nil
        }
        return account
    }

    public var apiKeyVerificationStateKey: String? {
        guard case let .userAPIKey(_, verificationStateKey, _) = accessRequirement else {
            return nil
        }
        return verificationStateKey
    }

    public var requiresUserAPIKey: Bool {
        guard case .userAPIKey = accessRequirement else {
            return false
        }
        return true
    }

    public func runtimeAPIKey(userAPIKey: String) -> String {
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKey
        case .localWhisperModel:
            return "local"
        case .bundledService:
            return ""
        }
    }

    public func isReady(
        userAPIKey: String,
        userAPIKeyVerified: Bool,
        localWhisperModelAvailable: Bool
    ) -> Bool {
        switch accessRequirement {
        case .userAPIKey:
            return userAPIKeyVerified && !userAPIKey.isEmpty
        case .localWhisperModel:
            return localWhisperModelAvailable
        case .bundledService:
            return true
        }
    }

    public static var userAPIKeyProviders: [VoiceInkProviderKind] {
        allCases.filter(\.requiresUserAPIKey)
    }

    public static func availableProviders(
        for use: VoiceInkProviderModelUse,
        isProviderReady: (VoiceInkProviderKind) -> Bool
    ) -> [VoiceInkProviderKind] {
        allCases.filter { provider in
            provider.supportsModelUse(use) && isProviderReady(provider)
        }
    }

    public var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        guard case let .userAPIKey(_, _, verificationTransport) = accessRequirement else {
            return nil
        }
        return verificationTransport
    }

    public var canVerifyAPIKey: Bool {
        apiKeyVerificationTransport != nil
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

    public var postProcessingChatCompletionsURL: URL? {
        guard supportsModelUse(.postProcessing) else {
            return nil
        }
        return VoiceInkProviderEndpoint.openAICompatibleChatCompletionsURL(from: apiBaseURL)
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

    public func selectedModel(_ currentModel: String, for use: VoiceInkProviderModelUse) -> String {
        if let fixedModel = fixedModel(for: use) {
            return fixedModel
        }

        let availableModels = models(for: use)
        if availableModels.contains(currentModel) {
            return currentModel
        }

        return defaultModel(for: use) ?? ""
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
