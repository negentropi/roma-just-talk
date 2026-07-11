import Combine
import Foundation
import LLMkit
import VoiceInkCore

private final class VoiceInkIOSAudioChunkSource: @unchecked Sendable {
    let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    nonisolated init() {
        (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .unbounded
        )
    }

    nonisolated func send(_ data: Data) {
        continuation.yield(data)
    }

    nonisolated func finish() {
        continuation.finish()
    }
}

private final class VoiceInkIOSAudioChunkRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var source: VoiceInkIOSAudioChunkSource?

    nonisolated init() {}

    nonisolated func activate(_ source: VoiceInkIOSAudioChunkSource) {
        lock.lock()
        self.source = source
        lock.unlock()
    }

    nonisolated func deactivate() {
        lock.lock()
        source = nil
        lock.unlock()
    }

    nonisolated func send(_ data: Data) {
        lock.lock()
        let source = source
        lock.unlock()
        source?.send(data)
    }
}

enum VoiceInkIOSStreamingError: LocalizedError {
    case unsupportedProvider(VoiceInkProviderKind)
    case emptyFinalTranscript

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "\(provider.displayName) does not support live transcription on iOS."
        case .emptyFinalTranscript:
            return "Live transcription returned no final text."
        }
    }
}

@MainActor
final class IOSStreamingTranscriptionService: ObservableObject {
    typealias ClientFactory = @MainActor (VoiceInkProviderKind) throws -> any LLMkit.StreamingTranscriptionProvider

    @Published private(set) var partialTranscript = ""

    private let clientFactory: ClientFactory
    private nonisolated let chunkRelay = VoiceInkIOSAudioChunkRelay()
    private var client: (any LLMkit.StreamingTranscriptionProvider)?
    private var chunkSource: VoiceInkIOSAudioChunkSource?
    private var sendTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var commitSignal: AsyncStream<Void>.Continuation?
    private var accumulator = VoiceInkStreamingTranscriptAccumulator()
    private var terminalError: Error?
    private var isCommitting = false

    init(clientFactory: @escaping ClientFactory = IOSStreamingTranscriptionService.makeClient) {
        self.clientFactory = clientFactory
    }

    func start(
        request: VoiceInkLiveTranscriptionRequest,
        apiKey: String,
        language: String?,
        customVocabulary: [String]
    ) async throws {
        cancel()
        let client = try clientFactory(request.provider)
        let source = VoiceInkIOSAudioChunkSource()
        self.client = client
        self.chunkSource = source
        chunkRelay.activate(source)
        accumulator.reset()
        terminalError = nil
        partialTranscript = ""
        isCommitting = false

        startEventConsumer(client.transcriptionEvents)
        do {
            try await client.connect(
                apiKey: apiKey,
                model: request.connectionModel,
                language: VoiceInkTranscriptionLanguageSupport.requestLanguage(language),
                customVocabulary: customVocabulary
            )
        } catch {
            cancel()
            throw error
        }

        sendTask = Task.detached { [weak self, client] in
            for await chunk in source.stream {
                do {
                    try await client.sendAudioChunk(chunk)
                } catch {
                    await MainActor.run {
                        self?.recordTerminalError(error)
                    }
                    break
                }
            }
        }
    }

    nonisolated func sendAudioChunk(_ data: Data) {
        chunkRelay.send(data)
    }

    func stopAndGetFinalText(
        timeoutNanoseconds: UInt64 = VoiceInkStreamingFinalCommitTimeout.cloudNanoseconds
    ) async throws -> String {
        try Task.checkCancellation()
        guard let client, let chunkSource else {
            throw VoiceInkStreamingTranscriptionError.notConnected
        }

        isCommitting = true
        chunkSource.finish()
        await sendTask?.value
        sendTask = nil

        let (signalStream, continuation) = AsyncStream.makeStream(of: Void.self)
        commitSignal = continuation
        do {
            try await client.commit()
            try Task.checkCancellation()
        } catch {
            await cleanup()
            throw error
        }

        await waitForCommit(signalStream, timeoutNanoseconds: timeoutNanoseconds)
        do {
            try Task.checkCancellation()
        } catch {
            await cleanup()
            throw error
        }
        if let terminalError {
            await cleanup()
            throw terminalError
        }

        let finalText = accumulator.committedText
        await cleanup()
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceInkIOSStreamingError.emptyFinalTranscript
        }
        return finalText
    }

    func cancel() {
        let client = self.client
        self.client = nil
        chunkSource?.finish()
        chunkSource = nil
        chunkRelay.deactivate()
        sendTask?.cancel()
        sendTask = nil
        eventTask?.cancel()
        eventTask = nil
        commitSignal?.finish()
        commitSignal = nil
        accumulator.reset()
        terminalError = nil
        partialTranscript = ""
        isCommitting = false

        Task {
            await client?.disconnect()
        }
    }

    private func startEventConsumer(
        _ events: AsyncStream<LLMkit.StreamingTranscriptionEvent>
    ) {
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .sessionStarted:
                    break
                case .partial(let text):
                    if !isCommitting {
                        partialTranscript = accumulator.preview(partialText: text)
                    }
                case .committed(let text):
                    _ = accumulator.appendCommitted(text)
                    partialTranscript = accumulator.committedText
                    if isCommitting {
                        commitSignal?.yield()
                    }
                case .error(let message):
                    recordTerminalError(
                        VoiceInkStreamingTranscriptionError.serverError(message)
                    )
                }
            }
        }
    }

    private func recordTerminalError(_ error: Error) {
        guard terminalError == nil else { return }
        terminalError = error
        chunkRelay.deactivate()
        commitSignal?.yield()
    }

    private func waitForCommit(
        _ signalStream: AsyncStream<Void>,
        timeoutNanoseconds: UInt64
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in signalStream { return }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            await group.next()
            group.cancelAll()
        }
        commitSignal?.finish()
        commitSignal = nil
    }

    private func cleanup() async {
        let client = self.client
        self.client = nil
        chunkSource?.finish()
        chunkSource = nil
        chunkRelay.deactivate()
        sendTask?.cancel()
        sendTask = nil
        eventTask?.cancel()
        eventTask = nil
        commitSignal?.finish()
        commitSignal = nil
        isCommitting = false
        await client?.disconnect()
    }

    static func makeClient(
        provider: VoiceInkProviderKind
    ) throws -> any LLMkit.StreamingTranscriptionProvider {
        switch provider {
        case .assemblyAI:
            return LLMkit.AssemblyAIStreamingClient()
        case .deepgram:
            return LLMkit.DeepgramStreamingClient()
        case .elevenLabs:
            return LLMkit.ElevenLabsStreamingClient()
        case .mistral:
            return LLMkit.MistralStreamingClient()
        case .soniox:
            return LLMkit.SonioxStreamingClient()
        case .speechmatics:
            return LLMkit.SpeechmaticsStreamingClient()
        case .xai:
            return LLMkit.XAIStreamingClient()
        case .groq, .openAI, .cerebras, .gemini, .localWhisper, .voiceInk:
            throw VoiceInkIOSStreamingError.unsupportedProvider(provider)
        }
    }
}
