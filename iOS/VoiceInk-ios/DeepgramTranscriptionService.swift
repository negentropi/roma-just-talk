//
//  DeepgramTranscriptionService.swift
//

import Foundation
import VoiceInkCore

struct DeepgramTranscriptionService: TranscriptionService {
    
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        let request = try VoiceInkDeepgramRequestBuilder.makeTranscriptionRequest(
            baseURL: apiBaseURL,
            apiKey: apiKey,
            model: model,
            audioData: audioData,
            language: language
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DeepgramAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        return try VoiceInkDeepgramTranscriptionCodec.transcript(from: data)
    }
    
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        let request = VoiceInkDeepgramRequestBuilder.makeProjectsRequest(baseURL: apiBaseURL, apiKey: apiKey)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
