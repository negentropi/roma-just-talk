//
//  WhisperTranscriptionService.swift
//  RomaJustTalk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import OSLog
import RomaCore

struct WhisperTranscriptionService: RomaAudioTranscriptionService {
    private let logger = RomaIOSLogger.localWhisper
    
    /// Transcribe audio file using local Whisper model
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        customVocabulary: [String] = []
    ) async throws -> String {
        logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.iOSStartingLocalTranscriptionMessage, privacy: .public)")
        let request = RomaLocalWhisperTranscriptionRequest.iOS(
            audioURL: fileURL,
            language: language,
            prompt: prompt
        )

        let transcription = try await RomaLocalWhisperTranscriptionFlow.transcribe(
            request: request,
            actions: RomaLocalWhisperTranscriptionActions<WhisperContext>(
                resolveContext: {
                    let modelManager = LocalModelManager.shared
                    let retained = try await modelManager.retainedContext(
                        forRuntimeModelName: model
                    )

                    logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.iOSUsingModelMessage(modelPath: retained.modelPath), privacy: .public)")

                    return RomaLocalWhisperContextPlan(
                        context: retained.context,
                        shouldReleaseContext: false
                    )
                },
                readAudioSamples: { audioURL in
                    do {
                        guard let samples = try RomaWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL) else {
                            logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage, privacy: .public)")
                            return nil
                        }
                        logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.iOSProcessedAudioSamplesMessage(count: samples.count), privacy: .public)")
                        return samples
                    } catch {
                        logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.iOSAudioProcessingFailedMessage(localizedDescription: error.localizedDescription), privacy: .public)")
                        throw error
                    }
                },
                runTranscription: { context, samples, language, prompt in
                    let cancellationToken = RomaWhisperCancellationToken()
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
                        logger.error("\(RomaLocalWhisperTranscriptionDiagnostics.iOSTranscriptionFailedMessage, privacy: .public)")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.iOSContextResourcesReleasedMessage, privacy: .public)")
                }
            )
        )

        logger.notice("\(RomaLocalWhisperTranscriptionDiagnostics.iOSTranscriptionCompletedMessage, privacy: .public)")
        return transcription
    }
    
}
