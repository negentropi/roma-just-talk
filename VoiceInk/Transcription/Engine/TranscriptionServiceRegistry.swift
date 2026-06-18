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
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionServiceRegistry")

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

    func service(for provider: ModelProvider) -> TranscriptionService {
        switch provider {
        case .whisper:
            return localTranscriptionService
        case .fluidAudio:
            return fluidAudioTranscriptionService
        case .nativeApple:
            return nativeAppleTranscriptionService
        default:
            return cloudTranscriptionService
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let service = service(for: model.provider)
        logger.debug("Transcribing with \(model.displayName, privacy: .public) using \(String(describing: type(of: service)), privacy: .public)")
        return try await service.transcribe(audioURL: audioURL, model: model)
    }

    /// Creates a streaming or file-based session depending on the model's capabilities.
    func createSession(
        for model: any TranscriptionModel,
        onPartialTranscript: ((String) -> Void)? = nil,
        forceStreaming: Bool = false
    ) -> TranscriptionSession {
        let shouldUseStreaming = forceStreaming
            ? model.supportsStreaming
            : VoiceInkTranscriptionStreamingPreference.shouldUseStreaming(for: model.streamingPreferenceSnapshot)

        if shouldUseStreaming {
            let streamingService = StreamingTranscriptionService(
                modelContext: modelContext,
                fluidAudioService: model.provider == .fluidAudio ? fluidAudioTranscriptionService : nil,
                fluidAudioStreamingConfig: forceStreaming && model.provider == .fluidAudio ? .rollingPreload : nil,
                finalCommitTimeoutNanoseconds: VoiceInkStreamingFinalCommitTimeout.nanoseconds(
                    for: model.provider == .fluidAudio ? .localFluidAudio : .cloud
                ),
                onPartialTranscript: onPartialTranscript
            )
            let fallback = service(for: model.provider)
            return StreamingTranscriptionSession(streamingService: streamingService, fallbackService: fallback)
        } else {
            return FileTranscriptionSession(service: service(for: model.provider))
        }
    }

    func cleanup() async {
        await fluidAudioTranscriptionService.cleanup()
    }
}
