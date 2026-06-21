//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import os
import VoiceInkCore

struct WhisperTranscriptionService: VoiceInkAudioTranscriptionService {
    private let logger = Logger(
        subsystem: VoiceInkAppIdentity.loggingSubsystem,
        category: "WhisperTranscriptionService"
    )
    private let failurePlatform = VoiceInkLocalWhisperPlatform.iOS
    
    /// Transcribe audio file using local Whisper model
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        logger.notice("Starting local transcription.")
        let failurePlatform = self.failurePlatform

        let transcription = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: VoiceInkLocalWhisperTranscriptionRequest(
                audioURL: fileURL,
                language: language,
                prompt: prompt ?? "",
                failurePlatform: failurePlatform
            ),
            actions: VoiceInkLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    let modelManager = LocalModelManager.shared
                    guard let modelPath = await modelManager.modelPath(for: model) else {
                        throw VoiceInkLocalWhisperFailurePolicy.error(
                            for: .modelUnavailable,
                            platform: failurePlatform
                        )
                    }

                    logger.notice("Using model at \(modelPath, privacy: .public)")

                    do {
                        return VoiceInkLocalWhisperContextPlan(
                            context: try await WhisperContext.createContext(path: modelPath),
                            shouldReleaseContext: true
                        )
                    } catch {
                        logger.error("Failed to load model: \(error.localizedDescription, privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(
                            for: .modelLoadFailed,
                            platform: failurePlatform
                        )
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        guard let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL) else {
                            logger.error("Audio processing failed.")
                            return nil
                        }
                        logger.notice("Processed \(samples.count, privacy: .public) audio samples.")
                        return samples
                    } catch {
                        logger.error("Audio processing failed: \(error.localizedDescription, privacy: .public)")
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
                        logger.error("Transcription failed.")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    logger.notice("Whisper context resources released.")
                }
            )
        )

        logger.notice("Transcription completed successfully.")
        return transcription
    }
    
}
