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
            guard let provider = modelProvider.remoteTranscriptionProviderKind else {
                throw CloudTranscriptionError.unsupportedProvider
            }
            let apiKey = try requireAPIKey(forProvider: modelProvider.apiKeyProviderName)
            return try await transcribeProvider(
                provider: provider,
                modelProvider: modelProvider,
                audioData: audioData,
                fileName: fileName,
                apiKey: apiKey,
                modelName: model.name,
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

    private func transcribeProvider(
        provider: VoiceInkProviderKind,
        modelProvider: ModelProvider,
        audioData: Data,
        fileName: String,
        apiKey: String,
        modelName: String,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        do {
            let text = try await VoiceInkRemoteTranscriptionService(provider: provider).transcribeAudioData(
                apiKey: apiKey,
                model: modelName,
                audioData: audioData,
                fileName: fileName,
                language: language,
                options: modelProvider.remoteTranscriptionOptions(
                    prompt: prompt,
                    customVocabulary: customVocabulary
                )
            )
            guard modelProvider.acceptsRemoteTranscriptionText(text) else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            if let apiError = CloudTranscriptionError.apiRequestFailure(
                from: error as NSError,
                matchingErrorDomain: modelProvider.apiErrorDomain
            ) {
                throw apiError
            }
            throw error
        }
    }
}
