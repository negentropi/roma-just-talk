import Foundation

public struct VoiceInkAIChatRequestParameters {
    public let temperature: Double
    public let reasoningEffort: String?
    public let extraBodyParameters: [String: Any]?

    public init(
        temperature: Double,
        reasoningEffort: String?,
        extraBodyParameters: [String: Any]?
    ) {
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.extraBodyParameters = extraBodyParameters
    }
}

public enum VoiceInkAIReasoningConfig {
    public static func temperature(forModelName modelName: String, defaultTemperature: Double = 0.3) -> Double {
        modelName.lowercased().hasPrefix("gpt-5") ? 1.0 : defaultTemperature
    }

    public static func chatRequestParameters(
        for provider: VoiceInkAIModelProvider?,
        modelName: String,
        defaultTemperature: Double = 0.3
    ) -> VoiceInkAIChatRequestParameters {
        VoiceInkAIChatRequestParameters(
            temperature: temperature(forModelName: modelName, defaultTemperature: defaultTemperature),
            reasoningEffort: provider.flatMap {
                reasoningEffort(for: $0, modelName: modelName)
            },
            extraBodyParameters: provider.flatMap {
                extraBodyParameters(for: $0, modelName: modelName)
            }
        )
    }

    private static let geminiNoneReasoningModels: Set<String> = [
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite"
    ]

    private static let geminiLowReasoningModels: Set<String> = [
        "gemini-3.1-pro-preview"
    ]

    private static let geminiMinimalReasoningModels: Set<String> = [
        "gemini-3.5-flash",
        "gemini-2.5-pro",
        "gemini-3-flash-preview",
        "gemini-3.1-flash-lite"
    ]

    private static let openAINoneReasoningModels: Set<String> = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.4-nano",
        "gpt-5.2"
    ]

    private static let cerebrasGPTOSSMinimumReasoningModels: Set<String> = [
        "gpt-oss-120b"
    ]

    private static let groqGPTOSSMinimumReasoningModels: Set<String> = [
        "openai/gpt-oss-120b",
        "openai/gpt-oss-20b"
    ]

    private static let cerebrasNoneReasoningModels: Set<String> = [
        "zai-glm-4.7"
    ]

    private static let groqQwenReasoningModels: Set<String> = [
        "qwen/qwen3-32b"
    ]

    public static func reasoningEffort(
        for provider: VoiceInkAIModelProvider,
        modelName: String
    ) -> String? {
        switch provider {
        case .gemini:
            if geminiNoneReasoningModels.contains(modelName) { return "none" }
            if geminiLowReasoningModels.contains(modelName) { return "low" }
            if geminiMinimalReasoningModels.contains(modelName) { return "minimal" }
        case .openAI:
            if openAINoneReasoningModels.contains(modelName) { return "none" }
        case .cerebras:
            if cerebrasGPTOSSMinimumReasoningModels.contains(modelName) { return "low" }
            if cerebrasNoneReasoningModels.contains(modelName) { return "none" }
        case .groq:
            if groqGPTOSSMinimumReasoningModels.contains(modelName) { return "low" }
            if groqQwenReasoningModels.contains(modelName) { return "none" }
        case .anthropic, .assemblyAI, .deepgram, .elevenLabs, .mistral, .openRouter, .soniox, .speechmatics:
            break
        }
        return nil
    }

    public static func extraBodyParameters(
        for provider: VoiceInkAIModelProvider,
        modelName: String
    ) -> [String: Any]? {
        if provider == .cerebras && modelName == "gpt-oss-120b" {
            return ["reasoning_format": "hidden"]
        }
        if provider == .groq && (modelName == "openai/gpt-oss-120b" || modelName == "openai/gpt-oss-20b") {
            return ["include_reasoning": false]
        }
        return nil
    }
}
