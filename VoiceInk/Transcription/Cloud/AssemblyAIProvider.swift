import Foundation
import SwiftData
import VoiceInkCore

struct AssemblyAIProvider: CloudProvider {
    let modelProvider: ModelProvider = .assemblyAI
    private let transcriptionClient = VoiceInkAssemblyAITranscriptionClient()

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        do {
            let text = try await transcriptionClient.transcribeAudioData(
                baseURL: VoiceInkProviderEndpoint.assemblyAIAPIBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language,
                prompt: prompt,
                customVocabulary: customVocabulary,
                errorDomain: "AssemblyAIAPI"
            )
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError where error.domain == "AssemblyAIAPI" {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        AssemblyAIStreamingProvider(modelContext: modelContext)
    }

}
