//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import OSLog
import VoiceInkCore

struct WhisperTranscriptionService: VoiceInkAudioTranscriptionService {
    private let logger = VoiceInkIOSLogger.localWhisper
    
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
        let request = VoiceInkLocalWhisperTranscriptionRequest.iOS(
            audioURL: fileURL,
            language: language,
            prompt: prompt
        )

        let transcription = try await VoiceInkLocalWhisperTranscriptionFlow.transcribe(
            request: request,
            actions: VoiceInkLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    let modelManager = LocalModelManager.shared
                    let retained = try await modelManager.retainedContext(
                        forRuntimeModelName: model
                    )

                    logger.notice("\(VoiceInkLocalWhisperTranscriptionDiagnostics.iOSUsingModelMessage(modelPath: retained.modelPath), privacy: .public)")

                    return VoiceInkLocalWhisperContextPlan(
                        context: retained.context,
                        shouldReleaseContext: false
                    )
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
                    let cancellationToken = VoiceInkWhisperCancellationToken()
                    let success = await withTaskCancellationHandler {
                        if Task.isCancelled {
                            cancellationToken.cancel()
                        }
                        return await context.fullTranscribe(
                            samples: samples,
                            language: language,
                            prompt: prompt,
                            cancellationToken: cancellationToken
                        )
                    } onCancel: {
                        cancellationToken.cancel()
                    }
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
