import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct ElevenLabsProvider: CloudProvider {
    let modelProvider: ModelProvider = .elevenLabs

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .elevenLabs)
            .map { $0.makeCloudModel(provider: .elevenLabs) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await ElevenLabsClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        ElevenLabsStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await ElevenLabsClient.verifyAPIKey(key)
    }
}
