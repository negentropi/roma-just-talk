import Foundation
import VoiceInkCore

enum ModelType {
    case transcription
    case postProcessing

    var coreModelUse: VoiceInkProviderModelUse {
        switch self {
        case .transcription:
            return .transcription
        case .postProcessing:
            return .postProcessing
        }
    }
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

    var coreKind: VoiceInkProviderKind {
        switch self {
        case .groq:
            return .groq
        case .openai:
            return .openAI
        case .deepgram:
            return .deepgram
        case .cerebras:
            return .cerebras
        case .gemini:
            return .gemini
        case .local:
            return .localWhisper
        case .voiceink:
            return .voiceInk
        }
    }

    var baseURL: URL {
        coreKind.apiBaseURL
    }
    
    var consoleURL: URL {
        coreKind.consoleURL
    }

    var requiresUserAPIKey: Bool {
        coreKind.requiresUserAPIKey
    }

    var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        coreKind.apiKeyVerificationTransport
    }

    func models(for type: ModelType) -> [String] {
        coreKind.models(for: type.coreModelUse)
    }
}
