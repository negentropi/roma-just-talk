import Foundation
import SwiftData
import VoiceInkCore

class CloudTranscriptionService: TranscriptionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let audioData = try loadAudioData(from: audioURL)
        let fileName = audioURL.lastPathComponent
        let language = VoiceInkTranscriptionLanguagePreference.requestLanguage()
        let prompt = VoiceInkTranscriptionPromptPreference.requestPrompt()

        do {
            if model.provider == .custom {
                guard let customModel = model as? CustomCloudModel else {
                    throw CloudTranscriptionError.unsupportedProvider
                }
                return try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
                    apiEndpoint: customModel.apiEndpoint,
                    apiKey: customModel.apiKey,
                    model: customModel.modelName,
                    audioData: audioData,
                    fileName: fileName,
                    language: language,
                    prompt: prompt
                )
            }

            let modelProvider = model.provider
            let apiKey = try requireAPIKey(forProvider: modelProvider.apiKeyProviderName)
            return try await VoiceInkMacOSCloudTranscriptionPolicy.transcribeAudioData(
                modelProvider: modelProvider,
                apiKey: apiKey,
                modelName: model.name,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: prompt,
                customVocabulary: CustomVocabularyService.shared.rawCustomVocabularyTerms(from: modelContext)
            )
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            throw CloudTranscriptionError.networkError(error)
        }
    }

    // MARK: - Helpers

    private func loadAudioData(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CloudTranscriptionError.audioFileNotFound
        }
        return try Data(contentsOf: url)
    }

    private func requireAPIKey(forProvider provider: String) throws -> String {
        guard let apiKey = VoiceInkProviderCredential.nonBlank(
            APIKeyManager.shared.getAPIKey(forProvider: provider)
        ) else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }
}
