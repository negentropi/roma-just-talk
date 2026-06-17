public enum VoiceInkAIModelProvider: String, CaseIterable, Sendable {
    case anthropic
    case assemblyAI
    case cerebras
    case deepgram
    case elevenLabs
    case groq
    case gemini
    case mistral
    case openAI
    case openRouter
    case soniox
    case speechmatics
}

public enum VoiceInkAIModelCatalog {
    public static func defaultModel(for provider: VoiceInkAIModelProvider) -> String {
        switch provider {
        case .anthropic:
            return "claude-sonnet-4-6"
        case .assemblyAI:
            return "universal-3-pro"
        case .cerebras:
            return "gpt-oss-120b"
        case .deepgram:
            return "whisper-1"
        case .elevenLabs:
            return "scribe_v2"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-2.5-flash-lite"
        case .mistral:
            return "mistral-large-latest"
        case .openAI:
            return "gpt-5.4"
        case .openRouter:
            return "openai/gpt-oss-120b"
        case .soniox:
            return "stt-async-v4"
        case .speechmatics:
            return "speechmatics-enhanced"
        }
    }

    public static func firstAvailableModel(for provider: VoiceInkAIModelProvider) -> String {
        availableModels(for: provider).first ?? defaultModel(for: provider)
    }

    public static func availableModels(for provider: VoiceInkAIModelProvider) -> [String] {
        switch provider {
        case .anthropic:
            return [
                "claude-opus-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-opus-4-5",
                "claude-sonnet-4-5",
                "claude-haiku-4-5"
            ]
        case .assemblyAI:
            return ["universal-3-pro"]
        case .cerebras:
            return [
                "gpt-oss-120b",
                "zai-glm-4.7"
            ]
        case .deepgram:
            return ["whisper-1"]
        case .elevenLabs:
            return ["scribe_v1", "scribe_v2"]
        case .groq:
            return [
                "llama-3.1-8b-instant",
                "llama-3.3-70b-versatile",
                "qwen/qwen3-32b",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ]
        case .gemini:
            return [
                "gemini-3.5-flash",
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite"
            ]
        case .mistral:
            return [
                "mistral-large-latest",
                "mistral-medium-latest",
                "mistral-small-latest"
            ]
        case .openAI:
            return [
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-5.2",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano"
            ]
        case .openRouter:
            return []
        case .soniox:
            return ["stt-async-v4"]
        case .speechmatics:
            return ["speechmatics-enhanced"]
        }
    }
}
