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
    private let client = VoiceInkOpenAICompatibleTranscriptionClient()

    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        return try await client.transcribeAudioData(
            baseURL: apiBaseURL,
            apiKey: apiKey,
            model: model,
            audioData: fileData,
            fileName: fileURL.lastPathComponent,
            language: language,
            errorDomain: "GroqAPI"
        )
    }

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        await client.verifyAPIKey(baseURL: apiBaseURL, apiKey: apiKey)
    }
}
