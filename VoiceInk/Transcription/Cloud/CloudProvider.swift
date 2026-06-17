import Foundation
import SwiftData
import VoiceInkCore

protocol CloudProvider {
    var modelProvider: ModelProvider { get }
    var languageCodes: [String]? { get }
    var includesAutoDetect: Bool { get }
    var models: [CloudModel] { get }
    /// True when the provider has no batch HTTP endpoint and requires streaming for all transcription.
    var isStreamingOnly: Bool { get }

    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String
    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)?
    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?)
}

extension CloudProvider {
    private var apiErrorDomain: String? {
        switch modelProvider {
        case .groq:
            return "GroqAPI"
        case .deepgram:
            return "DeepgramAPI"
        case .gemini:
            return "GeminiAPI"
        case .mistral:
            return "MistralAPI"
        case .elevenLabs:
            return "ElevenLabsAPI"
        case .soniox:
            return "SonioxAPI"
        case .speechmatics:
            return "SpeechmaticsAPI"
        case .assemblyAI:
            return "AssemblyAIAPI"
        case .xai:
            return "XAIAPI"
        default:
            return nil
        }
    }

    private func remoteTranscriptionOptions(
        prompt: String?,
        customVocabulary: [String]
    ) -> VoiceInkRemoteTranscriptionOptions {
        switch modelProvider {
        case .groq:
            return VoiceInkRemoteTranscriptionOptions(
                prompt: prompt,
                openAICompatibleResponseFormat: "json",
                openAICompatibleTemperature: "0",
                openAICompatibleErrorDomain: "GroqAPI",
                openAICompatibleTimeout: 60,
                openAICompatibleMaxRetries: 2
            )
        case .deepgram:
            return VoiceInkRemoteTranscriptionOptions(
                deepgramParagraphs: true,
                deepgramDiarize: nil,
                deepgramTimeout: 30
            )
        case .soniox, .speechmatics:
            return VoiceInkRemoteTranscriptionOptions(customVocabulary: customVocabulary)
        case .assemblyAI:
            return VoiceInkRemoteTranscriptionOptions(
                prompt: prompt,
                customVocabulary: customVocabulary
            )
        default:
            return VoiceInkRemoteTranscriptionOptions()
        }
    }

    var languageCodes: [String]? {
        modelProvider.coreTranscriptionModelProvider?.languageCodes
    }

    var models: [CloudModel] {
        guard let provider = modelProvider.coreTranscriptionModelProvider else {
            return []
        }

        return VoiceInkTranscriptionModelCatalog
            .cloudModels(for: provider)
            .map { $0.makeCloudModel(provider: modelProvider) }
    }

    var includesAutoDetect: Bool {
        modelProvider.coreTranscriptionModelProvider?.includesAutoDetect ?? false
    }

    var isStreamingOnly: Bool {
        guard let provider = modelProvider.coreTranscriptionModelProvider else {
            return false
        }
        return !provider.supportsRecordedFileTranscription
    }

    /// Streaming-only providers inherit this and get a clear error if batch is somehow attempted.
    /// Batch providers share the core remote dispatch while this shell keeps SwiftData and streaming adapters.
    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        guard let provider = modelProvider.coreTranscriptionModelProvider?.providerKind else {
            throw CloudTranscriptionError.unsupportedProvider
        }

        do {
            let text = try await VoiceInkRemoteTranscriptionService(provider: provider).transcribeAudioData(
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileName,
                language: language,
                options: remoteTranscriptionOptions(
                    prompt: prompt,
                    customVocabulary: customVocabulary
                )
            )
            guard provider.transcriptionEmptyTextPolicy.accepts(text) else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch let error as NSError
            where apiErrorDomain == error.domain && (100...599).contains(error.code) {
            throw CloudTranscriptionError.apiRequestFailed(
                statusCode: error.code,
                message: error.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            )
        }
    }

    func verifyAPIKey(_ key: String) async -> (isValid: Bool, errorMessage: String?) {
        guard let provider = modelProvider.coreTranscriptionModelProvider else {
            return (false, "Unsupported provider")
        }

        let result = await VoiceInkProviderAPIKeyVerifier().verifyAPIKeyDetailed(key, for: provider)
        return (result.isValid, result.errorMessage)
    }
}

enum CloudProviderRegistry {
    static let allProviders: [any CloudProvider] = [
        GroqProvider(),
        ElevenLabsProvider(),
        DeepgramProvider(),
        MistralProvider(),
        GeminiProvider(),
        SonioxProvider(),
        SpeechmaticsProvider(),
        AssemblyAIProvider(),
        XAIProvider(),
        CartesiaProvider()
    ]

    static func provider(for modelProvider: ModelProvider) -> (any CloudProvider)? {
        allProviders.first { $0.modelProvider == modelProvider }
    }
}
