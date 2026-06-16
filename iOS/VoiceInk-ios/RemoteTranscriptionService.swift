import Foundation
import VoiceInkCore

protocol TranscriptionService {
    func transcribeAudioFile(
        apiBaseURL: URL,
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?
    ) async throws -> String

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool
}

struct RemoteTranscriptionService: TranscriptionService {
    private let transport: VoiceInkTranscriptionTransport
    private let openAICompatibleClient = VoiceInkOpenAICompatibleTranscriptionClient()
    private let deepgramClient = VoiceInkDeepgramTranscriptionClient()

    init(transport: VoiceInkTranscriptionTransport) {
        self.transport = transport
    }

    func transcribeAudioFile(
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

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
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
