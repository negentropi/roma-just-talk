import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

struct SpeechmaticsProvider: CloudProvider {
    let modelProvider: ModelProvider = .speechmatics

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .speechmatics)
            .map { $0.makeCloudModel(provider: .speechmatics) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        return try await SpeechmaticsClient.transcribe(
            audioData: audioData,
            fileName: fileName,
            apiKey: apiKey,
            language: language,
            customVocabulary: customVocabulary
        )
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SpeechmaticsStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        return await SpeechmaticsClient.verifyAPIKey(key)
    }
}
