import Foundation
import VoiceInkCore

enum ModelType {
    case transcription
    case postProcessing
}

enum Provider: String, CaseIterable, Codable, Identifiable {
    case groq = "Groq"
    case openai = "OpenAI"
    case deepgram = "Deepgram"
    case cerebras = "Cerebras"
    case gemini = "Gemini"
    case local = "Local (Whisper)"
    case voiceink = "VoiceInk"

    var id: String { rawValue }

    var baseURL: URL {
        switch self {
        case .groq: return VoiceInkProviderEndpoint.groq.apiBaseURL
        case .openai: return VoiceInkProviderEndpoint.openAI.apiBaseURL
        case .deepgram: return VoiceInkProviderEndpoint.deepgram.apiBaseURL
        case .cerebras: return VoiceInkProviderEndpoint.cerebras.apiBaseURL
        case .gemini: return VoiceInkProviderEndpoint.gemini.apiBaseURL
        case .local: return URL(string: "http://localhost")! // Not used for local transcription
        case .voiceink: return VoiceInkProviderEndpoint.voiceInkBackend.apiBaseURL
        }
    }
    
    var consoleURL: URL {
        switch self {
        case .groq: return VoiceInkProviderEndpoint.groq.consoleURL
        case .openai: return VoiceInkProviderEndpoint.openAI.consoleURL
        case .deepgram: return VoiceInkProviderEndpoint.deepgram.consoleURL
        case .cerebras: return VoiceInkProviderEndpoint.cerebras.consoleURL
        case .gemini: return VoiceInkProviderEndpoint.gemini.consoleURL
        case .local: return URL(string: "https://github.com/ggerganov/whisper.cpp")! // Whisper.cpp GitHub page
        case .voiceink: return URL(string: "https://voiceink.app")! // VoiceInk website
        }
    }

    func models(for type: ModelType) -> [String] {
        switch (self, type) {
        case (.groq, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .groq)
        case (.groq, .postProcessing):
            return VoiceInkAIModelCatalog.availableModels(for: .groq)
        case (.openai, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .openAI)
        case (.openai, .postProcessing):
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
        case (.local, .transcription):
            return VoiceInkTranscriptionModelCatalog.modelNames(for: .local)
        case (.local, .postProcessing):
            return [] // Local transcription doesn't support post-processing
        case (.voiceink, .transcription):
            return [] // Hardcoded: whisper-large-v3 (no user selection)
        case (.voiceink, .postProcessing):
            return [] // Hardcoded: openai/gpt-oss-120b (no user selection)
        }
    }
}
