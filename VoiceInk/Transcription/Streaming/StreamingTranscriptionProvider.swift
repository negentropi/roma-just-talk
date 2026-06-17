import Foundation
import VoiceInkCore

/// Events emitted by a streaming transcription provider
enum StreamingTranscriptionEvent {
    case sessionStarted
    case partial(text: String)
    case committed(text: String)
    case error(Error)
}

/// Errors specific to streaming transcription
enum StreamingTranscriptionError: LocalizedError {
    case missingAPIKey
    case connectionFailed(String)
    case timeout
    case serverError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured for streaming transcription"
        case .connectionFailed(let message):
            return "Streaming connection failed: \(message)"
        case .timeout:
            return "Streaming transcription timed out waiting for final result"
        case .serverError(let message):
            return "Streaming server error: \(message)"
        case .notConnected:
            return "Not connected to streaming transcription service"
        }
    }
}

enum StreamingFinalCommitTimeout {
    static let cloudNanoseconds: UInt64 = 10_000_000_000
    static let localFluidAudioNanoseconds: UInt64 = 1_000_000_000

    static func nanoseconds(for provider: ModelProvider) -> UInt64 {
        provider == .fluidAudio ? localFluidAudioNanoseconds : cloudNanoseconds
    }
}

/// Protocol for streaming transcription providers.
protocol StreamingTranscriptionProvider: AnyObject {
    /// Connect to the streaming transcription endpoint
    func connect(model: any TranscriptionModel, language: String?) async throws

    /// Send a chunk of raw PCM audio data (16-bit, 16kHz, mono, little-endian)
    func sendAudioChunk(_ data: Data) async throws

    /// Commit the current audio buffer to finalize transcription
    func commit() async throws

    /// Disconnect from the streaming endpoint
    func disconnect() async

    /// Stream of transcription events from the provider
    var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent> { get }
}

extension StreamingTranscriptionProvider {
    func apiKey(for model: any TranscriptionModel) throws -> String {
        guard let apiKey = VoiceInkProviderCredential.nonBlank(
            APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName)
        ) else {
            throw StreamingTranscriptionError.missingAPIKey
        }
        return apiKey
    }
}
