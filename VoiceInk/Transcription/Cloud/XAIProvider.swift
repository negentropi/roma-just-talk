import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct XAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .xai

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .xai)
            .map { $0.makeCloudModel(provider: .xai) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await XAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language,
            format: true
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        XAIStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await XAIClient.verifyAPIKey(key)
    }
}
