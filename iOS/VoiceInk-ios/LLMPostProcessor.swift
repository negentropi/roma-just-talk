import Foundation
import VoiceInkCore

struct LLMPostProcessor {
    private let client = VoiceInkOpenAICompatibleClient()

    func postProcessTranscript(provider: VoiceInkProviderKind, apiKey: String, model: String, prompt: String, transcript: String) async throws -> String {
        guard let request = VoiceInkPostProcessingRequest(prompt: prompt, transcript: transcript) else {
            return transcript
        }

        let result = try await client.chatCompletion(
            baseURL: provider.apiBaseURL,
            apiKey: apiKey,
            model: model,
            messages: request.messages,
            temperature: request.temperature
        )
        return VoiceInkPostProcessingRequest.finalizedTranscript(
            from: result,
            fallbackTranscript: transcript
        )
    }
}
