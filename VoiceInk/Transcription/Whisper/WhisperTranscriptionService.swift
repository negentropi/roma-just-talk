import Foundation
import AVFoundation
import os
import VoiceInkCore

class WhisperTranscriptionService: TranscriptionService {

    private var whisperContext: WhisperContext?
    private let logger = Logger(subsystem: VoiceInkAppIdentity.loggingSubsystem, category: "WhisperTranscriptionService")
    private let modelsDirectory: URL
    private weak var modelProvider: (any WhisperModelProvider)?
    private let failurePlatform = VoiceInkLocalWhisperPlatform.macOS

    init(modelsDirectory: URL, modelProvider: (any WhisperModelProvider)? = nil) {
        self.modelsDirectory = modelsDirectory
        self.modelProvider = modelProvider
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard model.provider == .whisper else {
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: failurePlatform)
        }

        logger.notice("Initiating local transcription for model: \(model.displayName, privacy: .public)")
        let failurePlatform = self.failurePlatform

        let text = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: audioURL,
                language: VoiceInkTranscriptionLanguagePreference.selectedLanguage(),
                prompt: VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage(),
                failurePlatform: failurePlatform,
                mapsThrownAudioSampleErrors: false
            ),
            actions: VoiceInkLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    if let provider = self.modelProvider,
                       await provider.isModelLoaded,
                       let loadedContext = await provider.whisperContext,
                       await provider.loadedWhisperModel?.name == model.name {

                        self.logger.notice("Using already loaded model: \(model.name, privacy: .public)")
                        self.whisperContext = loadedContext
                        return VoiceInkLocalWhisperContextPlan(
                            context: loadedContext,
                            shouldReleaseContext: false
                        )
                    }

                    let availableModels = await self.modelProvider?.availableModels ?? []
                    guard let modelURL = VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                        forModelName: model.name,
                        in: availableModels
                    ) else {
                        self.logger.error("❌ Model file not found for: \(model.name, privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: failurePlatform)
                    }

                    self.logger.notice("Loading model: \(model.name, privacy: .public)")
                    do {
                        let context = try await WhisperContext.createContext(path: modelURL.path)
                        self.whisperContext = context
                        return VoiceInkLocalWhisperContextPlan(
                            context: context,
                            shouldReleaseContext: true,
                            shouldReleaseContextOnFailure: false
                        )
                    } catch {
                        self.logger.error("❌ Failed to load model: \(model.name, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: failurePlatform)
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL)
                        if samples == nil {
                            self.logger.error("❌ Failed to process audio samples for local Whisper transcription.")
                        }
                        return samples
                    } catch {
                        self.logger.error("❌ Failed to process audio samples for local Whisper transcription.")
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
                        self.logger.error("❌ Core transcription engine failed (whisper_full).")
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

        logger.notice("Whisper transcription completed successfully.")

        return text
    }
}
