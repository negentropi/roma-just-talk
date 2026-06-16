import Foundation
import VoiceInkCore

struct OpenAICompatibleClient {
    func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        let request = VoiceInkOpenAICompatibleModelsRequestBuilder.make(baseURL: baseURL, apiKey: apiKey)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch { return false }
    }

    func chatCompletion(baseURL: URL, apiKey: String, model: String, messages: [VoiceInkOpenAICompatibleChatMessage], temperature: Double? = 0.2) async throws -> String {
        let request = try VoiceInkOpenAICompatibleChatRequestBuilder.make(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LLMPostProcessing", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        return try VoiceInkOpenAICompatibleChatCodec.firstMessageContent(from: data)
    }
}
