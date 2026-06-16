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

    public static var geminiNativeAPIBaseURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    public static var mistralAPIBaseURL: URL {
        URL(string: "https://api.mistral.ai")!
    }

    public static var elevenLabsAPIBaseURL: URL {
        URL(string: "https://api.elevenlabs.io")!
    }

    public static var xaiAPIBaseURL: URL {
        URL(string: "https://api.x.ai")!
    }

    public static var sonioxAPIBaseURL: URL {
        URL(string: "https://api.soniox.com/v1")!
    }

    public static var speechmaticsAPIBaseURL: URL {
        URL(string: "https://asr.api.speechmatics.com/v2")!
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
            return URL(string: "https://console.deepgram.com/api-keys")!
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/")!
        case .gemini:
            return URL(string: "https://makersuite.google.com/app/apikey")!
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

    public static func geminiGenerateContentURL(from baseURL: URL, model: String) -> URL {
        baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(model):generateContent")
    }

    public static func geminiModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("models")
    }

    public static func mistralAudioTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/audio/transcriptions")
    }

    public static func mistralModelsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/models")
    }

    public static func elevenLabsSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/speech-to-text")
    }

    public static func elevenLabsUserURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/user")
    }

    public static func xaiSpeechToTextURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/stt")
    }

    public static func xaiAPIKeyURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("v1/api-key")
    }

    public static func sonioxFilesURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("files")
    }

    public static func sonioxTranscriptionsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("transcriptions")
    }

    public static func sonioxTranscriptionURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func sonioxTranscriptURL(from baseURL: URL, id: String) -> URL {
        sonioxTranscriptionURL(from: baseURL, id: id).appendingPathComponent("transcript")
    }

    public static func speechmaticsJobsURL(from baseURL: URL) -> URL {
        baseURL.appendingPathComponent("jobs")
    }

    public static func speechmaticsJobURL(from baseURL: URL, id: String) -> URL {
        speechmaticsJobsURL(from: baseURL).appendingPathComponent(id)
    }

    public static func speechmaticsTranscriptURL(from baseURL: URL, id: String) -> URL {
        let url = speechmaticsJobURL(from: baseURL, id: id).appendingPathComponent("transcript")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "txt")]
        return components.url!
    }
}
