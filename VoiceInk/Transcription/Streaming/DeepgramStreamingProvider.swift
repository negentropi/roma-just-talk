import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

/// Deepgram streaming provider wrapping `LLMkit.DeepgramStreamingClient`.
final class DeepgramStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.DeepgramStreamingClient()
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

        let vocabulary = getCustomVocabularyTerms()

        // Cancel any existing forwarding task before starting a new one
        forwardingTask?.cancel()
        forwardingTask = forwardLLMKitStreamingEvents(from: client, to: eventsContinuation)

        do {
            try await client.connect(apiKey: apiKey, model: model.name, language: language, customVocabulary: vocabulary)
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

    // MARK: - Private

    private func getCustomVocabularyTerms() -> [String] {
        let descriptor = FetchDescriptor<VocabularyWord>(sortBy: [SortDescriptor(\.word)])
        guard let vocabularyWords = try? modelContext.fetch(descriptor) else {
            return []
        }
        return VoiceInkCustomVocabularyTerms.normalized(vocabularyWords.map(\.word), limit: 50)
    }

}
