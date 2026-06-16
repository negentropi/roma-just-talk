import Foundation
import VoiceInkCore

struct LLMPostProcessor {
    private let client = OpenAICompatibleClient()

    func postProcessTranscript(provider: Provider, apiKey: String, model: String, prompt: String, transcript: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        let systemPrompt = VoiceInkAIRequestPrompts.postProcessingSystemPrompt
        let contentPrompt = VoiceInkAIRequestPrompts.postProcessingUserPrompt(prompt: prompt, transcript: transcript)
        let messages = [
            OAChatMessage(role: "system", content: systemPrompt),
            OAChatMessage(role: "user", content: contentPrompt)
        ]
        
        let result = try await client.chatCompletion(baseURL: provider.baseURL, apiKey: apiKey, model: model, messages: messages, temperature: 0.2)
        let filteredResult = VoiceInkAIEnhancementOutputFilter.filter(result)
        return filteredResult.isEmpty ? transcript : filteredResult
    }
}
