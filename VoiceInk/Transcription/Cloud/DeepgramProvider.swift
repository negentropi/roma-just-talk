import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct DeepgramProvider: CloudProvider {
    let modelProvider: ModelProvider = .deepgram

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .deepgram)
            .map { $0.makeCloudModel(provider: .deepgram) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await DeepgramClient.transcribe(
            audioData: audioData,
            apiKey: apiKey,
            model: model,
            language: language
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        DeepgramStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await DeepgramClient.verifyAPIKey(key)
    }
}
