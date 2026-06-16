//
//  DeepgramTranscriptionService.swift
//

import Foundation
import VoiceInkCore

struct DeepgramTranscriptionService: TranscriptionService {
    private let client = VoiceInkDeepgramTranscriptionClient()
    
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        return try await client.transcribeAudioData(
            baseURL: apiBaseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            language: language
        )
    }
    
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        await client.verifyAPIKey(baseURL: apiBaseURL, apiKey: apiKey)
    }
}
