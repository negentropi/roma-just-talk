import Foundation

public struct VoiceInkPostProcessingRequest: Equatable, Sendable {
    public static let defaultTemperature = 0.2

    public let messages: [VoiceInkOpenAICompatibleChatMessage]
    public let temperature: Double

    public init?(
        prompt: String,
        transcript: String,
        temperature: Double = Self.defaultTemperature
    ) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.messages = [
            VoiceInkOpenAICompatibleChatMessage(
                role: "system",
                content: VoiceInkAIRequestPrompts.postProcessingSystemPrompt
            ),
            VoiceInkOpenAICompatibleChatMessage(
                role: "user",
                content: VoiceInkAIRequestPrompts.postProcessingUserPrompt(
                    prompt: prompt,
                    transcript: transcript
                )
            )
        ]
        self.temperature = temperature
    }

    public static func finalizedTranscript(
        from responseText: String,
        fallbackTranscript: String
    ) -> String {
        let filteredText = VoiceInkAIEnhancementOutputFilter.filter(responseText)
        return filteredText.isEmpty ? fallbackTranscript : filteredText
    }
}

public struct VoiceInkPostProcessingClient: Sendable {
    private let client: VoiceInkOpenAICompatibleClient

    public init(client: VoiceInkOpenAICompatibleClient = VoiceInkOpenAICompatibleClient()) {
        self.client = client
    }

    public func postProcessTranscript(
        provider: VoiceInkProviderKind,
        apiKey: String,
        model: String,
        prompt: String,
        transcript: String
    ) async throws -> String {
        guard let request = VoiceInkPostProcessingRequest(prompt: prompt, transcript: transcript) else {
            return transcript
        }
        let requestParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
            for: provider.aiModelProvider,
            modelName: model,
            defaultTemperature: request.temperature
        )

        let result = try await client.chatCompletion(
            baseURL: provider.apiBaseURL,
            apiKey: apiKey,
            model: model,
            messages: request.messages,
            temperature: requestParameters.temperature,
            reasoningEffort: requestParameters.reasoningEffort,
            extraBodyParameters: requestParameters.extraBodyParameters
        )

        return VoiceInkPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}
