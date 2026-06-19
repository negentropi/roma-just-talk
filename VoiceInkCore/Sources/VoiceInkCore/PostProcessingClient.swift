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
