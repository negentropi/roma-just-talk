import Foundation

public enum VoiceInkProviderEndpoint: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini

    public var apiBaseURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://api.groq.com/openai")!
        case .openAI:
            return URL(string: "https://api.openai.com")!
        case .deepgram:
            return URL(string: "https://api.deepgram.com")!
        case .cerebras:
            return URL(string: "https://api.cerebras.ai")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        }
    }

    public var chatCompletionsURL: URL? {
        switch self {
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .openAI:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .cerebras:
            return URL(string: "https://api.cerebras.ai/v1/chat/completions")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .deepgram:
            return nil
        }
    }

    public var consoleURL: URL {
        switch self {
        case .groq:
            return URL(string: "https://console.groq.com/keys")!
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .deepgram:
            return URL(string: "https://console.deepgram.com/project/keys")!
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/platform")!
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }
}
