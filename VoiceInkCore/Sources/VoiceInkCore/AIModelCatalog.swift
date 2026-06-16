public enum VoiceInkAIModelProvider: String, CaseIterable, Sendable {
    case cerebras
    case groq
    case gemini
    case openAI
}

public enum VoiceInkAIModelCatalog {
    public static func defaultModel(for provider: VoiceInkAIModelProvider) -> String {
        switch provider {
        case .cerebras:
            return "gpt-oss-120b"
        case .groq:
            return "openai/gpt-oss-120b"
        case .gemini:
            return "gemini-2.5-flash-lite"
        case .openAI:
            return "gpt-5.4"
        }
    }

    public static func firstAvailableModel(for provider: VoiceInkAIModelProvider) -> String {
        availableModels(for: provider).first ?? defaultModel(for: provider)
    }

    public static func availableModels(for provider: VoiceInkAIModelProvider) -> [String] {
        switch provider {
        case .cerebras:
            return [
                "gpt-oss-120b",
                "zai-glm-4.7"
            ]
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
        }
    }
}
