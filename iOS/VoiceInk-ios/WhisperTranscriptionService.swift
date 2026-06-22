//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import VoiceInkCore

struct WhisperTranscriptionService: VoiceInkAudioTranscriptionService {
    private let logger = VoiceInkIOSLogger.localWhisper
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
        logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSStartingLocalTranscriptionMessage, privacy: .public)")
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

                    logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSUsingModelMessage(modelPath: modelPath), privacy: .public)")

                    do {
                        return VoiceInkLocalWhisperContextPlan(
                            context: try await WhisperContext.createContext(path: modelPath),
                            shouldReleaseContext: true
                        )
                    } catch {
                        logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSModelLoadFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(
                            for: .modelLoadFailed,
                            platform: failurePlatform
                        )
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        guard let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL) else {
                            logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage, privacy: .public)")
                            return nil
                        }
                        logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSProcessedAudioSamplesMessage(count: samples.count), privacy: .public)")
                        return samples
                    } catch {
                        logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
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
                        logger.error("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSTranscriptionFailedMessage, privacy: .public)")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSContextResourcesReleasedMessage, privacy: .public)")
                }
            )
        )

        logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSTranscriptionCompletedMessage, privacy: .public)")
        return transcription
    }
    
}
