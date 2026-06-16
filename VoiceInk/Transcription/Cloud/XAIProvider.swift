import Foundation
import SwiftData
import VoiceInkCore

struct XAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .xai
    private let transcriptionClient = VoiceInkXAITranscriptionClient()

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .xai)
            .map { $0.makeCloudModel(provider: .xai) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        do {
            return try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                format: true,
                errorDomain: "XAIAPI",
                timeout: 60,
                maxRetries: 2
            )
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "XAIAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        XAIStreamingProvider()
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        let result = await transcriptionClient.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.xaiAPIBaseURL,
            apiKey: key
        )
        return (result.isValid, result.errorMessage)
    }
}
