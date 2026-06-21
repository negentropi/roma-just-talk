import Foundation
import SwiftData
import VoiceInkCore

enum CloudTranscriptionError: Error, LocalizedError {
    case unsupportedProvider
    case missingAPIKey
    case audioFileNotFound
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return VoiceInkTranscriptionRunError.noTranscriptionReturned.errorDescription
        }
    }
}

class CloudTranscriptionService: TranscriptionService {
    private let modelContext: ModelContext
    private let openAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient()

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
                return try await transcribeCustomModel(
                    audioData: audioData,
                    fileName: fileName,
                    model: customModel,
                    language: language,
                    prompt: prompt
                )
            }

            guard let cloudProvider = CloudProviderRegistry.provider(for: model.provider) else {
                throw CloudTranscriptionError.unsupportedProvider
            }
            let apiKey = try requireAPIKey(forProvider: model.provider.apiKeyProviderName)
            return try await cloudProvider.transcribe(
                audioData: audioData,
                fileName: fileName,
                apiKey: apiKey,
                model: model.name,
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

    private func transcribeCustomModel(
        audioData: Data,
        fileName: String,
        model: CustomCloudModel,
        language: String?,
        prompt: String?
    ) async throws -> String {
        guard let url = VoiceInkCustomCloudTranscriptionPolicy.endpointURL(from: model.apiEndpoint) else {
            throw NSError(
                domain: VoiceInkCustomCloudTranscriptionPolicy.apiErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: VoiceInkCustomCloudTranscriptionPolicy.invalidEndpointDescription]
            )
        }
        let options = VoiceInkCustomCloudTranscriptionPolicy.openAICompatibleOptions

        do {
            let text = try await openAICompatibleTranscriptionClient.transcribeAudioData(
                url: url,
                apiKey: model.apiKey,
                model: model.modelName,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: prompt,
                responseFormat: options.openAICompatibleResponseFormat,
                temperature: options.openAICompatibleTemperature,
                errorDomain: options.openAICompatibleErrorDomain,
                allowPlainTextFallback: options.openAICompatibleAllowsPlainTextFallback
            )
            guard VoiceInkCustomCloudTranscriptionPolicy.acceptsTranscriptionText(text) else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError
            where VoiceInkCustomCloudTranscriptionPolicy.isHTTPAPIError(error) {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }
}
