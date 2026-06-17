import Foundation
import SwiftData
import VoiceInkCore

enum CloudTranscriptionError: Error, LocalizedError {
    case unsupportedProvider
    case missingAPIKey
    case invalidAPIKey
    case audioFileNotFound
    case apiRequestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case noTranscriptionReturned
    case dataEncodingError

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The model provider is not supported by this service."
        case .missingAPIKey:
            return "API key for this service is missing. Please configure it in the settings."
        case .invalidAPIKey:
            return "The provided API key is invalid."
        case .audioFileNotFound:
            return "The audio file to transcribe could not be found."
        case .apiRequestFailed(let statusCode, let message):
            return "The API request failed with status code \(statusCode): \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .noTranscriptionReturned:
            return "The API returned an empty or invalid response."
        case .dataEncodingError:
            return "Failed to encode the request body."
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
        let language = selectedLanguage()

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
                    prompt: transcriptionPrompt()
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
                prompt: transcriptionPrompt(),
                customVocabulary: getCustomDictionaryTerms()
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
        guard let apiKey = APIKeyManager.shared.getAPIKey(forProvider: provider), !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }
        return apiKey
    }

    private func selectedLanguage() -> String? {
        let lang = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        return (lang == "auto" || lang.isEmpty) ? nil : lang
    }

    private func transcriptionPrompt() -> String? {
        let prompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
        return prompt.isEmpty ? nil : prompt
    }

    private func getCustomDictionaryTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }
        return VoiceInkCustomVocabularyTerms.normalized(vocabularyWords.map(\.word))
    }

    private func transcribeCustomModel(
        audioData: Data,
        fileName: String,
        model: CustomCloudModel,
        language: String?,
        prompt: String?
    ) async throws -> String {
        guard let url = URL(string: model.apiEndpoint) else {
            throw NSError(
                domain: "CustomWhisperTranscriptionService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"]
            )
        }

        do {
            let text = try await openAICompatibleTranscriptionClient.transcribeAudioData(
                url: url,
                apiKey: model.apiKey,
                model: model.modelName,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: prompt,
                responseFormat: "json",
                temperature: "0",
                errorDomain: "CustomWhisperTranscriptionService",
                allowPlainTextFallback: false
            )
            guard !text.isEmpty else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError
            where error.domain == "CustomWhisperTranscriptionService" && (100...599).contains(error.code) {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }
}
