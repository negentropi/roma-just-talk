import Foundation
import SwiftData
import VoiceInkCore

struct ElevenLabsProvider: CloudProvider {
    let modelProvider: ModelProvider = .elevenLabs
    private let transcriptionClient = VoiceInkElevenLabsTranscriptionClient()

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .elevenLabs)
            .map { $0.makeCloudModel(provider: .elevenLabs) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        do {
            return try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                errorDomain: "ElevenLabsAPI",
                timeout: 30,
                maxRetries: 2
            )
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "ElevenLabsAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        ElevenLabsStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        let result = await transcriptionClient.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.elevenLabsAPIBaseURL,
            apiKey: key
        )
        return (result.isValid, result.errorMessage)
    }
}
