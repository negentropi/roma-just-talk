import Foundation
import SwiftData
import VoiceInkCore

struct MistralProvider: CloudProvider {
    let modelProvider: ModelProvider = .mistral
    private let transcriptionClient = VoiceInkMistralTranscriptionClient()

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        do {
            return try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.mistralAPIBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                errorDomain: "MistralAPI",
                timeout: 30,
                maxRetries: 2
            )
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "MistralAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        MistralStreamingProvider()
    }

}
