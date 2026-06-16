import Foundation

public enum VoiceInkProviderEndpoint: String, CaseIterable, Sendable {
    case groq
    case openAI
    case deepgram
    case cerebras
    case gemini

    public static let voiceInkBackend = VoiceInkProviderEndpoint.groq

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
        case .groq, .openAI, .cerebras, .gemini:
            return Self.openAICompatibleChatCompletionsURL(from: apiBaseURL)
        case .deepgram:
            return nil
        }
    }

    public var deepgramListenURL: URL? {
        switch self {
        case .deepgram:
            return Self.deepgramListenURL(from: apiBaseURL)
        case .groq, .openAI, .cerebras, .gemini:
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

    public static func openAICompatibleModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func openAICompatibleChatCompletionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/chat/completions")
    }

    public static func openAICompatibleAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func deepgramListenURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/listen")
    }

    public static func deepgramProjectsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/projects")
    }
}
