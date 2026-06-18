import Foundation
import LLMkit
import VoiceInkCore

/// ElevenLabs streaming provider wrapping `LLMkit.ElevenLabsStreamingClient`.
final class ElevenLabsStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.ElevenLabsStreamingClient()
    private var eventsContinuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?

    private(set) var transcriptionEvents: AsyncStream<VoiceInkStreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let apiKey = try apiKey(for: model)

        // Cancel any existing forwarding task before starting a new one
        forwardingTask?.cancel()
        forwardingTask = forwardLLMKitStreamingEvents(from: client, to: eventsContinuation)

        do {
            try await client.connect(apiKey: apiKey, model: "scribe_v2_realtime", language: language)
        } catch {
            // Clean up forwarding task on connection failure
            forwardingTask?.cancel()
            forwardingTask = nil
            throw mapStreamingError(error)
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        do {
            try await client.sendAudioChunk(data)
        } catch {
            throw mapStreamingError(error)
        }
    }

    func commit() async throws {
        do {
            try await client.commit()
        } catch {
            throw mapStreamingError(error)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
    }

}
