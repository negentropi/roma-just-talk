import Foundation
import SwiftUI
import SwiftData
import os
import VoiceInkCore

@MainActor
class TranscriptionServiceRegistry {
    private weak var modelProvider: (any WhisperModelProvider)?
    private let modelsDirectory: URL
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "TranscriptionServiceRegistry")

    private(set) lazy var localTranscriptionService = WhisperTranscriptionService(
        modelsDirectory: modelsDirectory,
        modelProvider: modelProvider
    )
    private(set) lazy var cloudTranscriptionService = CloudTranscriptionService(modelContext: modelContext)
    private(set) lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
    private(set) lazy var fluidAudioTranscriptionService = FluidAudioTranscriptionService()

    init(modelProvider: any WhisperModelProvider, modelsDirectory: URL, modelContext: ModelContext) {
        self.modelProvider = modelProvider
        self.modelsDirectory = modelsDirectory
        self.modelContext = modelContext
    }

    func service(for route: VoiceInkTranscriptionServiceRoute) -> TranscriptionService {
        switch route {
        case .localWhisper:
            return localTranscriptionService
        case .localFluidAudio:
            return fluidAudioTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        case .cloud:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.transcriptionSessionRouteFacts.serviceRoute)
        logger.debug("Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(
        for model: any TranscriptionModel,
        onPartialTranscript: ((String) -> Void)? = nil,
        forceStreaming: Bool = false
    ) -> TranscriptionSession {
        let routePlan = model.transcriptionSessionRouteFacts.plan(forceStreaming: forceStreaming)

        switch routePlan.executionPlan {
        case .streaming(let serviceRoute, let streamingAdapterKind, let usesRollingPreload, let finalCommitTimeoutNanoseconds):
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                streamingAdapterKind: streamingAdapterKind,
                fluidAudioService: streamingAdapterKind == .localFluidAudio ? fluidAudioTranscriptionService : nil,
                fluidAudioStreamingConfig: usesRollingPreload ? .rollingPreload : nil,
                finalCommitTimeoutNanoseconds: finalCommitTimeoutNanoseconds,
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: serviceRoute)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        case .file(let serviceRoute):
            return FileTranscriptionSession(service: service(for: serviceRoute))
        }
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
