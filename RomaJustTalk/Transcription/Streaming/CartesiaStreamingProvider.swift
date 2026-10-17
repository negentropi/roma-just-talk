import Foundation
import SwiftData
import LLMkit
import RomaCore

/// Cartesia Ink streaming provider wrapping `LLMkit.CartesiaStreamingClient`.
final class CartesiaStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.CartesiaStreamingClient()
    private var eventsContinuation: AsyncStream<RomaStreamingTranscriptionEvent>.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private let modelContext: ModelContext

    private(set) var transcriptionEvents: AsyncStream<RomaStreamingTranscriptionEvent>

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        var continuation: AsyncStream<RomaStreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        forwardingTask?.cancel()
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        let apiKey = try apiKey(for: model)

        forwardingTask?.cancel()
        forwardingTask = forwardLLMKitStreamingEvents(from: client, to: eventsContinuation)

        do {
            try await client.connect(apiKey: apiKey, model: model.streamingConnectionModelName, language: language, customVocabulary: [])
        } catch {
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
