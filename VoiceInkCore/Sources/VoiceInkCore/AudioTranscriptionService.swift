import Foundation

public protocol VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?
    ) async throws -> String

    func verifyAPIKey(_ apiKey: String) async -> Bool
}

public struct VoiceInkRemoteTranscriptionService: VoiceInkAudioTranscriptionService, Sendable {
    private let transport: VoiceInkTranscriptionTransport
    private let apiBaseURL: URL
    private let openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient
    private let deepgramClient: VoiceInkDeepgramTranscriptionClient
    private let geminiClient: VoiceInkGeminiTranscriptionClient
    private let mistralClient: VoiceInkMistralTranscriptionClient
    private let elevenLabsClient: VoiceInkElevenLabsTranscriptionClient
    private let sonioxClient: VoiceInkSonioxTranscriptionClient
    private let speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient
    private let assemblyAIClient: VoiceInkAssemblyAITranscriptionClient
    private let xaiClient: VoiceInkXAITranscriptionClient

    public init(
        provider: VoiceInkProviderKind,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.init(
            transport: provider.transcriptionTransport,
            apiBaseURL: provider.transcriptionAPIBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient,
            geminiClient: geminiClient,
            mistralClient: mistralClient,
            elevenLabsClient: elevenLabsClient,
            sonioxClient: sonioxClient,
            speechmaticsClient: speechmaticsClient,
            assemblyAIClient: assemblyAIClient,
            xaiClient: xaiClient
        )
    }

    public init(
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient(),
        geminiClient: VoiceInkGeminiTranscriptionClient = VoiceInkGeminiTranscriptionClient(),
        mistralClient: VoiceInkMistralTranscriptionClient = VoiceInkMistralTranscriptionClient(),
        elevenLabsClient: VoiceInkElevenLabsTranscriptionClient = VoiceInkElevenLabsTranscriptionClient(),
        sonioxClient: VoiceInkSonioxTranscriptionClient = VoiceInkSonioxTranscriptionClient(),
        speechmaticsClient: VoiceInkSpeechmaticsTranscriptionClient = VoiceInkSpeechmaticsTranscriptionClient(),
        assemblyAIClient: VoiceInkAssemblyAITranscriptionClient = VoiceInkAssemblyAITranscriptionClient(),
        xaiClient: VoiceInkXAITranscriptionClient = VoiceInkXAITranscriptionClient()
    ) {
        self.transport = transport
        self.apiBaseURL = apiBaseURL
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
        self.geminiClient = geminiClient
        self.mistralClient = mistralClient
        self.elevenLabsClient = elevenLabsClient
        self.sonioxClient = sonioxClient
        self.speechmaticsClient = speechmaticsClient
        self.assemblyAIClient = assemblyAIClient
        self.xaiClient = xaiClient
    }

    public func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil
    ) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)

        switch transport {
        case .openAICompatible:
            return try await openAICompatibleClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileURL.lastPathComponent,
                language: language,
                errorDomain: "GroqAPI"
            )
        case .deepgram:
            return try await deepgramClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language
            )
        case .geminiGenerateContent:
            return try await geminiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData
            )
        case .mistral:
            return try await mistralClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileURL.lastPathComponent
            )
        case .elevenLabs:
            return try await elevenLabsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileURL.lastPathComponent,
                language: language
            )
        case .soniox:
            return try await sonioxClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                fileName: fileURL.lastPathComponent,
                language: language
            )
        case .speechmatics:
            return try await speechmaticsClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileURL.lastPathComponent,
                language: language
            )
        case .assemblyAI:
            return try await assemblyAIClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                model: model,
                audioData: audioData,
                language: language
            )
        case .xai:
            return try await xaiClient.transcribeAudioData(
                baseURL: apiBaseURL,
                apiKey: apiKey,
                audioData: audioData,
                fileName: fileURL.lastPathComponent,
                language: language,
                format: true
            )
        case .localWhisper:
            throw URLError(.unsupportedURL)
        }
    }

    public func verifyAPIKey(_ apiKey: String) async -> Bool {
        switch transport {
        case .openAICompatible:
            return await openAICompatibleClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .deepgram:
            return await deepgramClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .geminiGenerateContent:
            return await geminiClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .mistral:
            return await mistralClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .elevenLabs:
            return await elevenLabsClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .soniox:
            return await sonioxClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .speechmatics:
            return await speechmaticsClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .assemblyAI:
            return await assemblyAIClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .xai:
            return await xaiClient.verifyAPIKey(
                baseURL: apiBaseURL,
                apiKey: apiKey
            )
        case .localWhisper:
            return false
        }
    }
}
