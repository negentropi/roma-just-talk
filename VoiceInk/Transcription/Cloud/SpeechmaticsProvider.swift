import Foundation
import SwiftData
import VoiceInkCore

struct SpeechmaticsProvider: CloudProvider {
    let modelProvider: ModelProvider = .speechmatics
    private let transcriptionClient = VoiceInkSpeechmaticsTranscriptionClient()

    var models: [CloudModel] {
        VoiceInkTranscriptionModelCatalog
            .cloudModels(for: .speechmatics)
            .map { $0.makeCloudModel(provider: .speechmatics) }
    }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        do {
            let text = try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: customVocabulary,
                errorDomain: "SpeechmaticsAPI"
            )
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "SpeechmaticsAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SpeechmaticsStreamingProvider(modelContext: modelContext)
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        let result = await transcriptionClient.verifyAPIKeyDetailed(
            baseURL: VoiceInkProviderEndpoint.speechmaticsAPIBaseURL,
            apiKey: key
        )
        return (result.isValid, result.errorMessage)
    }
}
