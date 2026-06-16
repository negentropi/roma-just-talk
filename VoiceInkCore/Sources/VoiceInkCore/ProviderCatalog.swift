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

public enum VoiceInkProviderKind: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini
    case localWhisper
    case voiceInk

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

    public func models(for use: VoiceInkProviderModelUse) -> [String] {
        switch (self, use) {
        case (.groq, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .groq)
        case (.groq, .postProcessing):
            return VoiceInkAIModelCatalog.availableModels(for: .groq)
        case (.openAI, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .openAI)
        case (.openAI, .postProcessing):
            return VoiceInkAIModelCatalog.availableModels(for: .openAI)
        case (.deepgram, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .deepgram)
        case (.deepgram, .postProcessing):
            return []
        case (.cerebras, .transcription):
            return []
        case (.cerebras, .postProcessing):
            return VoiceInkAIModelCatalog.availableModels(for: .cerebras)
        case (.gemini, .transcription):
            return []
        case (.gemini, .postProcessing):
            return VoiceInkAIModelCatalog.availableModels(for: .gemini)
        case (.localWhisper, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .local)
        case (.localWhisper, .postProcessing):
            return []
        case (.voiceInk, .transcription):
            return []
        case (.voiceInk, .postProcessing):
            return []
        }
    }
}
