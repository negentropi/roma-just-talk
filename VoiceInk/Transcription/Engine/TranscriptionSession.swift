import Foundation
import os
import VoiceInkCore

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)?

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

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model
        return nil
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
    private var streamingFailed = false
    private var startupTask: Task<Void, Never>?
    private var startupTaskID: UUID?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)? {
        self.model = model
        logger.notice("Streaming session prepare model=\(model.displayName, privacy: .public)")

        // Return callback immediately; WebSocket connects in background
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        startupTask?.cancel()
        let taskID = UUID()
        startupTaskID = taskID
        startupTask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                if self.startupTaskID == taskID {
                    self.startupTask = nil
                    self.startupTaskID = nil
                }
            }
            guard !Task.isCancelled else { return }

            do {
                let start = Date()
                try await self.streamingService.startStreaming(model: model)
                guard !Task.isCancelled else {
                    self.streamingService.cancel()
                    return
                }
                self.logger.notice("Streaming session connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
            } catch is CancellationError {
                self.streamingService.cancel()
            } catch {
                guard !Task.isCancelled else { return }
                let desc = error.localizedDescription
                self.logger.error("❌ Failed to start streaming, will fall back to batch: \(desc, privacy: .public)")
                self.streamingFailed = true
            }
        }

        return callback
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let model = model else {
            throw VoiceInkEngineError.transcriptionFailed
        }

        switch VoiceInkStreamingStartupResolutionPolicy.plan(
            hasPendingStartup: startupTask != nil,
            streamingFailed: streamingFailed,
            supportsRecordedFileTranscription: model.supportsRecordedFileTranscription
        ) {
        case .proceed:
            break
        case .cancelStartupAndUseRecordedFileFallback:
            logger.notice("Streaming startup still pending at commit; using recorded-file fallback without waiting model=\(model.displayName, privacy: .public)")
            startupTask?.cancel()
            startupTask = nil
            startupTaskID = nil
            streamingFailed = true
            streamingService.cancel()
        case .waitForStreamingStartup:
            guard let startupTask else { break }
            let waitStart = Date()
            logger.notice("Streaming-only transcribe waiting for startup model=\(model.displayName, privacy: .public)")
            await startupTask.value
            logger.notice("Streaming-only startup wait finished elapsed=\(Date().timeIntervalSince(waitStart), format: .fixed(precision: 3), privacy: .public)s")
        }

        return try await VoiceInkStreamingFallbackPolicy.run(
            streamingFailed: streamingFailed,
            streaming: {
                let start = Date()
                self.logger.notice("Streaming stop/transcribe started model=\(model.displayName, privacy: .public)")
                let text = try await streamingService.stopAndGetFinalText()
                self.logger.notice("Streaming transcript received elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
                return text
            },
            onStreamingFailure: { error in
                self.logger.error("❌ Streaming failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            },
            cancelStreaming: {
                streamingService.cancel()
            },
            fallback: {
                let fallbackStart = Date()
                self.logger.notice("Using batch fallback for \(model.displayName, privacy: .public) file=\(audioURL.lastPathComponent, privacy: .public)")
                let text = try await self.fallbackService.transcribe(audioURL: audioURL, model: model)
                self.logger.notice("Batch fallback completed elapsed=\(Date().timeIntervalSince(fallbackStart), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
                return text
            }
        )
    }

    func cancel() {
        startupTask?.cancel()
        startupTask = nil
        startupTaskID = nil
        streamingService.cancel()
    }
}
