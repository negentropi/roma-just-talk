import Foundation

public protocol VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiBaseURL: URL,
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?
    ) async throws -> String

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool
}

public struct VoiceInkRemoteTranscriptionService: VoiceInkAudioTranscriptionService, Sendable {
    private let transport: VoiceInkTranscriptionTransport
    private let openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient
    private let deepgramClient: VoiceInkDeepgramTranscriptionClient

    public init(
        transport: VoiceInkTranscriptionTransport,
        openAICompatibleClient: VoiceInkOpenAICompatibleTranscriptionClient = VoiceInkOpenAICompatibleTranscriptionClient(),
        deepgramClient: VoiceInkDeepgramTranscriptionClient = VoiceInkDeepgramTranscriptionClient()
    ) {
        self.transport = transport
        self.openAICompatibleClient = openAICompatibleClient
        self.deepgramClient = deepgramClient
    }

    public func transcribeAudioFile(
        apiBaseURL: URL,
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

    public func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
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
