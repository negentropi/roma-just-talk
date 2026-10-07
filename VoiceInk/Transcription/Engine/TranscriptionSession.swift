import Foundation
import os

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    var audioChunkCallback: ((Data) -> Void)? { get }
    func prepare(model: any TranscriptionModel) async throws

    /// Called after recording stops. Returns the final transcribed text.
    func transcribe(audioURL: URL) async throws -> String

    /// Cancel the session and clean up resources.
    func cancel()
}

// MARK: - File-Based Session

/// File-based session: records to file, uploads after stop.
@MainActor
final class FileTranscriptionSession: TranscriptionSession {
    private let service: TranscriptionService
    private var model: (any TranscriptionModel)?

    init(service: TranscriptionService) {
        self.service = service
    }

    var audioChunkCallback: ((Data) -> Void)? { nil }

    func prepare(model: any TranscriptionModel) async throws {
        self.model = model
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    func cancel() {
        // No-op for file-based transcription
    }
}

// MARK: - Streaming Session

/// Streaming session with automatic fallback to file-based upload on failure.
@MainActor
final class StreamingTranscriptionSession: TranscriptionSession {
    private let streamingService: StreamingTranscriptionService
    private let fallbackService: TranscriptionService
    private var model: (any TranscriptionModel)?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    var audioChunkCallback: ((Data) -> Void)? {
        let service = streamingService
        return { [weak service] data in service?.sendAudioChunk(data) }
    }

    func prepare(model: any TranscriptionModel) async throws {
        self.model = model
        logger.notice("Streaming session prepare model=\(model.displayName, privacy: .public)")
        try await streamingService.startStreaming(model: model)
        try Task.checkCancellation()
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        do {
            let start = Date()
            logger.notice("Streaming stop/transcribe started model=\(model.displayName, privacy: .public)")
            let text = try await streamingService.stopAndGetFinalText()
            logger.notice("Streaming transcript received elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
            return text
        } catch {
            logger.error("❌ Streaming failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            streamingService.cancel()
        }

        let fallbackStart = Date()
        logger.notice("Using batch fallback for \(model.displayName, privacy: .public) file=\(audioURL.lastPathComponent, privacy: .public)")
        let text = try await fallbackService.transcribe(audioURL: audioURL, model: model)
        logger.notice("Batch fallback completed elapsed=\(Date().timeIntervalSince(fallbackStart), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
        return text
    }

    func cancel() {
        streamingService.cancel()
    }
}
