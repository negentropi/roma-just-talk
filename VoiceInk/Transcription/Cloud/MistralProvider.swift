import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct MistralProvider: CloudProvider {
    let modelProvider: ModelProvider = .mistral

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .mistral)
            .map { $0.makeCloudModel(provider: .mistral) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await MistralTranscriptionClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        MistralStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await MistralTranscriptionClient.verifyAPIKey(key)
    }
}
