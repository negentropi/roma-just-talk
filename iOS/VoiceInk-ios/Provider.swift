import Foundation
import VoiceInkCore

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

    var apiKeyAccount: String? {
        coreKind.apiKeyAccount
    }

    var apiKeyVerificationTransport: VoiceInkAPIKeyVerificationTransport? {
        coreKind.apiKeyVerificationTransport
    }

    var apiKeyVerificationStateKey: String? {
        coreKind.apiKeyVerificationStateKey
    }

    func fixedModel(for use: VoiceInkProviderModelUse) -> String? {
        coreKind.fixedModel(for: use)
    }

    func supportsModelUse(_ use: VoiceInkProviderModelUse) -> Bool {
        coreKind.supportsModelUse(use)
    }

    func models(for use: VoiceInkProviderModelUse) -> [String] {
        coreKind.models(for: use)
    }
}
