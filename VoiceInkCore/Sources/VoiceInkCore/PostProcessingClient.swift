import Foundation

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
        let aiProvider = provider.aiModelProvider
        let temperature = VoiceInkAIReasoningConfig.temperature(forModelName: model, defaultTemperature: request.temperature)

        let result = try await client.chatCompletion(
            baseURL: provider.apiBaseURL,
            apiKey: apiKey,
            model: model,
            messages: request.messages,
            temperature: temperature,
            reasoningEffort: aiProvider.flatMap {
                VoiceInkAIReasoningConfig.reasoningEffort(for: $0, modelName: model)
            },
            extraBodyParameters: aiProvider.flatMap {
                VoiceInkAIReasoningConfig.extraBodyParameters(for: $0, modelName: model)
            }
        )

        return VoiceInkPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}
