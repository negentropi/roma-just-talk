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

        // Check if the required model is already loaded in the model provider
        if let provider = modelProvider,
           await provider.isModelLoaded,
           let loadedContext = await provider.whisperContext,
           await provider.loadedWhisperModel?.name == model.name {

            logger.notice("Using already loaded model: \(model.name, privacy: .public)")
            whisperContext = loadedContext
        } else {
            // Resolve the on-disk URL using the provider's availableModels (covers imports)
            let availableModels = await modelProvider?.availableModels ?? []
            guard let modelURL = VoiceInkWhisperModelFiles.availableLocalModelFileURL(
                forModelName: model.name,
                in: availableModels
            ) else {
                logger.error("❌ Model file not found for: \(model.name, privacy: .public)")
                throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: failurePlatform)
            }

            logger.notice("Loading model: \(model.name, privacy: .public)")
            do {
                whisperContext = try await WhisperContext.createContext(path: modelURL.path)
            } catch {
                logger.error("❌ Failed to load model: \(model.name, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: failurePlatform)
            }
        }

        guard let whisperContext = whisperContext else {
            logger.error("❌ Cannot transcribe: Model could not be loaded")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: failurePlatform)
        }

        guard let data = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL) else {
            logger.error("❌ Failed to process audio samples for local Whisper transcription.")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: failurePlatform)
        }

        let currentPrompt = VoiceInkTranscriptionPromptPreference.localWhisperPromptForSelectedLanguage()

        // Transcribe
        let success = await whisperContext.fullTranscribe(
            samples: data,
            language: VoiceInkTranscriptionLanguagePreference.selectedLanguage(),
            prompt: currentPrompt
        )

        guard success else {
            logger.error("❌ Core transcription engine failed (whisper_full).")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: failurePlatform)
        }

        let text = await whisperContext.getTranscription()

        logger.notice("Whisper transcription completed successfully.")

        // Only release resources if we created a new context (not using the shared one)
        if await modelProvider?.whisperContext !== whisperContext {
            await whisperContext.releaseResources()
            self.whisperContext = nil
        }

        return text
    }
}
