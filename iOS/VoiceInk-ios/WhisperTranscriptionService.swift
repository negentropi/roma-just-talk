//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation
import VoiceInkCore

struct WhisperTranscriptionService: VoiceInkAudioTranscriptionService {
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
        print("WhisperTranscriptionService: Starting local transcription")
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

                    print("WhisperTranscriptionService: Using model at \(modelPath)")

                    do {
                        return VoiceInkLocalWhisperContextPlan(
                            context: try await WhisperContext.createContext(path: modelPath),
                            shouldReleaseContext: true
                        )
                    } catch {
                        print("WhisperTranscriptionService: Failed to load model: \(error)")
                        throw VoiceInkLocalWhisperFailurePolicy.error(
                            for: .modelLoadFailed,
                            platform: failurePlatform
                        )
                    }
                },
                readAudioSamples: { audioURL in
                    do {
                        guard let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: audioURL) else {
                            print("WhisperTranscriptionService: Audio processing failed")
                            return nil
                        }
                        print("WhisperTranscriptionService: Processed \(samples.count) audio samples")
                        return samples
                    } catch {
                        print("WhisperTranscriptionService: Audio processing failed: \(error)")
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
                        print("WhisperTranscriptionService: Transcription failed")
                    }
                    return success
                },
                transcriptionText: { context in
                    await context.getTranscription()
                },
                releaseContext: { context in
                    await context.releaseResources()
                    print("WhisperTranscriptionService: Whisper context resources released.")
                }
            )
        )

        print("WhisperTranscriptionService: Transcription completed successfully")
        return transcription
    }
    
}
