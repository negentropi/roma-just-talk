//
//  GroqTranscriptionService.swift
//

import Foundation
import VoiceInkCore

protocol TranscriptionService {
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String?) async throws -> String
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool
}

struct GroqTranscriptionService: TranscriptionService {
    // OpenAI-compatible APIs. Caller supplies baseURL and model.

    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        let components = URLComponents(
            url: VoiceInkProviderEndpoint.openAICompatibleAudioTranscriptionsURL(from: apiBaseURL),
            resolvingAgainstBaseURL: false
        )!
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        let fileData = try Data(contentsOf: fileURL)
        request.setValue(VoiceInkOpenAICompatibleTranscriptionCodec.multipartContentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        let body = VoiceInkOpenAICompatibleTranscriptionCodec.requestBody(
            audioData: fileData,
            fileName: fileURL.lastPathComponent,
            model: model,
            boundary: boundary,
            language: language
        )
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "GroqAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Some OpenAI-compatible APIs return JSON with a text property; others return nested objects.
        // Try to parse a simple text response first, else fallback to raw string.
        if let text = try? VoiceInkOpenAICompatibleTranscriptionCodec.textIfPresent(from: data) {
            return text
        }
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        // Hit a lightweight endpoint (models listing) to verify
        var request = URLRequest(url: VoiceInkProviderEndpoint.openAICompatibleModelsURL(from: apiBaseURL))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
