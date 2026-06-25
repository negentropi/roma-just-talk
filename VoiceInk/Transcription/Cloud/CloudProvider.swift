import Foundation
import SwiftData
import VoiceInkCore

protocol CloudProvider {
    var modelProvider: ModelProvider { get }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)?
}

struct CoreCloudProvider: CloudProvider {
    let modelProvider: ModelProvider
    private let streamingProviderFactory: ((ModelContext) -> (any StreamingTranscriptionProvider)?)?

    init(
        modelProvider: ModelProvider,
        streamingProviderFactory: ((ModelContext) -> (any StreamingTranscriptionProvider)?)? = nil
    ) {
        self.modelProvider = modelProvider
        self.streamingProviderFactory = streamingProviderFactory
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        streamingProviderFactory?(modelContext)
    }
}

private extension VoiceInkCloudTranscriptionModelSpec {
    func makeCloudModel(provider: ModelProvider) -> CloudModel {
        CloudModel(
            name: name,
            displayName: displayName,
            description: description,
            provider: provider,
            speed: speed,
            accuracy: accuracy,
            isMultilingual: isMultilingual,
            supportsStreaming: supportsStreaming,
            supportedLanguages: provider.supportedLanguages(isMultilingual: isMultilingual)
        )
    }
}

extension CloudProvider {
    private var apiErrorDomain: String? {
        modelProvider.apiErrorDomain
    }

    private func remoteTranscriptionOptions(
        prompt: String?,
        customVocabulary: [String]
    ) -> VoiceInkRemoteTranscriptionOptions {
        modelProvider.remoteTranscriptionOptions(
            prompt: prompt,
            customVocabulary: customVocabulary
        )
    }

    var models: [CloudModel] {
        modelProvider
            .cloudModelSpecs
            .map { $0.makeCloudModel(provider: modelProvider) }
    }

    /// Streaming-only providers inherit this and get a clear error if batch is somehow attempted.
    /// Batch providers share the core remote dispatch while this shell keeps SwiftData and streaming adapters.
    func transcribe(audioData: Data, fileName: String, apiKey: String, model: String, language: String?, prompt: String?, customVocabulary: [String]) async throws -> String {
        guard let provider = modelProvider.remoteTranscriptionProviderKind else {
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
            guard modelProvider.acceptsRemoteTranscriptionText(text) else {
                throw CloudTranscriptionError.noTranscriptionReturned
            }
            return text
        } catch let error as CloudTranscriptionError {
            throw error
        } catch {
            if let apiError = CloudTranscriptionError.apiRequestFailure(
                from: error as NSError,
                matchingErrorDomain: apiErrorDomain
            ) {
                throw apiError
            }
            throw error
        }
    }

}

enum CloudProviderRegistry {
    static let allProviders: [any CloudProvider] = [
        CoreCloudProvider(modelProvider: .groq),
        CoreCloudProvider(modelProvider: .elevenLabs) { _ in ElevenLabsStreamingProvider() },
        CoreCloudProvider(modelProvider: .deepgram) { DeepgramStreamingProvider(modelContext: $0) },
        CoreCloudProvider(modelProvider: .mistral) { _ in MistralStreamingProvider() },
        CoreCloudProvider(modelProvider: .gemini),
        CoreCloudProvider(modelProvider: .soniox) { SonioxStreamingProvider(modelContext: $0) },
        CoreCloudProvider(modelProvider: .speechmatics) { SpeechmaticsStreamingProvider(modelContext: $0) },
        CoreCloudProvider(modelProvider: .assemblyAI) { AssemblyAIStreamingProvider(modelContext: $0) },
        CoreCloudProvider(modelProvider: .xai) { _ in XAIStreamingProvider() },
        CoreCloudProvider(modelProvider: .cartesia) { CartesiaStreamingProvider(modelContext: $0) }
    ]

    static func provider(for modelProvider: ModelProvider) -> (any CloudProvider)? {
        allProviders.first { $0.modelProvider == modelProvider }
    }
}
