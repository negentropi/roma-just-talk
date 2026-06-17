import Foundation
import SwiftData
import VoiceInkCore

struct SonioxProvider: CloudProvider {
    let modelProvider: ModelProvider = .soniox
    private let transcriptionClient = VoiceInkSonioxTranscriptionClient()

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        do {
            let text = try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.sonioxAPIBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                customVocabulary: customVocabulary,
                errorDomain: "SonioxAPI"
            )
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "SonioxAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        SonioxStreamingProvider(modelContext: modelContext)
    }

}
