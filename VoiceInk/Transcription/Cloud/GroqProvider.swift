import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct GroqProvider: CloudProvider {
    let modelProvider: ModelProvider = .groq

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .groq)
            .map { $0.makeCloudModel(provider: .groq) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await OpenAITranscriptionClient.transcribe(
            baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            prompt: prompt
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await OpenAITranscriptionClient.verifyAPIKey(
            baseURL: VoiceInkProviderEndpoint.groq.apiBaseURL,
            apiKey: key
        )
    }
}
