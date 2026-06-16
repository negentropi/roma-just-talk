import Foundation
import VoiceInkCore

typealias OAChatMessage = VoiceInkOpenAICompatibleChatMessage

struct OpenAICompatibleClient {
    func verifyAPIKey(baseURL: URL, apiKey: String) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch { return false }
    }

    func chatCompletion(baseURL: URL, apiKey: String, model: String, messages: [OAChatMessage], temperature: Double? = 0.2) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try VoiceInkOpenAICompatibleChatCodec.requestBody(
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
