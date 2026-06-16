import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .assemblyAI)
            .map { $0.makeCloudModel(provider: .assemblyAI) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await AssemblyAIClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            model: model,
            language: language,
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await AssemblyAIClient.verifyAPIKey(key)
    }
}
