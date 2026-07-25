import Foundation
import os
import VoiceInkCore

/// Encapsulates a single recording-to-transcription lifecycle (streaming or file-based).
@MainActor
protocol TranscriptionSession: AnyObject {
    /// Prepares the session. Returns an audio chunk callback for streaming, or nil for file-based.
    func prepare(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws -> ((Data) -> Void)?

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

    func prepare(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws -> ((Data) -> Void)? {
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
    private var latencyTraceToken: VoiceInkLatencyTrace.Token?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "StreamingTranscriptionSession")

    init(streamingService: StreamingTranscriptionService, fallbackService: TranscriptionService) {
        self.streamingService = streamingService
        self.fallbackService = fallbackService
    }

    func prepare(
        model: any TranscriptionModel,
        latencyTraceToken: VoiceInkLatencyTrace.Token?
    ) async throws -> ((Data) -> Void)? {
        // Sessions own one recording lifecycle. Reuse would require a fresh streaming
        // service because cancellation permanently closes its audio chunk stream.
        guard self.model == nil else {
            throw VoiceInkEngineError.transcriptionFailed
        }
        self.model = model
        streamingFailed = false
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken
        self.latencyTraceToken = traceToken
        latencyTrace.event(
            "streaming_session.prepare.enter",
            details: "model=\(model.displayName) supportsBatch=\(model.supportsRecordedFileTranscription)",
            token: traceToken
        )
        logger.notice("Streaming session prepare model=\(model.displayName, privacy: .public)")

        // Return callback immediately; WebSocket connects in background
        let service = streamingService
        let callback: (Data) -> Void = { [weak service] data in
            service?.sendAudioChunk(data)
        }

        let taskID = UUID()
        startupTaskID = taskID
        startupTask = Task { [weak self] in
            guard let self = self else { return }
            latencyTrace.event("streaming_startup.task.enter", token: traceToken)
            defer {
                if self.startupTaskID == taskID {
                    self.startupTask = nil
                    self.startupTaskID = nil
                }
            }
            guard !Task.isCancelled else { return }

            let span = latencyTrace.begin("streaming_startup.connect", token: traceToken)
            do {
                let start = Date()
                try await self.streamingService.startStreaming(
                    model: model,
                    latencyTraceToken: traceToken
                )
                latencyTrace.end(span, details: "result=success")
                guard !Task.isCancelled else {
                    latencyTrace.event("streaming_startup.cancelled_after_connect", token: traceToken)
                    self.streamingService.cancel(latencyTraceToken: traceToken)
                    return
                }
                self.logger.notice("Streaming session connected model=\(model.displayName, privacy: .public) elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s")
            } catch is CancellationError {
                latencyTrace.end(span, details: "result=cancelled")
                latencyTrace.event("streaming_startup.cancelled", token: traceToken)
                self.streamingService.cancel(latencyTraceToken: traceToken)
            } catch {
                latencyTrace.end(
                    span,
                    details: "result=failure error=\(String(describing: type(of: error)))"
                )
                guard !Task.isCancelled else { return }
                latencyTrace.event(
                    "streaming_startup.failed",
                    details: "error=\(String(describing: type(of: error)))",
                    token: traceToken
                )
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
        let latencyTrace = VoiceInkLatencyTrace.shared
        let traceToken = latencyTraceToken

        let startupResolution = VoiceInkStreamingStartupResolutionPolicy.plan(
            hasPendingStartup: startupTask != nil,
            streamingFailed: streamingFailed,
            supportsRecordedFileTranscription: model.supportsRecordedFileTranscription
        )
        latencyTrace.event(
            "streaming_session.transcribe.enter",
            details: "startupPending=\(startupTask != nil) streamingFailed=\(streamingFailed) resolution=\(String(describing: startupResolution))",
            token: traceToken
        )

        switch startupResolution {
        case .proceed:
            break
        case .cancelStartupAndUseRecordedFileFallback:
            latencyTrace.event("streaming_session.startup_cancel_for_batch", token: traceToken)
            logger.notice("Streaming startup still pending at commit; using recorded-file fallback without waiting model=\(model.displayName, privacy: .public)")
            startupTask?.cancel()
            startupTask = nil
            startupTaskID = nil
            streamingFailed = true
            streamingService.cancel(latencyTraceToken: traceToken)
        case .waitForStreamingStartup:
            guard let startupTask else { break }
            let startupWaitSpan = latencyTrace.begin("streaming_session.startup_wait", token: traceToken)
            let waitStart = Date()
            logger.notice("Streaming-only transcribe waiting for startup model=\(model.displayName, privacy: .public)")
            await startupTask.value
            latencyTrace.end(startupWaitSpan)
            logger.notice("Streaming-only startup wait finished elapsed=\(Date().timeIntervalSince(waitStart), format: .fixed(precision: 3), privacy: .public)s")
        }

        let fallbackPolicyCheckpoint = latencyTrace.executorEnqueued(
            "streaming_session.fallback_policy",
            details: "streamingFailed=\(streamingFailed)",
            token: traceToken
        )
        return try await VoiceInkStreamingFallbackPolicy.run(
            streamingFailed: streamingFailed,
            streaming: {
                if !streamingFailed {
                    latencyTrace.executorResumed(fallbackPolicyCheckpoint)
                }
                let span = latencyTrace.begin("streaming_session.finalize_stream", token: traceToken)
                let start = Date()
                self.logger.notice("Streaming stop/transcribe started model=\(model.displayName, privacy: .public)")
                do {
                    let text = try await streamingService.stopAndGetFinalText(
                        latencyTraceToken: traceToken
                    )
                    latencyTrace.end(
                        span,
                        details: "result=success chars=\(text.count)"
                    )
                    self.logger.notice("Streaming transcript received elapsed=\(Date().timeIntervalSince(start), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
                    return text
                } catch {
                    latencyTrace.end(
                        span,
                        details: "result=failure error=\(String(describing: type(of: error)))"
                    )
                    throw error
                }
            },
            onStreamingFailure: { error in
                self.logger.error("❌ Streaming failed, falling back to batch: \(error.localizedDescription, privacy: .public)")
            },
            cancelStreaming: {
                if streamingFailed {
                    latencyTrace.executorResumed(fallbackPolicyCheckpoint)
                }
                streamingService.cancel(latencyTraceToken: traceToken)
            },
            fallback: {
                let span = latencyTrace.begin("streaming_session.batch_fallback", token: traceToken)
                let fallbackStart = Date()
                self.logger.notice("Using batch fallback for \(model.displayName, privacy: .public) file=\(audioURL.lastPathComponent, privacy: .public)")
                do {
                    let text = try await self.fallbackService.transcribe(audioURL: audioURL, model: model)
                    latencyTrace.end(
                        span,
                        details: "result=success chars=\(text.count)"
                    )
                    self.logger.notice("Batch fallback completed elapsed=\(Date().timeIntervalSince(fallbackStart), format: .fixed(precision: 3), privacy: .public)s chars=\(text.count, privacy: .public)")
                    return text
                } catch {
                    latencyTrace.end(
                        span,
                        details: "result=failure error=\(String(describing: type(of: error)))"
                    )
                    throw error
                }
            }
        )
    }

    func cancel() {
        let traceToken = latencyTraceToken
        startupTask?.cancel()
        startupTask = nil
        startupTaskID = nil
        streamingService.cancel(latencyTraceToken: traceToken)
    }
}
