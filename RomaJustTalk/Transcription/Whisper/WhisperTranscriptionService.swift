import Foundation
import AVFoundation
import os
import RomaCore

class WhisperTranscriptionService: TranscriptionService {

    private var whisperContext: WhisperContext?
    private let logger = Logger(
        subsystem: RomaAppIdentity.loggingSubsystem,
        category: RomaMacOSLogCategory.whisperTranscriptionService
    )
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let request = RomaLocalWhisperTranscriptionRequest.macOS(audioURL: audioURL, isMultilingual: model.isMultilingualModel)
        guard model.provider == .whisper else {
            throw RomaLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: request.failurePlatform)
        }

        logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.macOSInitiatingLocalTranscriptionMessage(modelDisplayName: model.displayName), privacy: .public)")

        let text = try await RomaLocalWhisperTranscriptionFlow.transcribe(
            request: request,
            actions: RomaLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    if let provider = self.modelProvider,
                       await provider.isModelLoaded,
                       let loadedContext = await provider.whisperContext,
                       await provider.loadedWhisperModel?.name == model.name {

                        self.logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.macOSUsingLoadedModelMessage(modelName: model.name), privacy: .public)")
                        self.whisperContext = loadedContext
                        return RomaLocalWhisperContextPlan(
                            context: loadedContext,
                            shouldReleaseContext: false
                        )
                    }

                    let availableModels = await self.modelProvider?.availableModels ?? []
                    guard let modelURL = RomaWhisperModelFiles.availableLocalModelFileURL(
                        forModelName: model.name,
                        in: availableModels
                    ) else {
                        self.logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.macOSModelFileNotFoundMessage(modelName: model.name), privacy: .public)")
                        throw RomaLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: request.failurePlatform)
                    }

                    self.logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.macOSLoadingModelMessage(modelName: model.name), privacy: .public)")
                    do {
                        let context = try await WhisperContext.createContext(path: modelURL.path)
                        self.whisperContext = context
                        return RomaLocalWhisperContextPlan(
                            context: context,
                            shouldReleaseContext: true,
                            shouldReleaseContextOnFailure: false
                        )
                    } catch {
                        self.logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.macOSModelLoadFailedMessage(modelName: model.name, localizedDescription: error.localizedDescription), privacy: .public)")
                        throw RomaLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: request.failurePlatform)
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        let samples = try RomaWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL)
                        if samples == nil {
                            self.logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.macOSAudioSamplesProcessingFailedMessage, privacy: .public)")
                        }
                        return samples
                    } catch {
                        self.logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.macOSAudioSamplesProcessingFailedMessage, privacy: .public)")
                        throw error
                    }
                },
                runTranscription: { context, samples, language, prompt in
                    let success = await context.fullTranscribe(
                        samples: samples,
                        language: language,
                        prompt: prompt
                    )
                    if !success {
                        self.logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.macOSCoreTranscriptionFailedMessage, privacy: .public)")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    if self.whisperContext === context {
                        self.whisperContext = nil
                    }
                }
            )
        )

        logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.macOSTranscriptionCompletedMessage, privacy: .public)")

        return text
    }
}
