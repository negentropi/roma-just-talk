import Foundation

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
