public enum VoiceInkProviderAPIKeyAccount {
    public static let groq = "groqAPIKey"
    public static let deepgram = "deepgramAPIKey"
    public static let cerebras = "cerebrasAPIKey"
    public static let gemini = "geminiAPIKey"
    public static let mistral = "mistralAPIKey"
    public static let elevenLabs = "elevenLabsAPIKey"
    public static let soniox = "sonioxAPIKey"
    public static let speechmatics = "speechmaticsAPIKey"
    public static let assemblyAI = "assemblyAIAPIKey"
    public static let xAI = "xaiAPIKey"
    public static let cartesia = "cartesiaAPIKey"
    public static let openAI = "openAIAPIKey"
    public static let anthropic = "anthropicAPIKey"
    public static let openRouter = "openRouterAPIKey"

    public static func accountIdentifier(forProviderName provider: String) -> String {
        let normalizedProvider = normalized(provider)
        return knownAccountsByProviderName[normalizedProvider] ?? "\(normalizedProvider)APIKey"
    }

    private static let knownAccountsByProviderName: [String: String] = [
        "groq": groq,
        "deepgram": deepgram,
        "cerebras": cerebras,
        "gemini": gemini,
        "mistral": mistral,
        "elevenlabs": elevenLabs,
        "soniox": soniox,
        "speechmatics": speechmatics,
        "assemblyai": assemblyAI,
        "xai": xAI,
        "cartesia": cartesia,
        "openai": openAI,
        "anthropic": anthropic,
        "openrouter": openRouter
    ]

    private static func normalized(_ provider: String) -> String {
        provider.lowercased()
    }
}
