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
        
        // Get available model
        let modelManager = LocalModelManager.shared
        guard let modelPath = await modelManager.modelPath(for: model) else {
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelUnavailable, platform: failurePlatform)
        }
        
        print("WhisperTranscriptionService: Using model at \(modelPath)")
        
        // Load Whisper context
        let context: WhisperContext
        do {
            context = try await WhisperContext.createContext(path: modelPath)
        } catch {
            print("WhisperTranscriptionService: Failed to load model: \(error)")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .modelLoadFailed, platform: failurePlatform)
        }
        
        // Process audio file (expecting WAV format from recorder)
        let audioSamples: [Float]
        do {
            guard let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: fileURL) else {
                throw VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: failurePlatform)
            }
            audioSamples = samples
            print("WhisperTranscriptionService: Processed \(audioSamples.count) audio samples")
        } catch {
            print("WhisperTranscriptionService: Audio processing failed: \(error)")
            // Clean up resources before throwing
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .audioProcessingFailed, platform: failurePlatform)
        }
        
        // Perform transcription
        let success = await context.fullTranscribe(
            samples: audioSamples,
            language: language,
            prompt: prompt ?? ""
        )
        
        if success {
            let transcription = await context.getTranscription()
            // Clean up resources
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            print("WhisperTranscriptionService: Transcription completed successfully")
            return transcription
        } else {
            // Clean up resources before throwing error
            await context.releaseResources()
            print("WhisperTranscriptionService: Whisper context resources released.")
            print("WhisperTranscriptionService: Transcription failed")
            throw VoiceInkLocalWhisperFailurePolicy.error(for: .transcriptionFailed, platform: failurePlatform)
        }
    }
    
}
