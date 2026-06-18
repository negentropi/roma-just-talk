import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

/// Soniox streaming provider wrapping `LLMkit.SonioxStreamingClient`.
final class SonioxStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.SonioxStreamingClient()
    private var eventsContinuation: AsyncStream<VoiceInkStreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private let modelContext: ModelContext

    private(set) var transcriptionEvents: AsyncStream<VoiceInkStreamingTranscriptionEvent>

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

        let vocabulary = CustomVocabularyService.shared.getCustomVocabularyTerms(from: modelContext)

        // Cancel any existing forwarding task before starting a new one
        forwardingTask?.cancel()
        forwardingTask = forwardLLMKitStreamingEvents(from: client, to: eventsContinuation)

        do {
            try await client.connect(apiKey: apiKey, model: "stt-rt-v4", language: language, customVocabulary: vocabulary)
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
