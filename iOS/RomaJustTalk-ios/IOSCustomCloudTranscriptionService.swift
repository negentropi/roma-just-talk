import Foundation
import RomaCore

struct IOSCustomCloudTranscriptionService: RomaAudioTranscriptionService {
    typealias Transcribe = (
        RomaCustomCloudModelStoredRecord,
        String,
        Data,
        String,
        String?,
        String?
    ) async throws -> String

    private let modelsByName: [String: RomaCustomCloudModelStoredRecord]
    private let loadAPIKey: (UUID) -> String?
    private let transcribe: Transcribe

    init(
        models: [RomaCustomCloudModelStoredRecord],
        loadAPIKey: @escaping (UUID) -> String? = {
            RomaKeychainValueStore.loadString(
                account: RomaProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: $0)
            ).value
        },
        transcribe: @escaping Transcribe = { model, apiKey, audioData, fileName, language, prompt in
            try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: model.apiEndpoint,
                apiKey: apiKey,
                model: model.modelName,
                audioData: audioData,
                fileName: fileName,
                language: language,
                prompt: prompt
            )
        }
    ) {
        self.modelsByName = models.reduce(into: [:]) { result, model in
            result[model.name] = model
        }
        self.loadAPIKey = loadAPIKey
        self.transcribe = transcribe
    }

    func transcribeAudioFile(
        apiKey _: String,
        model selectedModelName: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary _: [String]
    ) async throws -> String {
        guard let model = modelsByName[selectedModelName] else {
            throw RomaCloudTranscriptionError.unsupportedProvider
        }
        guard let apiKey = RomaProviderCredential.nonBlank(loadAPIKey(model.id)) else {
            throw RomaCloudTranscriptionError.missingAPIKey
        }

        let audioFile = try RomaCloudTranscriptionAudioFile.load(from: fileURL)
        return try await transcribe(
            model,
            apiKey,
            audioFile.data,
            audioFile.fileName,
            RomaTranscriptionLanguageSupport.requestLanguage(language),
            prompt
        )
    }
}
