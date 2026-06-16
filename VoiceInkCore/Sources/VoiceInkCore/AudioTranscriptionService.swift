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

    public init(
        provider: VoiceInkProviderKind,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient()
    ) {
        self.init(
            transport: provider.transcriptionTransport,
            apiBaseURL: provider.apiBaseURL,
            openAICompatibleClient: openAICompatibleClient,
            deepgramClient: deepgramClient
        )
    }

    public init(
        transport: VoiceInkTranscriptionTransport,
        apiBaseURL: URL,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient()
    ) {
        self.transport = transport
        self.apiBaseURL = apiBaseURL
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
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
        case .localWhisper:
            return false
        }
    }
}
