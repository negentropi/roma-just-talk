import SwiftData
import VoiceInkCore

protocol CloudProvider {
    var modelProvider: VoiceInkMacOSTranscriptionModelProvider { get }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)?
}

struct CoreCloudProvider: CloudProvider {
    let modelProvider: VoiceInkMacOSTranscriptionModelProvider
    private let streamingProviderFactory: ((ModelContext) -> (any StreamingTranscriptionProvider)?)?

    init(
        modelProvider: VoiceInkMacOSTranscriptionModelProvider,
        streamingProviderFactory: ((ModelContext) -> (any StreamingTranscriptionProvider)?)? = nil
    ) {
        self.modelProvider = modelProvider
        self.streamingProviderFactory = streamingProviderFactory
    }

    func makeStreamingProvider(modelContext: ModelContext) -> (any StreamingTranscriptionProvider)? {
        streamingProviderFactory?(modelContext)
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

    static func provider(for modelProvider: VoiceInkMacOSTranscriptionModelProvider) -> (any CloudProvider)? {
        allProviders.first { $0.modelProvider == modelProvider }
    }
}
