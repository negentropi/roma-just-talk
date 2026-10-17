import Foundation
import LLMkit
import RomaCore

/// Protocol for streaming transcription providers.
protocol StreamingTranscriptionProvider: AnyObject {
    /// Associates provider-internal diagnostic events with one recording lifecycle.
    func setLatencyTraceToken(_ token: RomaLatencyTrace.Token?)

    /// Connect to the streaming transcription endpoint
    func connect(model: any TranscriptionModel, language: String?) async throws

    /// Send a chunk of raw PCM audio data (16-bit, 16kHz, mono, little-endian)
    func sendAudioChunk(_ data: Data) async throws

    /// Commit the current audio buffer to finalize transcription
    func commit() async throws

    /// Disconnect from the streaming endpoint
    func disconnect() async

    /// Stream of transcription events from the provider
    var transcriptionEvents: AsyncStream<RomaStreamingTranscriptionEvent> { get }
}

extension StreamingTranscriptionProvider {
    func setLatencyTraceToken(_ token: RomaLatencyTrace.Token?) {}

    func apiKey(for model: any TranscriptionModel) throws -> String {
        guard let apiKey = RomaProviderCredential.nonBlank(
            APIKeyManager.shared.getAPIKey(forProvider: model.provider.apiKeyProviderName)
        ) else {
            throw RomaStreamingTranscriptionError.missingAPIKey
        }
        return apiKey
    }

    func mapStreamingError(
        _ error: Error,
        treatsTimeoutAsStreamingTimeout: Bool = false
    ) -> Error {
        guard let llmError = error as? LLMKitError else { return error }

        switch llmError {
        case .missingAPIKey:
            return RomaStreamingTranscriptionError.missingAPIKey
        case .httpError(_, let message):
            return RomaStreamingTranscriptionError.serverError(message)
        case .networkError(let detail):
            return RomaStreamingTranscriptionError.connectionFailed(detail)
        case .timeout where treatsTimeoutAsStreamingTimeout:
            return RomaStreamingTranscriptionError.timeout
        default:
            return RomaStreamingTranscriptionError.serverError(
                llmError.localizedDescription ?? RomaStreamingTranscriptionError.unknownServerErrorMessage
            )
        }
    }

    func forwardLLMKitStreamingEvents(
        from client: any LLMKitStreamingEventSource,
        to continuation: AsyncStream<RomaStreamingTranscriptionEvent>.Continuation?
    ) -> Task<Void, Never> {
        Task {
            for await event in client.transcriptionEvents {
                continuation?.yield(RomaStreamingTranscriptionEvent(llmKitEvent: event))
            }
        }
    }
}

protocol LLMKitStreamingEventSource {
    var transcriptionEvents: AsyncStream<LLMkit.StreamingTranscriptionEvent> { get }
}

extension LLMkit.AssemblyAIStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.CartesiaStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.DeepgramStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.ElevenLabsStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.MistralStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.SonioxStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.SpeechmaticsStreamingClient: LLMKitStreamingEventSource {}
extension LLMkit.XAIStreamingClient: LLMKitStreamingEventSource {}

private extension RomaStreamingTranscriptionEvent {
    init(llmKitEvent event: LLMkit.StreamingTranscriptionEvent) {
        switch event {
        case .sessionStarted:
            self = .sessionStarted
        case .partial(let text):
            self = .partial(text: text)
        case .committed(let text):
            self = .committed(text: text)
        case .error(let message):
            self = .error(RomaStreamingTranscriptionError.serverError(message))
        }
    }
}
