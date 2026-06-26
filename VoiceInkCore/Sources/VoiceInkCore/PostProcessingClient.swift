import Foundation

struct VoiceInkPostProcessingRequest: Equatable, Sendable {
    static let defaultTemperature = 0.2

    private let messages: [VoiceInkOpenAICompatibleChatMessage]
    private let temperature: Double

    init?(
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

    func applyRuntimeState<Result>(
        execute: ([VoiceInkOpenAICompatibleChatMessage], Double) async throws -> Result
    ) async throws -> Result {
        try await execute(messages, temperature)
    }

    static func finalizedTranscript(
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
        let result = try await request.applyRuntimeState { messages, temperature in
            let requestParameters = VoiceInkAIReasoningConfig.chatRequestParameters(
                for: provider.aiModelProvider,
                modelName: model,
                defaultTemperature: temperature
            )

            return try await client.chatCompletion(
                baseURL: provider.apiBaseURL,
                apiKey: apiKey,
                model: model,
                messages: messages,
                temperature: requestParameters.temperature,
                reasoningEffort: requestParameters.reasoningEffort,
                extraBodyParameters: requestParameters.extraBodyParameters
            )
        }

        return VoiceInkPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}
