import Foundation
import SwiftData
import LLMkit
import VoiceInkCore

/// AssemblyAI streaming provider wrapping `LLMkit.AssemblyAIStreamingClient`.
final class AssemblyAIStreamingProvider: StreamingTranscriptionProvider {

    private let client = LLMkit.AssemblyAIStreamingClient()
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

        forwardingTask?.cancel()
        forwardingTask = forwardLLMKitStreamingEvents(from: client, to: eventsContinuation)

        do {
            try await client.connect(
                apiKey: apiKey,
                model: model.streamingConnectionModelName,
                language: language,
                prompt: VoiceInkTranscriptionPromptUse.streamingTranscription(.assemblyAI).requestPrompt(
                    VoiceInkTranscriptionPromptPreference.requestPrompt()
                ),
                customVocabulary: CustomVocabularyService.shared.getCustomVocabularyTerms(
                    from: modelContext,
                    for: .streamingTranscription(.assemblyAI)
                )
            )
        } catch {
            forwardingTask?.cancel()
            forwardingTask = nil
            throw mapStreamingError(error, treatsTimeoutAsStreamingTimeout: true)
        }
    }

    func sendAudioChunk(_ data: Data) async throws {
        do {
            try await client.sendAudioChunk(data)
        } catch {
            throw mapStreamingError(error, treatsTimeoutAsStreamingTimeout: true)
        }
    }

    func commit() async throws {
        do {
            try await client.commit()
        } catch {
            throw mapStreamingError(error, treatsTimeoutAsStreamingTimeout: true)
        }
    }

    func disconnect() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        await client.disconnect()
        eventsContinuation?.finish()
    }

}
