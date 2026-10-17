import Foundation
import SwiftData
import RomaCore

class CloudTranscriptionService: TranscriptionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let audioFile = try RomaCloudTranscriptionAudioFile.load(from: audioURL)
        let language = RomaTranscriptionLanguagePreference.requestLanguage(for: model.transcriptionLanguageSelectionFacts)
        let prompt = RomaTranscriptionPromptPreference.requestPrompt(
            forEffectiveLanguage: RomaTranscriptionLanguagePreference.effectiveLanguage(for: model.transcriptionLanguageSelectionFacts)
        )

        if model.provider == .custom {
            guard let customModel = model as? CustomCloudModel else {
                throw RomaCloudTranscriptionError.unsupportedProvider
            }
            return try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: customModel.apiEndpoint,
                apiKey: customModel.apiKey,
                model: customModel.modelName,
                audioData: audioFile.data,
                fileName: audioFile.fileName,
                language: language,
                prompt: prompt
            )
        }

        let modelProvider = model.provider
        return try await RomaMacOSCloudTranscriptionPolicy.transcribeAudioData(
            modelProvider: modelProvider,
            apiKey: APIKeyManager.shared.getAPIKey(forProvider: modelProvider.apiKeyProviderName),
            modelName: model.name,
            audioData: audioFile.data,
            fileName: audioFile.fileName,
            language: language,
            prompt: prompt,
            customVocabulary: CustomVocabularyService.shared.rawCustomVocabularyTerms(from: modelContext)
        )
    }
}
