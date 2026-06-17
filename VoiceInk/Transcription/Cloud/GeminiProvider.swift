import Foundation
import SwiftData
import VoiceInkCore

struct GeminiProvider: CloudProvider {
    let modelProvider: ModelProvider = .gemini
    private let transcriptionClient = VoiceInkGeminiTranscriptionClient()

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        do {
            let text = try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.geminiNativeAPIBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                errorDomain: "GeminiAPI",
                timeout: 60
            )
            guard !text.isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "GeminiAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? { nil }

}
