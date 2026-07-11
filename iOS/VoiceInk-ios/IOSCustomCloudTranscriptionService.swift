import Foundation
import VoiceInkCore

struct IOSCustomCloudTranscriptionService: VoiceInkAudioTranscriptionService {
    typealias Transcribe = (
        VoiceInkCustomCloudModelStoredRecord,
        String,
        Data,
        String,
        String?,
        String?
    ) async throws -> String

    private let modelsByName: [String: VoiceInkCustomCloudModelStoredRecord]
    private let loadAPIKey: (UUID) -> String?
    private let transcribe: Transcribe

    init(
        models: [VoiceInkCustomCloudModelStoredRecord],
        loadAPIKey: @escaping (UUID) -> String? = {
            VoiceInkKeychainValueStore.loadString(
                account: VoiceInkProviderAPIKeyAccount.customModelAccountIdentifier(forModelId: $0)
            ).value
        },
        transcribe: @escaping Transcribe = { model, apiKey, audioData, fileName, language, prompt in
            try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
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
            throw VoiceInkCloudTranscriptionError.unsupportedProvider
        }
        guard let apiKey = VoiceInkProviderCredential.nonBlank(loadAPIKey(model.id)) else {
            throw VoiceInkCloudTranscriptionError.missingAPIKey
        }

        let audioFile = try VoiceInkCloudTranscriptionAudioFile.load(from: fileURL)
        return try await transcribe(
            model,
            apiKey,
            audioFile.data,
            audioFile.fileName,
            VoiceInkTranscriptionLanguageSupport.requestLanguage(language),
            prompt
        )
    }
}
