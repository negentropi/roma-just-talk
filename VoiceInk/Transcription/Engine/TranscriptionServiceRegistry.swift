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
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: VoiceInkMacOSLogCategory.transcriptionServiceRegistry
    )

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
        let message = VoiceInkTranscriptionServiceRouteDiagnostics.transcribingMessage(
            modelDisplayName: model.displayName,
            serviceTypeDescription: String(describing: type(of: service))
        )
        logger.debug("\(message, privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(
        for model: any TranscriptionModel,
        onPartialTranscript: ((String) -> Void)? = nil
    ) -> TranscriptionSession {
        let routePlan = model.transcriptionSessionRouteFacts.plan()

        return routePlan.executionPlan.applyRuntimeState(
            file: { serviceRoute -> TranscriptionSession in
                FileTranscriptionSession(service: service(for: serviceRoute))
            },
            streaming: { request -> TranscriptionSession in
                let streamingService = StreamingTranscriptionService(
                    modelContext: modelContext,
                    streamingAdapterKind: request.adapterKind,
                    fluidAudioService: request.adapterKind == .localFluidAudio ? fluidAudioTranscriptionService : nil,
                    finalCommitTimeoutNanoseconds: request.finalCommitTimeoutNanoseconds,
                    onPartialTranscript: onPartialTranscript
                )
                let fallback = service(for: request.serviceRoute)
                return StreamingTranscriptionSession(
                    streamingService: streamingService,
                    fallbackService: fallback
                )
            }
        )
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
